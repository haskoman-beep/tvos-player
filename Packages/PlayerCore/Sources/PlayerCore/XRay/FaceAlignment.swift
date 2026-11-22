import Foundation

// Wave X2: face alignment geometry for the "who is in the picture" feature (X-Ray on pause).
// Pure math, no Vision or Core ML, so it runs in the Linux tests. The app (X4) feeds in Vision landmarks and
// uses the transform to warp the face into the 112×112 input of the embedding model.

/// A point in image pixels, origin top left, y pointing down (the convention of the warp and of CGImage rows).
public struct FacePoint: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static func + (a: FacePoint, b: FacePoint) -> FacePoint { FacePoint(a.x + b.x, a.y + b.y) }
    static func - (a: FacePoint, b: FacePoint) -> FacePoint { FacePoint(a.x - b.x, a.y - b.y) }
    func distance(to p: FacePoint) -> Double { ((x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)).squareRoot() }

    static func centroid(_ ps: [FacePoint]) -> FacePoint? {
        guard !ps.isEmpty else { return nil }
        let n = Double(ps.count)
        return FacePoint(ps.reduce(0) { $0 + $1.x } / n, ps.reduce(0) { $0 + $1.y } / n)
    }
}

/// The five landmarks of the ArcFace/SFace alignment, in image pixels. Order is by image position:
/// `leftEye` is the eye on the left side of the picture (the subject's right eye), likewise the mouth corners.
public struct FiveLandmarks: Sendable, Equatable, Codable {
    public var leftEye: FacePoint
    public var rightEye: FacePoint
    public var nose: FacePoint
    public var leftMouth: FacePoint
    public var rightMouth: FacePoint

    public init(leftEye: FacePoint, rightEye: FacePoint, nose: FacePoint, leftMouth: FacePoint, rightMouth: FacePoint) {
        self.leftEye = leftEye; self.rightEye = rightEye; self.nose = nose
        self.leftMouth = leftMouth; self.rightMouth = rightMouth
    }

    public var points: [FacePoint] { [leftEye, rightEye, nose, leftMouth, rightMouth] }

    /// Builds the five points from Vision-style landmark regions that are already converted to image pixels
    /// (see `FaceGeometry.imagePoint`). Eye centre = pupil if given, else the centroid of the eye outline.
    /// Nose = centroid of the nose outline (it rings the nostrils, so its centre sits at the tip), else the lowest
    /// point of the nose crest. Mouth corners = the outermost points of the outer lip line.
    /// Eyes and mouth corners are sorted by x, so it does not matter which naming convention the detector uses.
    /// Returns nil when a region is missing.
    public static func from(eyeA: [FacePoint], eyeB: [FacePoint], pupilA: FacePoint? = nil, pupilB: FacePoint? = nil,
                            nose: [FacePoint], noseCrest: [FacePoint] = [], outerLips: [FacePoint]) -> FiveLandmarks? {
        guard let a = pupilA ?? FacePoint.centroid(eyeA), let b = pupilB ?? FacePoint.centroid(eyeB) else { return nil }
        guard let tip = FacePoint.centroid(nose) ?? noseCrest.max(by: { $0.y < $1.y }) else { return nil }
        guard let ml = outerLips.min(by: { $0.x < $1.x }), let mr = outerLips.max(by: { $0.x < $1.x }), ml != mr else { return nil }
        let (le, re) = a.x <= b.x ? (a, b) : (b, a)
        return FiveLandmarks(leftEye: le, rightEye: re, nose: tip, leftMouth: ml, rightMouth: mr)
    }
}

/// 2-D similarity transform (uniform scale, rotation, shift, no mirroring):
/// x' = a·x − b·y + tx, y' = b·x + a·y + ty.
public struct SimilarityTransform: Sendable, Equatable, Codable {
    public var a: Double
    public var b: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, tx: Double, ty: Double) { self.a = a; self.b = b; self.tx = tx; self.ty = ty }

    public static let identity = SimilarityTransform(a: 1, b: 0, tx: 0, ty: 0)

    public var scale: Double { (a * a + b * b).squareRoot() }
    /// Rotation in radians (positive turns x towards y, i.e. clockwise on screen with y down).
    public var rotation: Double { atan2(b, a) }

    public func apply(_ p: FacePoint) -> FacePoint {
        FacePoint(a * p.x - b * p.y + tx, b * p.x + a * p.y + ty)
    }

    /// The reverse mapping; nil for a degenerate transform (scale 0).
    public var inverse: SimilarityTransform? {
        let d = a * a + b * b
        guard d > 1e-12 else { return nil }
        let ia = a / d, ib = -b / d
        return SimilarityTransform(a: ia, b: ib, tx: -(ia * tx - ib * ty), ty: -(ib * tx + ia * ty))
    }

    /// Least-squares fit that maps `source` onto `target` (closed form of Umeyama's method for 2-D without
    /// reflection). Needs at least two distinct points of the same count.
    public static func fit(from source: [FacePoint], to target: [FacePoint]) -> SimilarityTransform? {
        guard source.count == target.count, source.count >= 2,
              let ms = FacePoint.centroid(source), let mt = FacePoint.centroid(target) else { return nil }
        var sxx = 0.0, num_a = 0.0, num_b = 0.0
        for (s, t) in zip(source, target) {
            let p = s - ms, q = t - mt
            sxx += p.x * p.x + p.y * p.y
            num_a += p.x * q.x + p.y * q.y
            num_b += p.x * q.y - p.y * q.x
        }
        guard sxx > 1e-9 else { return nil }
        let a = num_a / sxx, b = num_b / sxx
        return SimilarityTransform(a: a, b: b, tx: mt.x - (a * ms.x - b * ms.y), ty: mt.y - (b * ms.x + a * ms.y))
    }
}

/// Result of aligning one face.
public struct FaceAlignmentResult: Sendable, Equatable {
    /// Image pixels → model input pixels (112×112).
    public var toCrop: SimilarityTransform
    /// Model input pixels → image pixels; this is what a warp samples with.
    public var toImage: SimilarityTransform
    /// Root mean square distance (in crop pixels) between the mapped landmarks and the template.
    public var residual: Double
}

public enum FaceAlignment {
    /// Side of the square model input (SFace and ArcFace both use 112).
    public static let inputSize = 112

    /// The standard ArcFace five-point template for 112×112, in the `FiveLandmarks` order.
    public static let template112: [FacePoint] = [
        FacePoint(38.2946, 51.6963), FacePoint(73.5318, 51.5014), FacePoint(56.0252, 71.7366),
        FacePoint(41.5493, 92.3655), FacePoint(70.7299, 92.2041),
    ]

    /// Highest residual (crop pixels) that still counts as a face: above this the landmarks do not form a face
    /// shape (detector error, strong profile), and the embedding would be junk.
    public static let maxResidual = 12.0

    /// Similarity transform that brings the five landmarks onto the template. Nil when the landmarks are
    /// degenerate or do not fit the template (`maxResidual`).
    public static func align(_ lm: FiveLandmarks, template: [FacePoint] = template112,
                             maxResidual: Double = maxResidual) -> FaceAlignmentResult? {
        guard let t = SimilarityTransform.fit(from: lm.points, to: template), let inv = t.inverse else { return nil }
        let sq = zip(lm.points, template).reduce(0.0) { acc, pair in
            let d = t.apply(pair.0).distance(to: pair.1); return acc + d * d
        }
        let residual = (sq / Double(template.count)).squareRoot()
        guard residual <= maxResidual else { return nil }
        return FaceAlignmentResult(toCrop: t, toImage: inv, residual: residual)
    }
}

/// Converts Vision's coordinates into image pixels with the origin top left.
public enum FaceGeometry {
    /// A rectangle in normalised image coordinates (0…1, origin bottom left), as Vision reports bounding boxes.
    public struct NormalizedRect: Sendable, Equatable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// A landmark point given relative to the face box (0…1, origin bottom left, Vision's `normalizedPoints`),
    /// for a picture with orientation `.up`.
    public static func imagePoint(x: Double, y: Double, inBox box: NormalizedRect,
                                  imageWidth: Double, imageHeight: Double) -> FacePoint {
        // Vision is continuous (pixel centres at i + 0.5); the warp and the template use OpenCV's convention
        // (centres at integers), hence the half-pixel shift.
        let nx = box.x + x * box.width, ny = box.y + y * box.height
        return FacePoint(nx * imageWidth - 0.5, (1 - ny) * imageHeight - 0.5)
    }

    /// Width of the face box in image pixels.
    public static func pixelWidth(_ box: NormalizedRect, imageWidth: Double) -> Double { box.width * imageWidth }
}

/// Pixel layout the embedding model expects. SFace's exact preprocessing is confirmed in X1 (model conversion):
/// OpenCV feeds it with `blobFromImage(…, swapRB: true)` and no scaling, so the defaults here are RGB, 0…255.
/// If the converted model has scale/bias baked in, the app passes `.raw` and lets Core ML do it.
public struct FaceInputFormat: Sendable, Equatable, Codable {
    public enum Order: String, Sendable, Codable { case rgb, bgr }
    public var order: Order
    public var scale: Float
    public var bias: Float

    public init(order: Order, scale: Float, bias: Float) { self.order = order; self.scale = scale; self.bias = bias }

    public static let raw = FaceInputFormat(order: .rgb, scale: 1, bias: 0)
    /// Common for ArcFace-style ONNX models: (x − 127.5) / 128.
    public static let centered = FaceInputFormat(order: .rgb, scale: 1 / 128, bias: -127.5 / 128)
}

/// Bilinear warp of an RGBA8 picture into the model input. Pure Swift: 112×112 samples are cheap, and the
/// test can check the geometry pixel by pixel. Pixels outside the source are black (as OpenCV's warpAffine).
public enum FaceWarp {
    /// Interleaved RGBA, 8 bits per channel, rows top to bottom.
    public struct RGBAImage: Sendable {
        public var width: Int
        public var height: Int
        public var bytesPerRow: Int
        public var pixels: [UInt8]
        public init(width: Int, height: Int, bytesPerRow: Int? = nil, pixels: [UInt8]) {
            self.width = width; self.height = height; self.bytesPerRow = bytesPerRow ?? width * 4; self.pixels = pixels
        }

        func channel(_ x: Int, _ y: Int, _ c: Int) -> Float {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            let i = y * bytesPerRow + x * 4 + c
            return i < pixels.count ? Float(pixels[i]) : 0
        }
    }

    /// Planar (CHW) float tensor of `size`×`size`×3 in the given channel order and scaling.
    public static func crop(_ img: RGBAImage, toImage: SimilarityTransform, size: Int = FaceAlignment.inputSize,
                            format: FaceInputFormat = .raw) -> [Float] {
        let plane = size * size
        var out = [Float](repeating: 0, count: plane * 3)
        let channels = format.order == .rgb ? [0, 1, 2] : [2, 1, 0]
        for oy in 0..<size {
            for ox in 0..<size {
                // Sample at the pixel centre, as warpAffine does with integer pixel coordinates.
                let p = toImage.apply(FacePoint(Double(ox), Double(oy)))
                let x0 = Int(floor(p.x)), y0 = Int(floor(p.y))
                let fx = Float(p.x - Double(x0)), fy = Float(p.y - Double(y0))
                for (k, c) in channels.enumerated() {
                    let v00 = img.channel(x0, y0, c), v10 = img.channel(x0 + 1, y0, c)
                    let v01 = img.channel(x0, y0 + 1, c), v11 = img.channel(x0 + 1, y0 + 1, c)
                    let top = v00 + (v10 - v00) * fx, bottom = v01 + (v11 - v01) * fx
                    out[k * plane + oy * size + ox] = (top + (bottom - top) * fy) * format.scale + format.bias
                }
            }
        }
        return out
    }
}
