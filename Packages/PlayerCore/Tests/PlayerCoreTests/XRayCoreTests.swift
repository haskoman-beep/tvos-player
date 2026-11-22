import Foundation
import Testing
@testable import PlayerCore

// Wave X2: alignment geometry, embeddings, scoring, assignment and the cache format.

private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }
private func close(_ p: FacePoint, _ q: FacePoint, _ eps: Double = 1e-6) -> Bool { close(p.x, q.x, eps) && close(p.y, q.y, eps) }

// MARK: Alignment

@Test func similarityApplyAndInverseRoundTrip() throws {
    let t = SimilarityTransform(a: 2 * cos(0.3), b: 2 * sin(0.3), tx: 15, ty: -4)
    #expect(close(t.scale, 2) && close(t.rotation, 0.3))
    let inv = try #require(t.inverse)
    for p in [FacePoint(0, 0), FacePoint(10, 3), FacePoint(-7, 40)] {
        #expect(close(inv.apply(t.apply(p)), p))
    }
    #expect(SimilarityTransform(a: 0, b: 0, tx: 1, ty: 1).inverse == nil)
}

@Test func alignRecoversKnownTransform() throws {
    // Landmarks of a face that is 3× larger than the template, turned by 12° and moved: the fit must find
    // exactly the transform that brings them back.
    let truth = SimilarityTransform(a: cos(-0.21) / 3, b: sin(-0.21) / 3, tx: -40, ty: 25)
    let toImage = try #require(truth.inverse)
    let pts = FaceAlignment.template112.map { toImage.apply($0) }
    let lm = FiveLandmarks(leftEye: pts[0], rightEye: pts[1], nose: pts[2], leftMouth: pts[3], rightMouth: pts[4])
    let r = try #require(FaceAlignment.align(lm))
    #expect(close(r.toCrop.a, truth.a) && close(r.toCrop.b, truth.b))
    #expect(close(r.toCrop.tx, truth.tx, 1e-4) && close(r.toCrop.ty, truth.ty, 1e-4))
    #expect(r.residual < 1e-6)
    #expect(close(r.toImage.apply(FaceAlignment.template112[2]), pts[2], 1e-6))
}

@Test func alignToleratesNoiseAndRejectsNonFaces() throws {
    let base = FaceAlignment.template112.map { FacePoint($0.x * 2 + 300, $0.y * 2 + 100) }
    let jitter = [FacePoint(1, -1), FacePoint(-1, 0.5), FacePoint(0.5, 1), FacePoint(-0.5, -1), FacePoint(1, 0)]
    let noisy = zip(base, jitter).map { $0 + $1 }
    let r = try #require(FaceAlignment.align(FiveLandmarks(leftEye: noisy[0], rightEye: noisy[1], nose: noisy[2],
                                                            leftMouth: noisy[3], rightMouth: noisy[4])))
    #expect(r.residual < 1.5 && close(r.toCrop.scale, 0.5, 0.01))
    // Mouth above the eyes: no similarity transform fits that shape.
    let wrong = FiveLandmarks(leftEye: base[3], rightEye: base[4], nose: base[2], leftMouth: base[0], rightMouth: base[1])
    #expect(FaceAlignment.align(wrong) == nil)
    // All points in one place.
    let p = FacePoint(5, 5)
    #expect(FaceAlignment.align(FiveLandmarks(leftEye: p, rightEye: p, nose: p, leftMouth: p, rightMouth: p)) == nil)
}

@Test func fiveLandmarksFromRegionsSortsByImageSide() throws {
    let right = [FacePoint(70, 50), FacePoint(78, 50), FacePoint(74, 48), FacePoint(74, 52)]
    let left = [FacePoint(30, 50), FacePoint(38, 50)]
    let lm = try #require(FiveLandmarks.from(eyeA: right, eyeB: left, nose: [FacePoint(52, 70), FacePoint(56, 72)],
                                              outerLips: [FacePoint(60, 90), FacePoint(40, 91), FacePoint(50, 95)]))
    #expect(lm.leftEye == FacePoint(34, 50) && lm.rightEye == FacePoint(74, 50))
    #expect(lm.nose == FacePoint(54, 71))
    #expect(lm.leftMouth == FacePoint(40, 91) && lm.rightMouth == FacePoint(60, 90))
    // Pupils win over the outline; without a nose outline the lowest crest point is the tip.
    let p = try #require(FiveLandmarks.from(eyeA: left, eyeB: right, pupilA: FacePoint(33, 49), pupilB: FacePoint(75, 51),
                                             nose: [], noseCrest: [FacePoint(55, 55), FacePoint(55, 69)],
                                             outerLips: [FacePoint(40, 90), FacePoint(60, 90)]))
    #expect(p.leftEye == FacePoint(33, 49) && p.rightEye == FacePoint(75, 51) && p.nose == FacePoint(55, 69))
    #expect(FiveLandmarks.from(eyeA: [], eyeB: left, nose: right, outerLips: left) == nil)
    #expect(FiveLandmarks.from(eyeA: left, eyeB: right, nose: right, outerLips: [FacePoint(1, 1)]) == nil)
}

@Test func visionCoordinatesToImagePixels() {
    // Box in the lower left quarter (Vision: origin bottom left).
    let box = FaceGeometry.NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
    let p = FaceGeometry.imagePoint(x: 0.5, y: 1, inBox: box, imageWidth: 1920, imageHeight: 1080)
    // Half-pixel shift: Vision is continuous, the warp uses integer pixel centres.
    #expect(p == FacePoint(479.5, 539.5))
    #expect(FaceGeometry.imagePoint(x: 0, y: 0, inBox: box, imageWidth: 1920, imageHeight: 1080) == FacePoint(-0.5, 1079.5))
    #expect(FaceGeometry.pixelWidth(box, imageWidth: 1920) == 960)
}

@Test func warpSamplesShiftedPixelsInChannelOrder() {
    // R = x, G = y, B = 200: a shift by (10, 20) must show up 1:1 in the crop.
    let w = 160, h = 160
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { let i = (y * w + x) * 4; px[i] = UInt8(x); px[i + 1] = UInt8(y); px[i + 2] = 200 } }
    let img = FaceWarp.RGBAImage(width: w, height: h, pixels: px)
    let shift = SimilarityTransform(a: 1, b: 0, tx: 10, ty: 20)
    let t = FaceWarp.crop(img, toImage: shift)
    let plane = 112 * 112
    #expect(t.count == plane * 3)
    #expect(t[0] == 10 && t[plane] == 20 && t[2 * plane] == 200)
    #expect(t[5 * 112 + 7] == 17 && t[plane + 5 * 112 + 7] == 25)
    // Half-pixel shift interpolates.
    let half = FaceWarp.crop(img, toImage: SimilarityTransform(a: 1, b: 0, tx: 10.5, ty: 0))
    #expect(half[0] == 10.5)
    // BGR puts blue first; scale and bias apply.
    let bgr = FaceWarp.crop(img, toImage: shift, format: FaceInputFormat(order: .bgr, scale: 0.5, bias: -1))
    #expect(bgr[0] == 99 && bgr[2 * plane] == 4)
    // Outside the picture is black.
    let out = FaceWarp.crop(img, toImage: SimilarityTransform(a: 1, b: 0, tx: 500, ty: 500))
    #expect(out.allSatisfy { $0 == 0 })
}

// MARK: Embedding

@Test func embeddingNormalisesAndCompares() throws {
    let a = try #require(FaceEmbedding([3, 4]))
    #expect(a.values == [0.6, 0.8])
    let b = try #require(FaceEmbedding([4, -3]))
    #expect(a.cosine(b) == 0)
    #expect(a.cosine(a).map { abs($0 - 1) < 1e-6 } == true)
    #expect(FaceEmbedding([0, 0]) == nil && FaceEmbedding([]) == nil && FaceEmbedding([.nan, 1]) == nil)
    #expect(a.cosine(try #require(FaceEmbedding([1, 0, 0]))) == nil)
    let back = try #require(FaceEmbedding(data: a.data))
    #expect(back == a && a.data.count == 8)
    #expect(FaceEmbedding(data: Data([1, 2, 3])) == nil)
    // Damaged bytes: a non-unit vector is normalised again, zeros are rejected.
    var raw = Data()
    for v: Float in [3, 4] { withUnsafeBytes(of: v.bitPattern.littleEndian) { raw.append(contentsOf: $0) } }
    #expect(FaceEmbedding(data: raw)?.values == [0.6, 0.8])
    #expect(FaceEmbedding(data: Data(count: 8)) == nil)
    #expect(FaceEmbedding([.infinity, 1]) == nil)
}

// MARK: Scoring

/// Unit vector whose cosine with [1, 0, 0] is `c` (in the x/y plane, or x/z when `z`).
private func emb(_ c: Float, z: Bool = false) -> FaceEmbedding {
    let s = (1 - c * c).squareRoot()
    return FaceEmbedding(z ? [c, 0, s] : [c, s, 0])!
}
private let probe = FaceEmbedding([1, 0, 0])!

private func near(_ a: Float?, _ b: Float) -> Bool { a.map { abs($0 - b) < 1e-5 } ?? false }

@Test func decisionNeedsThresholdAndMargin() {
    let cfg = FaceMatchConfig.sface
    #expect(cfg.threshold == 0.45 && cfg.margin == 0.06)
    let clear = FaceMatcher.decide(probe, gallery: [.init(personID: 1, embeddings: [emb(0.7)]), .init(personID: 2, embeddings: [emb(0.5)])], config: cfg)
    guard case .match(1, let s, let lead) = clear else { Issue.record("no match: \(clear)"); return }
    #expect(near(s, 0.7) && near(lead, 0.2))
    let low = FaceMatcher.decide(probe, gallery: [.init(personID: 1, embeddings: [emb(0.4)])], config: cfg)
    #expect(low == .unknown(.belowThreshold, best: low.bestForTest))
    let tight = FaceMatcher.decide(probe, gallery: [.init(personID: 1, embeddings: [emb(0.6)]), .init(personID: 2, embeddings: [emb(0.57)])], config: cfg)
    guard case .unknown(.ambiguous, _) = tight else { Issue.record("not ambiguous: \(tight)"); return }
    // A single candidate always has the lead.
    #expect(FaceMatcher.decide(probe, gallery: [.init(personID: 9, embeddings: [emb(0.46)])], config: cfg).personID == 9)
    #expect(FaceMatcher.decide(probe, gallery: [], config: cfg) == .unknown(.noCandidates, best: nil))
    #expect(FaceMatcher.decide(probe, gallery: [.init(personID: 1, embeddings: [])], config: cfg) == .unknown(.noCandidates, best: nil))
}

extension FaceDecision {
    var bestForTest: Float? { if case .unknown(_, let b) = self { b } else { nil } }
}

@Test func galleryScoreMaxOrMeanOfTopTwo() {
    let p = GalleryPerson(personID: 1, embeddings: [emb(0.3), emb(0.8), emb(0.6)])
    #expect(near(FaceMatcher.score(probe, p, mode: .max), 0.8))
    #expect(near(FaceMatcher.score(probe, p, mode: .meanTop2), 0.7))
    #expect(near(FaceMatcher.score(probe, .init(personID: 2, embeddings: [emb(0.5)]), mode: .meanTop2), 0.5))
    // Embeddings of another dimension are ignored, not counted as 0.
    let mixed = GalleryPerson(personID: 3, embeddings: [FaceEmbedding([1, 0])!, emb(0.55)])
    #expect(near(FaceMatcher.score(probe, mixed, mode: .max), 0.55))
}

@Test func assignmentGivesEachPersonOnce() {
    let cfg = FaceMatchConfig.sface
    let a = GalleryPerson(personID: 10, embeddings: [FaceEmbedding([1, 0, 0])!])
    let b = GalleryPerson(personID: 20, embeddings: [FaceEmbedding([0, 1, 0])!])
    let f1 = FaceEmbedding([0.9, 0.1, 0.42])!   // close to A
    let f2 = FaceEmbedding([0.75, 0.05, 0.66])! // also A, weaker
    let f3 = FaceEmbedding([0.05, 0.95, 0.3])!  // B
    let d = FaceMatcher.assign([f2, f1, f3], gallery: [a, b], config: cfg)
    #expect(d[1].personID == 10 && d[2].personID == 20)
    guard case .unknown(.taken, let s) = d[0] else { Issue.record("expected taken: \(d[0])"); return }
    #expect(s != nil)
    // Order of the faces does not change who wins.
    let e = FaceMatcher.assign([f1, f2, f3], gallery: [a, b], config: cfg)
    #expect(e.map(\.personID) == [10, nil, 20])
    #expect(FaceMatcher.assign([], gallery: [a], config: cfg).isEmpty)
}

@Test func faceSelectionFiltersAndKeepsLargest() {
    var cfg = FaceMatchConfig.sface
    cfg.maxFaces = 2
    let faces = [DetectedFace(width: 120, quality: 0.8, yaw: 10), DetectedFace(width: 50),
                 DetectedFace(width: 200, quality: 0.1), DetectedFace(width: 90, yaw: -60),
                 DetectedFace(width: 70), DetectedFace(width: 150, quality: nil, yaw: 44)]
    let s = cfg.selectFaces(faces)
    #expect(s.use == [5, 0])
    #expect(s.skipped == [1: .small, 2: .lowQuality, 3: .profile, 4: .crowd])
}

@Test func matchConfigDecodesMissingFieldsWithDefaults() throws {
    let c = try JSONDecoder().decode(FaceMatchConfig.self, from: Data(#"{"threshold":0.5,"galleryScore":"meanTop2"}"#.utf8))
    #expect(c.threshold == 0.5 && c.galleryScore == .meanTop2 && c.margin == 0.06 && c.maxFaces == 6)
    let back = try JSONDecoder().decode(FaceMatchConfig.self, from: JSONEncoder().encode(c))
    #expect(back == c)
}

// MARK: Cache

final class XRayMemoryBlobs: BlobStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    func read(_ name: String) -> Data? { lock.lock(); defer { lock.unlock() }; return files[name] }
    func write(_ name: String, _ data: Data) throws { lock.lock(); files[name] = data; lock.unlock() }
    func remove(_ name: String) { lock.lock(); files[name] = nil; lock.unlock() }
    var names: [String] { lock.lock(); defer { lock.unlock() }; return files.keys.sorted() }
    func raw(_ name: String) -> Data? { read(name) }
}

final class XRayClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    init(_ t: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.t = t }
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

private let day: TimeInterval = 24 * 3600

@Test func titleKeysAreStableNames() {
    #expect(XRayTitleKey.movie(tmdbID: 603).name == "m603")
    #expect(XRayTitleKey.episode(tvID: 1399, season: 1, episode: 2).name == "e1399-s1e2")
    #expect(XRayCacheFormat.titleName(.movie(tmdbID: 1)) != XRayCacheFormat.titleName(.episode(tvID: 1, season: 0, episode: 0)))
    #expect(XRayCacheFormat.personName(5, model: "sface/2021 dec") == "xray-p-5-sface_2021_dec.json")
}

@Test func cacheStoresTitlesAndPeopleFor30Days() async throws {
    let blobs = XRayMemoryBlobs(), clock = XRayClock()
    let store = XRayStore(storage: blobs, now: { clock.now })
    let key = XRayTitleKey.episode(tvID: 7, season: 2, episode: 3)
    let cast = [XRayCastEntry(personID: 1, name: "A", role: "Held", profilePath: "/a.jpg", order: 0),
                XRayCastEntry(personID: 2, name: "B", order: 1, guest: true)]
    await store.store(XRayTitleRecord(key: key, cast: cast))
    let face = XRayFaceRecord(filePath: "/a1.jpg", embedding: FaceEmbedding([1, 2, 3])!)
    await store.store(XRayPersonRecord(personID: 1, modelID: "sface-1", faces: [face]))
    await store.store(XRayPersonRecord(personID: 2, modelID: "sface-1", faces: []))

    #expect(await store.title(key)?.cast == cast)
    #expect(await store.title(.episode(tvID: 7, season: 2, episode: 4)) == nil)
    #expect(await store.person(1, model: "sface-1")?.faces == [face])
    #expect(await store.person(1, model: "arcface") == nil)
    #expect(await store.gallery(key, model: "sface-1").map(\.personID) == [1])

    // A second store on the same files (app restart) reads the same.
    let again = XRayStore(storage: blobs, now: { clock.now })
    #expect(await again.person(1, model: "sface-1")?.faces.first?.embedding == face.embedding)

    // The empty person expires after 7 days, the rest after 30.
    clock.advance(8 * day)
    #expect(await again.person(2, model: "sface-1") == nil)
    #expect(await again.person(1, model: "sface-1") != nil)
    clock.advance(22 * day)
    #expect(await again.title(key) == nil)
    #expect(await again.person(1, model: "sface-1") == nil)
    #expect(!blobs.names.contains(XRayCacheFormat.titleName(key)))
}

@Test func cacheIgnoresOtherFormatVersionsAndJunk() async throws {
    let blobs = XRayMemoryBlobs(), clock = XRayClock()
    let store = XRayStore(storage: blobs, now: { clock.now })
    let key = XRayTitleKey.movie(tmdbID: 9)
    await store.store(XRayTitleRecord(key: key, cast: [XRayCastEntry(personID: 1, name: "A")]))
    let name = XRayCacheFormat.titleName(key)
    let text = try #require(blobs.raw(name).flatMap { String(data: $0, encoding: .utf8) })
    #expect(text.contains(#""v":1"#))
    try blobs.write(name, Data(text.replacingOccurrences(of: #""v":1"#, with: #""v":99"#).utf8))
    #expect(await XRayStore(storage: blobs, now: { clock.now }).title(key) == nil)
    #expect(blobs.raw(name) == nil)   // other version: the file is deleted, not orphaned
    try blobs.write(name, Data("not json".utf8))
    #expect(await XRayStore(storage: blobs, now: { clock.now }).title(key) == nil)
    #expect(blobs.raw(name) == nil)
}

@Test func lifetimeSurvivesLostIndex() async throws {
    let blobs = XRayMemoryBlobs(), clock = XRayClock()
    let store = XRayStore(storage: blobs, now: { clock.now })
    let face = XRayFaceRecord(filePath: "/a.jpg", embedding: FaceEmbedding([1, 0])!)
    await store.store(XRayPersonRecord(personID: 1, modelID: "m", faces: []))
    await store.store(XRayPersonRecord(personID: 2, modelID: "m", faces: [face], partial: true))
    await store.store(XRayPersonRecord(personID: 3, modelID: "m", faces: [face]))
    blobs.remove(XRayCacheFormat.indexName)
    let fresh = XRayStore(storage: blobs, now: { clock.now })
    clock.advance(1.5 * day)
    #expect(await fresh.person(2, model: "m") == nil)   // partial: 1 day
    #expect(await fresh.person(1, model: "m") != nil)
    clock.advance(6 * day)
    #expect(await fresh.person(1, model: "m") == nil)   // empty: 7 days
    #expect(await fresh.person(3, model: "m") != nil)
}

@Test func cacheEvictsLeastRecentlyUsedOverBudget() async throws {
    let blobs = XRayMemoryBlobs(), clock = XRayClock()
    let big = (0..<64).map { _ in FaceRecordFactory.make() }
    let one = try XRayCacheFormat.encode(XRayPersonRecord(personID: 1, modelID: "m", faces: big), savedAt: clock.now).count
    let store = XRayStore(storage: blobs, maxBytes: one * 2 + one / 2, now: { clock.now })
    for id in 1...2 { await store.store(XRayPersonRecord(personID: id, modelID: "m", faces: big)); clock.advance(10) }
    _ = await store.person(1, model: "m")   // 1 is now newer than 2
    clock.advance(10)
    await store.store(XRayPersonRecord(personID: 3, modelID: "m", faces: big))
    #expect(await store.person(2, model: "m") == nil)
    #expect(await store.person(1, model: "m") != nil)
    #expect(await store.person(3, model: "m") != nil)
    #expect(await store.totalBytes <= one * 2 + one / 2)
    await store.removeAll()
    #expect(blobs.names == [XRayCacheFormat.indexName])
}

private enum FaceRecordFactory {
    static func make() -> XRayFaceRecord {
        XRayFaceRecord(filePath: "/x.jpg", embedding: FaceEmbedding((0..<128).map { Float($0 % 7) + 1 })!)
    }
}
