import Foundation
import Testing
@testable import PlayerCore

// Wave F-p: detail page load times and the parallel TMDB request.

@Test func typeDecidesOnlyForKnownTypes() {
    #expect(ContentKind.typeDecides("movie"))
    #expect(ContentKind.typeDecides("series"))
    #expect(ContentKind.typeDecides("anime"))
    #expect(ContentKind.typeDecides("tmdb.movie"))
    // Unknown addon types: the meta's episode list decides, so TMDB waits for it.
    #expect(!ContentKind.typeDecides("tv"))
    #expect(!ContentKind.typeDecides(""))
}

@Test func timelineLogsOnceWhenAllRequiredPartsArrived() {
    var t = DetailLoadTimeline(title: "Die Odyssee", expectsTech: true)
    t.mark(.id, ms: 425)
    t.mark(.tmdb, ms: 430)
    t.mark(.poster, ms: 460)
    #expect(t.takeLine() == nil)
    t.mark(.meta, ms: 1834)
    #expect(t.takeLine() == nil)   // tech still missing
    t.mark(.tech, ms: 3236, source: "neu, 900 Quellen")
    #expect(t.takeLine() == "Ladezeiten Die Odyssee · ID 425 ms · TMDB 430 ms · Meta 1834 ms · Poster 460 ms · Technik 3236 ms (neu, 900 Quellen)")
    #expect(t.takeLine() == nil)
    #expect(t.takeLine(force: true) == nil)
}

@Test func timelineKeepsTheFirstArrival() {
    var t = DetailLoadTimeline(title: "x", expectsTech: true)
    t.mark(.tech, ms: 12, source: "Cache")
    t.mark(.tech, ms: 900, source: "neu, 3 Quellen")
    t.mark(.id, ms: -5)
    #expect(t.times[.tech] == 12)
    #expect(t.techSource == "Cache")
    #expect(t.times[.id] == 0)
}

@Test func seriesTimelineNeedsNoTechAndForceShowsMissingParts() {
    var s = DetailLoadTimeline(title: "Serie", expectsTech: false)
    s.mark(.id, ms: 0)
    s.mark(.tmdb, ms: 300)
    s.mark(.meta, ms: 800)
    #expect(s.takeLine() == "Ladezeiten Serie · ID 0 ms · TMDB 300 ms · Meta 800 ms · Poster –")

    var m = DetailLoadTimeline(title: "Film", expectsTech: true)
    m.mark(.id, ms: 0)
    #expect(m.takeLine() == nil)
    #expect(m.takeLine(force: true) == "Ladezeiten Film · ID 0 ms · TMDB – · Meta – · Poster – · Technik –")
    #expect(m.logged)
}

@Test func focusRestMatchesTheHeroRest() {
    #expect(FocusRest.milliseconds == 350)
}

@Test func sharedLookupRetriesOnlyAfterAnError() {
    let found = SharedLookup<Int>.found(7), none = SharedLookup<Int>.none, failed = SharedLookup<Int>.failed
    #expect(found.value == 7 && !found.retriesOnJoin)
    // „kein TMDB-Treffer“: no second lookup, no second log line.
    #expect(none.value == nil && !none.retriesOnJoin)
    #expect(failed.value == nil && failed.retriesOnJoin)
}
