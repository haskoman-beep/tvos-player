import Foundation

// Wave X2: comparing faces with the cast gallery. Everything works on L2-normalised embeddings, so the cosine
// similarity is a plain dot product.

/// A face embedding (SFace: 128 values). `init` normalises to unit length.
public struct FaceEmbedding: Sendable, Equatable {
    public private(set) var values: [Float]

    /// Nil for an empty or all-zero vector (no direction, cannot be compared).
    public init?(_ raw: [Float]) {
        let norm = raw.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 1e-12, norm.isFinite else { return nil }
        values = raw.map { $0 / norm }
    }

    public var dimension: Int { values.count }

    /// Cosine similarity −1…1; nil when the dimensions differ (embeddings of two different models).
    public func cosine(_ other: FaceEmbedding) -> Float? {
        guard dimension == other.dimension else { return nil }
        var s: Float = 0
        for i in 0..<dimension { s += values[i] * other.values[i] }
        return min(1, max(-1, s))
    }

    /// Little-endian Float32 bytes (cache format, see `XRayFaceRecord`).
    public var data: Data {
        var d = Data(capacity: values.count * 4)
        for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }

    public init?(data: Data) {
        guard !data.isEmpty, data.count % 4 == 0 else { return nil }
        let bytes = [UInt8](data)
        var out = [Float](); out.reserveCapacity(bytes.count / 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let bits = UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
            out.append(Float(bitPattern: bits))
        }
        // A damaged file must not give a non-unit vector (cosine clamped to 1 = false match): normalise again
        // when the length is off; a stored unit vector stays bit for bit.
        let norm = out.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm.isFinite, norm > 1e-12 else { return nil }
        values = abs(norm - 1) > 1e-4 ? out.map { $0 / norm } : out
    }
}

/// Thresholds and filters for the decision per face. Starting values from the research (SFace); X6 calibrates.
public struct FaceMatchConfig: Sendable, Equatable, Codable {
    /// How a candidate's score is formed from the similarities to its gallery pictures.
    public enum GalleryScore: String, Sendable, Codable {
        /// Best single picture.
        case max
        /// Mean of the two best pictures (the best alone when there is only one); steadier with old photos.
        case meanTop2
    }

    /// T: lowest score for a match.
    public var threshold: Float
    /// M: required lead of the best candidate over the second best.
    public var margin: Float
    public var galleryScore: GalleryScore
    /// Faces narrower than this (source pixels) are skipped.
    public var minFaceWidth: Double
    /// Vision capture quality 0…1; lower is skipped (nil quality = not measured, accepted).
    public var minQuality: Double
    /// Largest |yaw| in degrees; SFace is weak in profile.
    public var maxYaw: Double
    /// Only the largest faces of a picture are compared (crowds cost time and bring extras).
    public var maxFaces: Int

    public init(threshold: Float = 0.45, margin: Float = 0.06, galleryScore: GalleryScore = .max,
                minFaceWidth: Double = 64, minQuality: Double = 0.3, maxYaw: Double = 45, maxFaces: Int = 6) {
        self.threshold = threshold; self.margin = margin; self.galleryScore = galleryScore
        self.minFaceWidth = minFaceWidth; self.minQuality = minQuality; self.maxYaw = maxYaw; self.maxFaces = maxFaces
    }

    public static let sface = FaceMatchConfig()
    public static let arcfaceR50 = FaceMatchConfig(threshold: 0.40)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FaceMatchConfig()
        threshold = try c.decodeIfPresent(Float.self, forKey: .threshold) ?? d.threshold
        margin = try c.decodeIfPresent(Float.self, forKey: .margin) ?? d.margin
        galleryScore = try c.decodeIfPresent(GalleryScore.self, forKey: .galleryScore) ?? d.galleryScore
        minFaceWidth = try c.decodeIfPresent(Double.self, forKey: .minFaceWidth) ?? d.minFaceWidth
        minQuality = try c.decodeIfPresent(Double.self, forKey: .minQuality) ?? d.minQuality
        maxYaw = try c.decodeIfPresent(Double.self, forKey: .maxYaw) ?? d.maxYaw
        maxFaces = try c.decodeIfPresent(Int.self, forKey: .maxFaces) ?? d.maxFaces
    }
}

/// What the detector found for one face, before the embedding.
public struct DetectedFace: Sendable, Equatable {
    /// Width of the face box in source pixels.
    public var width: Double
    /// Vision capture quality, if measured.
    public var quality: Double?
    /// Yaw in degrees, if measured.
    public var yaw: Double?

    public init(width: Double, quality: Double? = nil, yaw: Double? = nil) {
        self.width = width; self.quality = quality; self.yaw = yaw
    }
}

public enum FaceSkipReason: String, Sendable, Equatable { case small, lowQuality, profile, crowd }

extension FaceMatchConfig {
    /// Why a face is not compared at all; nil = use it.
    public func skipReason(_ f: DetectedFace) -> FaceSkipReason? {
        if f.width < minFaceWidth { return .small }
        if let q = f.quality, q < minQuality { return .lowQuality }
        if let y = f.yaw, abs(y) > maxYaw { return .profile }
        return nil
    }

    /// Indices of the faces to compare: passing the filters, largest first, at most `maxFaces`.
    /// The others come back with their reason (`crowd` for those cut by `maxFaces`).
    public func selectFaces(_ faces: [DetectedFace]) -> (use: [Int], skipped: [Int: FaceSkipReason]) {
        var skipped: [Int: FaceSkipReason] = [:]
        var ok: [Int] = []
        for (i, f) in faces.enumerated() {
            if let r = skipReason(f) { skipped[i] = r } else { ok.append(i) }
        }
        ok.sort { faces[$0].width != faces[$1].width ? faces[$0].width > faces[$1].width : $0 < $1 }
        for i in ok.dropFirst(max(0, maxFaces)) { skipped[i] = .crowd }
        return (Array(ok.prefix(max(0, maxFaces))), skipped)
    }
}

/// One cast member with the embeddings of their gallery pictures.
public struct GalleryPerson: Sendable, Equatable {
    public var personID: Int
    public var embeddings: [FaceEmbedding]
    public init(personID: Int, embeddings: [FaceEmbedding]) { self.personID = personID; self.embeddings = embeddings }
}

/// Outcome for one face of the paused picture.
public enum FaceDecision: Sendable, Equatable {
    case match(personID: Int, score: Float, lead: Float)
    case unknown(UnknownReason, best: Float?)

    public enum UnknownReason: String, Sendable, Equatable {
        /// Gallery empty or no comparable embedding.
        case noCandidates
        /// Best score under T.
        case belowThreshold
        /// Best score over T but less than M ahead of the second best.
        case ambiguous
        /// Best candidate already given to another face of the same picture with a higher score.
        case taken
    }

    public var personID: Int? { if case .match(let id, _, _) = self { id } else { nil } }
}

public enum FaceMatcher {
    /// Score of one candidate for one face; nil when no gallery embedding is comparable.
    public static func score(_ face: FaceEmbedding, _ person: GalleryPerson, mode: FaceMatchConfig.GalleryScore) -> Float? {
        let sims = person.embeddings.compactMap { face.cosine($0) }.sorted(by: >)
        guard let best = sims.first else { return nil }
        switch mode {
        case .max: return best
        case .meanTop2: return sims.count >= 2 ? (best + sims[1]) / 2 : best
        }
    }

    /// Candidates of one face, best first (ties by person ID, so the result is stable).
    public static func ranking(_ face: FaceEmbedding, gallery: [GalleryPerson],
                               mode: FaceMatchConfig.GalleryScore) -> [(personID: Int, score: Float)] {
        gallery.compactMap { p in score(face, p, mode: mode).map { (p.personID, $0) } }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.personID < $1.personID }
    }

    /// Decision for one face on its own: match when best ≥ T and best − second ≥ M (no second: lead = best + 1,
    /// i.e. the margin is always met).
    public static func decide(_ face: FaceEmbedding, gallery: [GalleryPerson], config: FaceMatchConfig) -> FaceDecision {
        decide(ranking(face, gallery: gallery, mode: config.galleryScore), config: config)
    }

    static func decide(_ r: [(personID: Int, score: Float)], config: FaceMatchConfig) -> FaceDecision {
        guard let best = r.first else { return .unknown(.noCandidates, best: nil) }
        guard best.score >= config.threshold else { return .unknown(.belowThreshold, best: best.score) }
        let lead = r.count > 1 ? best.score - r[1].score : best.score + 1
        guard lead >= config.margin else { return .unknown(.ambiguous, best: best.score) }
        return .match(personID: best.personID, score: best.score, lead: lead)
    }

    /// All faces of one picture. Each face is first decided on its own (T and M against all candidates, so a
    /// face that looks like two actors stays unknown even if one of them is taken). Then each person goes to at
    /// most one face: matches are handed out greedily by score, highest first; a face whose person is already
    /// given away becomes `.unknown(.taken)`. It does not fall back to its second choice, because that one is
    /// by definition at least M weaker and would cost precision.
    public static func assign(_ faces: [FaceEmbedding], gallery: [GalleryPerson], config: FaceMatchConfig) -> [FaceDecision] {
        var out = faces.map { decide($0, gallery: gallery, config: config) }
        let order = out.indices.compactMap { i -> (Int, Float)? in
            if case .match(_, let s, _) = out[i] { return (i, s) } else { return nil }
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var used = Set<Int>()
        for (i, s) in order {
            guard let id = out[i].personID else { continue }
            if !used.insert(id).inserted { out[i] = .unknown(.taken, best: s) }
        }
        return out
    }
}
