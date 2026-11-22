import Foundation

// Wave X3: building the gallery in the background. For each cast member of a title: fetch a few TMDB
// portraits, find the one clear face in each, embed it and cache it. The embedding itself is behind the
// `FaceEmbedder` protocol; X4 plugs in Vision + Core ML (SFace), the tests use a fake.

/// A face found and embedded in a still picture.
public struct EmbeddedFace: Sendable, Equatable {
    public var face: DetectedFace
    public var embedding: FaceEmbedding
    public init(face: DetectedFace, embedding: FaceEmbedding) { self.face = face; self.embedding = embedding }
}

/// Detects, aligns (`FaceAlignment`) and embeds every face in a picture.
public protocol FaceEmbedder: Sendable {
    /// Identifies model and preprocessing; part of the cache key, so a new model recomputes the gallery.
    var modelID: String { get }
    /// All faces in an encoded picture (JPEG/PNG, as downloaded). Returns [] when the picture shows no face.
    /// Throws only for failures worth retrying (model not loaded, prediction or Vision error, cancellation):
    /// the gallery builder then caches nothing for that person and tries again on the next run.
    func faces(inImage data: Data) async throws -> [EmbeddedFace]
}

public struct XRayGallerySettings: Sendable, Equatable {
    /// Candidates per title, in billing order (episode: episode cast and guests first).
    public var maxPeople: Int
    /// Portraits per person (best rated first).
    public var imagesPerPerson: Int
    /// A portrait counts only if its face is at least this wide (source pixels, h632 picture).
    public var minPortraitFaceWidth: Double
    /// Another face at least this share of the largest one's width makes the portrait ambiguous (group photo).
    public var secondFaceShare: Double
    /// Portraits lower than this (TMDB `height`) are skipped.
    public var minImageHeight: Int

    public init(maxPeople: Int = 60, imagesPerPerson: Int = 4, minPortraitFaceWidth: Double = 48,
                secondFaceShare: Double = 0.5, minImageHeight: Int = 300) {
        self.maxPeople = maxPeople; self.imagesPerPerson = imagesPerPerson
        self.minPortraitFaceWidth = minPortraitFaceWidth; self.secondFaceShare = secondFaceShare
        self.minImageHeight = minImageHeight
    }
}

public enum XRayGalleryPlan {
    /// Portraits to use: tall enough, best rated first, at most `max`.
    public static func pickImages(_ images: [TMDBProfileImage], settings: XRayGallerySettings) -> [TMDBProfileImage] {
        Array(images.filter { ($0.height ?? Int.max) >= settings.minImageHeight }.prefix(max(0, settings.imagesPerPerson)))
    }

    /// The single clear face of a portrait, or nil for none or more than one large face.
    public static func portraitFace(_ faces: [EmbeddedFace], settings: XRayGallerySettings) -> EmbeddedFace? {
        guard let big = faces.max(by: { $0.face.width < $1.face.width }), big.face.width >= settings.minPortraitFaceWidth else { return nil }
        let large = faces.filter { $0.face.width >= big.face.width * settings.secondFaceShare }
        return large.count == 1 ? big : nil
    }
}

/// At most `limit` requests per `window` seconds, handed out in order. The app keeps ONE `XRayGalleryBuilder`
/// (and so one pair of throttles) for all titles, so the background work stays well under TMDB's limit
/// (about 50 per second) and never competes with the UI.
public actor RequestThrottle {
    public let limit: Int
    public let window: TimeInterval
    let now: @Sendable () -> Date
    let sleep: APISleep
    private var recent: [Date] = []

    public init(limit: Int = 8, window: TimeInterval = 1, now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping APISleep = defaultAPISleep) {
        self.limit = max(1, limit); self.window = window; self.now = now; self.sleep = sleep
    }

    /// Waits for the next free slot: the n-th call starts no earlier than `window` after the (n − limit)-th.
    public func wait() async {
        let t = now()
        recent.removeAll { t.timeIntervalSince($0) >= window }
        let slot = recent.count >= limit ? max(t, recent[recent.count - limit].addingTimeInterval(window)) : t
        recent.append(slot)
        if slot > t { await sleep(slot.timeIntervalSince(t)) }
    }
}

/// Counts of one `prepare` run (for the `xray:` log line).
public struct XRayPrepareReport: Sendable, Equatable {
    public var title: String
    public var people = 0
    /// People whose embeddings were already cached.
    public var cached = 0
    /// People computed in this run.
    public var computed = 0
    /// People with at least one usable portrait after this run (cached or computed).
    public var usable = 0
    public var downloads = 0
    public var faces = 0
    /// Portraits without exactly one clear face.
    public var discarded = 0
    public var failures = 0
    public var castFromCache = false
    public var cancelled = false
    /// People cached with a short lifetime because some portraits failed.
    public var partial = 0
    /// Another `prepare` of the same title was already running; this one did nothing.
    public var alreadyRunning = false

    public init(title: String) { self.title = title }

    public var logLine: String {
        "xray: gallery \(title) people=\(people) cached=\(cached) computed=\(computed) usable=\(usable) "
            + "downloads=\(downloads) faces=\(faces) discarded=\(discarded) failures=\(failures)"
            + " partial=\(partial)" + (castFromCache ? " cast=cache" : " cast=tmdb") + (cancelled ? " cancelled" : "")
            + (alreadyRunning ? " already-running" : "")
    }
}

/// Background precompute of a title's gallery. Resumable: everything finished is cached at once, so a run that
/// is cancelled (playback stalls, user leaves) continues where it stopped the next time.
/// The app starts it with low priority after the first picture and cancels it while buffering.
public actor XRayGalleryBuilder {
    let tmdb: TMDBClient
    let images: HTTPFetching
    let embedder: FaceEmbedder
    let store: XRayStore
    let throttle: RequestThrottle
    let imageThrottle: RequestThrottle
    let settings: XRayGallerySettings
    let sleep: APISleep
    let log: (@Sendable (String) -> Void)?
    /// Wait before the one retry after HTTP 429.
    static let rateLimitPause: Double = 2
    /// Titles with a `prepare` in progress (actor reentrancy: a second call for the same title returns at once).
    private var running = Set<XRayTitleKey>()

    public init(tmdb: TMDBClient, images: HTTPFetching = URLSessionFetcher(), embedder: FaceEmbedder, store: XRayStore,
                throttle: RequestThrottle = RequestThrottle(),
                imageThrottle: RequestThrottle = RequestThrottle(limit: 20), settings: XRayGallerySettings = XRayGallerySettings(),
                sleep: @escaping APISleep = defaultAPISleep, log: (@Sendable (String) -> Void)? = nil) {
        self.tmdb = tmdb; self.images = images; self.embedder = embedder; self.store = store
        self.throttle = throttle; self.imageThrottle = imageThrottle; self.settings = settings; self.sleep = sleep; self.log = log
    }

    /// The candidates of a title: from the cache, else from TMDB (and cached for 30 days).
    public func cast(for key: XRayTitleKey) async throws -> (cast: [XRayCastEntry], fromCache: Bool) {
        if let r = await store.title(key) { return (r.cast, true) }
        // Each credits request gets its own throttle slot and 429 retry; a transient failure throws, so no
        // degraded list is ever cached (the next run asks again).
        let cast = try await tmdb.xrayCast(for: key) { op in try await self.limited(nil, op) }
        await store.store(XRayTitleRecord(key: key, cast: cast))
        return (cast, false)
    }

    /// Fetches and embeds what is missing for this title. Never throws: failures are counted and logged.
    @discardableResult
    public func prepare(_ key: XRayTitleKey) async -> XRayPrepareReport {
        var rep = XRayPrepareReport(title: key.name)
        defer { log?(rep.logLine) }
        guard running.insert(key).inserted else { rep.alreadyRunning = true; return rep }
        defer { running.remove(key) }
        let cast: [XRayCastEntry]
        do {
            let c = try await self.cast(for: key)
            cast = c.cast; rep.castFromCache = c.fromCache
        } catch {
            rep.failures += 1; rep.cancelled = Task.isCancelled
            return rep
        }
        let people = Array(cast.prefix(max(0, settings.maxPeople)))
        rep.people = people.count
        let model = embedder.modelID
        for person in people {
            if Task.isCancelled { rep.cancelled = true; break }
            if let r = await store.person(person.personID, model: model) {
                rep.cached += 1
                if !r.faces.isEmpty { rep.usable += 1 }
                continue
            }
            guard let done = await embedPerson(person, report: &rep) else { continue }
            let (faces, partial) = (done.0, done.partial)
            if Task.isCancelled { rep.cancelled = true; break }
            await store.store(XRayPersonRecord(personID: person.personID, modelID: model, faces: faces, partial: partial))
            rep.computed += 1
            if partial { rep.partial += 1 }
            if !faces.isEmpty { rep.usable += 1 }
        }
        await store.flush()
        return rep
    }

    /// The gallery for matching at pause time; only what is cached (no network). Saves the use times, so the
    /// LRU keeps what was just used even if the app is killed afterwards.
    public func gallery(for key: XRayTitleKey) async -> [GalleryPerson] {
        let g = await store.gallery(key, model: embedder.modelID)
        await store.flush()
        return g
    }

    /// Nil when the person could not be finished (network or embedder error, cancelled): nothing is cached
    /// then, so the next run tries again. An empty array is a finished result (no portrait had a clear face).
    /// `partial`: some portraits failed but others gave a face; cached with a short lifetime.
    private func embedPerson(_ person: XRayCastEntry, report rep: inout XRayPrepareReport) async -> ([XRayFaceRecord], partial: Bool)? {
        var portraits: [TMDBProfileImage]
        do {
            portraits = XRayGalleryPlan.pickImages(try await limited { try await self.tmdb.personImages(id: person.personID) },
                                                   settings: settings)
        } catch {
            if !Task.isCancelled { rep.failures += 1 }
            return nil
        }
        // No portraits listed: fall back to the credit's own profile picture.
        if portraits.isEmpty, let p = person.profilePath { portraits = [TMDBProfileImage(filePath: p)] }
        var out: [XRayFaceRecord] = []
        var incomplete = false
        for img in portraits {
            if Task.isCancelled { return nil }
            guard let u = TMDBClient.galleryImageURL(img.filePath) else { rep.discarded += 1; continue }
            let data: Data
            do { data = try await limited(imageThrottle) { try await self.images.data(from: u) } } catch {
                if Task.isCancelled { return nil }
                rep.failures += 1; incomplete = true; continue
            }
            rep.downloads += 1
            let faces: [EmbeddedFace]
            do { faces = try await embedder.faces(inImage: data) } catch {
                if Task.isCancelled || error is CancellationError { return nil }
                rep.failures += 1; incomplete = true; continue
            }
            rep.faces += faces.count
            guard let f = XRayGalleryPlan.portraitFace(faces, settings: settings) else { rep.discarded += 1; continue }
            out.append(XRayFaceRecord(filePath: img.filePath, embedding: f.embedding))
        }
        // Nothing usable and something failed: not finished, rather than caching "no face" for days.
        if out.isEmpty && incomplete { return nil }
        return (out, incomplete)
    }

    /// Throttled call; one retry after HTTP 429.
    private func limited<T: Sendable>(_ gate: RequestThrottle? = nil, _ op: @Sendable () async throws -> T) async throws -> T {
        let throttle = gate ?? self.throttle
        await throttle.wait()
        do { return try await op() } catch AddonError.http(429) {
            await sleep(Self.rateLimitPause)
            try Task.checkCancellation()
            await throttle.wait()
            return try await op()
        }
    }
}
