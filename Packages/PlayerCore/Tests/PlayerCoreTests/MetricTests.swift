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
                      "streams.order", "player.loadBegins", "player.firstFrame", "player.audioReload", "sync.merged"])
    #expect(Set(names).count == names.count)
    for m in Metric.allCases {
        #expect(m.rawValue.range(of: #"^[a-z]+\.[A-Za-z]+$"#, options: .regularExpression) != nil)
        #expect(LogRedact.text(Metric.line(m, ms: 1234)) == Metric.line(m, ms: 1234))
    }
}
