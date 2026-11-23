import Foundation

/// One event log line (already redacted). Stored and sent with the short keys the log receiver reads:
/// `t` time (ISO 8601), `s` session, `l` level (`info`/`error`), `c` category, `m` message.
public struct LogLine: Codable, Sendable, Equatable {
    public var time: String
    public var session: String
    public var level: String
    public var category: String
    public var message: String

    public init(time: String, session: String, level: String, category: String, message: String) {
        self.time = time; self.session = session; self.level = level; self.category = category; self.message = message
    }

    public var isError: Bool { level == "error" }

    enum CodingKeys: String, CodingKey {
        case time = "t", session = "s", level = "l", category = "c", message = "m"
    }
}

/// Task 1.5: the event log history on the device (independent of the remote log). Keeps the newest `capacity`
/// lines; the app stores it in Caches as `fileName` every `saveInterval` seconds and shows it under
/// Einstellungen › System › Diagnose.
public struct LogRing: Codable, Sendable, Equatable {
    public static let defaultCapacity = 2000
    public static let fileName = "log-ring.json"
    public static let saveInterval: TimeInterval = 30
    /// Lines on the „Diagnose“ page.
    public static let pageLines = 200

    public let capacity: Int
    /// Circular storage; once full, `start` is the oldest line.
    private var buffer: [LogLine] = []
    private var start = 0

    public init(capacity: Int = LogRing.defaultCapacity) {
        self.capacity = max(1, capacity)
        buffer.reserveCapacity(min(self.capacity, 256))
    }

    public var count: Int { buffer.count }

    public mutating func append(_ line: LogLine) {
        if buffer.count < capacity {
            buffer.append(line)
        } else {
            buffer[start] = line
            start = (start + 1) % capacity
        }
    }

    /// All lines, oldest first.
    public func snapshot() -> [LogLine] {
        guard start > 0 else { return buffer }
        return Array(buffer[start...] + buffer[..<start])
    }

    /// The newest `limit` lines, newest first; with `errorsOnly` only error lines.
    public func recent(_ limit: Int, errorsOnly: Bool) -> [LogLine] {
        var out: [LogLine] = []
        out.reserveCapacity(min(limit, buffer.count))
        var i = buffer.count
        while i > 0, out.count < limit {
            i -= 1
            let line = buffer[(start + i) % buffer.count]
            if !errorsOnly || line.isError { out.append(line) }
        }
        return out
    }

    enum CodingKeys: String, CodingKey { case capacity, lines }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cap = (try? c.decodeIfPresent(Int.self, forKey: .capacity)) ?? nil
        self.init(capacity: cap ?? LogRing.defaultCapacity)
        let lines = (try? c.decodeIfPresent([LogLine].self, forKey: .lines)) ?? nil ?? []
        for l in lines.suffix(capacity) { append(l) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(capacity, forKey: .capacity)
        try c.encode(snapshot(), forKey: .lines)
    }

    public static func == (a: LogRing, b: LogRing) -> Bool { a.capacity == b.capacity && a.snapshot() == b.snapshot() }
}

/// Task 1.5 (SEC-2): which announced log receiver gets the log. Only the receiver chosen on the TV, only when the
/// remote log is switched on and a shared secret is set; never simply the first `_playerlog._tcp` service found.
public enum RemoteLogTarget {
    public enum Status: Equatable, Sendable {
        /// Remote log off (the default): lines stay on the device.
        case off
        /// On, but no receiver chosen yet.
        case noReceiver
        /// On, receiver chosen, but no shared secret from the phone page.
        case noSecret
        /// The chosen receiver is not announced right now.
        case notFound
        /// Lines go to the chosen receiver.
        case ready
    }

    public static func status(enabled: Bool, receiver: String?, secret: String?, found: [String]) -> Status {
        guard enabled else { return .off }
        guard let receiver, !receiver.isEmpty else { return .noReceiver }
        guard let secret, !secret.isEmpty else { return .noSecret }
        return found.contains(receiver) ? .ready : .notFound
    }

    /// The service name to send to, or nil.
    public static func pick(enabled: Bool, receiver: String?, secret: String?, found: [String]) -> String? {
        status(enabled: enabled, receiver: receiver, secret: secret, found: found) == .ready ? receiver : nil
    }
}
