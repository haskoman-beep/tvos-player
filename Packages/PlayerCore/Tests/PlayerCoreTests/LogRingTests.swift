import Foundation
import Testing
@testable import PlayerCore

// Task 1.5: the on-device log history (ring) and the choice of the remote log receiver.

private func line(_ i: Int, level: String = "info") -> LogLine {
    LogLine(time: "2026-01-01T00:00:\(String(format: "%02d", i % 60)).000Z", session: "abcd1234", level: level,
            category: "test", message: "Zeile \(i)")
}

@Test func logRingOverflowKeepsNewest() {
    var r = LogRing(capacity: 5)
    for i in 0..<12 { r.append(line(i)) }
    #expect(r.count == 5)
    #expect(r.snapshot().map(\.message) == ["Zeile 7", "Zeile 8", "Zeile 9", "Zeile 10", "Zeile 11"])
    // Below capacity: everything in order.
    var small = LogRing(capacity: 5)
    small.append(line(1)); small.append(line(2))
    #expect(small.snapshot().map(\.message) == ["Zeile 1", "Zeile 2"])
    #expect(LogRing().capacity == 2000)
}

@Test func logRingSurvivesEncodeDecode() throws {
    var r = LogRing(capacity: 4)
    for i in 0..<7 { r.append(line(i, level: i % 3 == 0 ? "error" : "info")) }
    let data = try JSONEncoder().encode(r)
    var back = try JSONDecoder().decode(LogRing.self, from: data)
    #expect(back.capacity == 4)
    #expect(back.snapshot() == r.snapshot())
    // Keeps working as a ring after decoding.
    back.append(line(99))
    #expect(back.snapshot().map(\.message) == ["Zeile 4", "Zeile 5", "Zeile 6", "Zeile 99"])
    // A stored file with more lines than the capacity keeps the newest; the line keys stay short (t, s, l, c, m).
    let json = #"{"capacity":2,"lines":[{"t":"a","s":"x","l":"info","c":"c","m":"1"},{"t":"b","s":"x","l":"error","c":"c","m":"2"},{"t":"c","s":"x","l":"info","c":"c","m":"3"}]}"#
    let trimmed = try JSONDecoder().decode(LogRing.self, from: Data(json.utf8))
    #expect(trimmed.snapshot().map(\.message) == ["2", "3"])
    #expect(String(decoding: try JSONEncoder().encode(line(1)), as: UTF8.self).contains(#""m":"Zeile 1""#))
}

@Test func logRingRecentNewestFirstAndErrorFilter() {
    var r = LogRing(capacity: 10)
    for i in 0..<8 { r.append(line(i, level: i.isMultiple(of: 2) ? "error" : "info")) }
    #expect(r.recent(3, errorsOnly: false).map(\.message) == ["Zeile 7", "Zeile 6", "Zeile 5"])
    #expect(r.recent(3, errorsOnly: true).map(\.message) == ["Zeile 6", "Zeile 4", "Zeile 2"])
    #expect(r.recent(200, errorsOnly: true).count == 4)
}

@Test func remoteLogTargetOnlyTheChosenReceiver() {
    let found = ["Player-Log", "Fremder-Dienst"]
    // Off by default: nothing goes out even with a receiver in the network.
    #expect(RemoteLogTarget.pick(enabled: false, receiver: "Player-Log", secret: "s", found: found) == nil)
    #expect(RemoteLogTarget.status(enabled: false, receiver: "Player-Log", secret: "s", found: found) == .off)
    // On, but no receiver chosen, no secret, or the chosen one is not announced.
    #expect(RemoteLogTarget.pick(enabled: true, receiver: nil, secret: "s", found: found) == nil)
    #expect(RemoteLogTarget.status(enabled: true, receiver: nil, secret: "s", found: found) == .noReceiver)
    #expect(RemoteLogTarget.pick(enabled: true, receiver: "Player-Log", secret: "", found: found) == nil)
    #expect(RemoteLogTarget.status(enabled: true, receiver: "Player-Log", secret: nil, found: found) == .noSecret)
    #expect(RemoteLogTarget.pick(enabled: true, receiver: "Weg", secret: "s", found: found) == nil)
    #expect(RemoteLogTarget.status(enabled: true, receiver: "Weg", secret: "s", found: found) == .notFound)
    // Exactly the chosen name, never "the first one found".
    #expect(RemoteLogTarget.pick(enabled: true, receiver: "Player-Log", secret: "s", found: found) == "Player-Log")
    #expect(RemoteLogTarget.pick(enabled: true, receiver: "player-log", secret: "s", found: found) == nil)
    #expect(RemoteLogTarget.status(enabled: true, receiver: "Player-Log", secret: "s", found: found) == .ready)
}
