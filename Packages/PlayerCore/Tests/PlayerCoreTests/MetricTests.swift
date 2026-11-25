import Foundation
import Testing
@testable import PlayerCore

// Task 1.8: measuring points for the remote log (`metric: <name> <ms> · …`).

@Test func metricLineFormat() {
    #expect(Metric.category == "metric")
    #expect(Metric.line(.startUsable, ms: 812) == "start.usable 812")
    #expect(Metric.line(.startCatalog, ms: 140, fields: ["reihen": "6", "lesen": "35"])
            == "start.catalog 140 · reihen 6 · lesen 35")
    #expect(Metric.line(.playerFirstFrame, ms: -5) == "player.firstFrame 0")
    #expect(Metric.ms(.milliseconds(1500)) == 1500)
    #expect(Metric.ms(.microseconds(2600)) == 3)
    #expect(Metric.ms(.seconds(-1)) == 0)
    // The redaction of the event log leaves measuring lines alone.
    let sample = Metric.line(.syncMerged, ms: 12, fields: ["eintraege": "40", "geaendert": "ja"])
    #expect(LogRedact.text(sample) == sample)
}

@Test func metricNamesAreUniqueAndFixed() {
    let names = Metric.allCases.map(\.rawValue)
    #expect(names == ["start.usable", "start.profiles", "start.catalog", "detail.badges", "streams.firstRow",
                      "streams.order", "player.loadBegins", "player.firstFrame", "player.audioReload", "sync.merged",
                      "home.rowBody"])
    #expect(Set(names).count == names.count)
    for m in Metric.allCases {
        #expect(m.rawValue.range(of: #"^[a-z]+\.[A-Za-z]+$"#, options: .regularExpression) != nil)
        #expect(LogRedact.text(Metric.line(m, ms: 1234)) == Metric.line(m, ms: 1234))
    }
}

@Test func startTimingKeepsMonotonicPoints() {
    let d = Date(timeIntervalSince1970: 1_000)
    var t = StartTiming()
    t.markTap(d, uptime: 50)
    t.markResolved(d.addingTimeInterval(0.4), uptime: 50.4)
    t.markFirstFrame(d.addingTimeInterval(1.2), uptime: 51.2)
    #expect(StartTiming.ms(t.tapUptime, t.resolvedUptime) == 400)
    #expect(StartTiming.ms(t.resolvedUptime, t.firstFrameUptime) == 800)
    #expect(StartTiming.ms(t.tapUptime, nil) == nil)
    #expect(StartTiming.ms(10, 9) == 0)
    // A stale press (older than maxTapAge on the monotonic clock) is dropped even if the wall clock jumped back.
    var s = StartTiming()
    s.markTap(d, uptime: 10)
    s.markResolved(d.addingTimeInterval(1), uptime: 10 + StartTiming.maxTapAge + 1)
    #expect(s.tap == nil && s.tapUptime == nil && s.resolvedUptime != nil)
    _ = s.markPlaying(d.addingTimeInterval(2))
    #expect(s.tapUptime == nil)
}

@Test func phoneConfirmationLogLine() {
    let exp = Date(timeIntervalSince1970: 0)
    let addon = PhoneConfirmation(commands: [.addAddon("https://example.invalid/manifest.json")], summary: [], expires: exp)
    #expect(addon.logLine(.allowed) == "Bestätigung Addon erlaubt")
    let keys = PhoneConfirmation(commands: [.setKey(service: "tmdb", value: "x"), .setKey(service: "mdblist", value: "y"),
                                            .importBackup(Data())], summary: [], expires: exp)
    #expect(keys.logLine(.declined) == "Bestätigung Schlüssel+Import abgelehnt")
    #expect(PhoneConfirmation(commands: [.exportSecrets], summary: [], expires: exp).logLine(.lapsed)
            == "Bestätigung Sicherung abgelaufen")
    #expect(PhoneConfirmation(commands: [.setKey(service: AtvloadlyAddress.key, value: "h")], summary: [], expires: exp)
                .logKind == "Adresse")
}
