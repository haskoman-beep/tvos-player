import Foundation

/// Build 4 follow-up 2 (P3): pictures that went on screen (backdrop swaps, first picture of a poster tile), summed up
/// for one `bilder` line per `window` with activity. Measurement for the stutter search: how many, from the memory
/// cache or loaded (disk/network + decode), how long the load took until the picture faded in, the largest bitmap and
/// the bitmap bytes in all (what the GPU has to take over in that window).
public struct PictureArrivalStats: Sendable, Equatable {
    /// Seconds from the first picture of a window until its line is taken.
    public static let window: TimeInterval = 10

    public let title: String
    public private(set) var count = 0
    public private(set) var fromMemory = 0
    public private(set) var loaded = 0
    public private(set) var fades = 0
    public private(set) var longestWaitMs = 0
    private var loadedWaitMs = 0
    private var largestWidth = 0
    private var largestHeight = 0
    public private(set) var bytes = 0

    public init(title: String) { self.title = title }

    /// One picture on screen. `waitMs`: from the request until it was there (loaded ones only count for the wait);
    /// `fades`: shown with a fade-in. Returns true for the first picture of a new window.
    @discardableResult
    public mutating func record(fromMemory memory: Bool, waitMs: Int, pixelWidth: Int, pixelHeight: Int, bytes b: Int,
                                fades fade: Bool) -> Bool {
        let first = count == 0
        count += 1
        if memory {
            fromMemory += 1
        } else {
            loaded += 1
            loadedWaitMs += waitMs
            longestWaitMs = max(longestWaitMs, waitMs)
        }
        if fade { fades += 1 }
        if pixelWidth * pixelHeight > largestWidth * largestHeight {
            largestWidth = pixelWidth
            largestHeight = pixelHeight
        }
        bytes += b
        return first
    }

    /// The window's log text (nil without pictures); starts a new window.
    public mutating func take() -> String? {
        guard count > 0 else { return nil }
        var line = "\(title) \(count) · aus Speicher \(fromMemory) · geladen \(loaded)"
        if loaded > 0 {
            let avg = Int((Double(loadedWaitMs) / Double(loaded)).rounded())
            line += " (längstes \(longestWaitMs) ms, Ø \(avg) ms)"
        }
        line += " · eingeblendet \(fades) · größtes \(largestWidth)×\(largestHeight) px · zusammen \(Self.mb(bytes)) MB"
        self = PictureArrivalStats(title: title)
        return line
    }

    /// Megabytes (2^20) with one decimal and a decimal comma.
    static func mb(_ bytes: Int) -> String {
        let tenths = Int((Double(bytes) / 1_048_576 * 10).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }
}
