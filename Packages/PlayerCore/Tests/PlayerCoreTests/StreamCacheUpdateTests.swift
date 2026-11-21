import Foundation
import Testing
@testable import PlayerCore

// Zusammenführung Welle C: Addon-Suche mit Zeitgrenzen (lückenhaft) + Quellen-Cache mit Hintergrund-Erneuerung.

private typealias Entry = (addon: String, stream: String)

private func stored(_ o: StreamCacheUpdate.Outcome<String>) -> (at: Date, list: [String], fetchedAt: [String: Date])? {
    if case let .store(at, list, fetchedAt) = o { return (at, list.map(\.stream), fetchedAt) }
    return nil
}

@Test func cacheUpdateCompleteResultIsFreshAndReplaces() {
    let now = Date()
    let old: [Entry] = [("A", "a1"), ("B", "b1")]
    let o = StreamCacheUpdate.apply(fresh: [("A", "a2"), ("B", "b2")], answered: ["A", "B"], failed: [],
                                    previous: (now.addingTimeInterval(-300), old), previousFetchedAt: [:], now: now)
    let s = stored(o)
    #expect(s?.list == ["a2", "b2"])
    #expect(s?.at == now)
    #expect(s?.fetchedAt == ["A": now, "B": now])
}

@Test func cacheUpdatePartialKeepsFailedAddonAndIsFreshOnlyBriefly() {
    let now = Date()
    let t0 = now.addingTimeInterval(-600)
    let old: [Entry] = [("A", "a1"), ("B", "b1")]
    // B mit Zeitüberschreitung: b1 bleibt (alte Abrufzeit), der Stand ist nur 60 s frisch, danach veraltet.
    let o = StreamCacheUpdate.apply(fresh: [("A", "a2")], answered: ["A"], failed: ["B"],
                                    previous: (t0, old), previousFetchedAt: ["A": t0, "B": t0], now: now)
    let s = stored(o)
    #expect(s?.list == ["a2", "b1"])
    #expect(s?.fetchedAt == ["A": now, "B": t0])
    let at = s!.at
    #expect(RevalidationPolicy.streams.state(storedAt: at, now: now.addingTimeInterval(59)) == .fresh)
    #expect(RevalidationPolicy.streams.state(storedAt: at, now: now.addingTimeInterval(61)) == .stale)
    #expect(RevalidationPolicy.streams.isUsable(storedAt: at, now: now.addingTimeInterval(20 * 60)))
}

@Test func cacheUpdateOnlyFailedAddonsAreKept() {
    let now = Date()
    let old: [Entry] = [("A", "a1"), ("B", "b1"), ("C", "c1")]
    // C hat für diesen Inhalt nicht gefragt (weder Antwort noch Fehler): seine alten Einträge fallen weg.
    let o = StreamCacheUpdate.apply(fresh: [("A", "a2")], answered: ["A"], failed: ["B"],
                                    previous: (now.addingTimeInterval(-100), old), previousFetchedAt: [:], now: now)
    #expect(stored(o)?.list == ["a2", "b1"])
}

@Test func cacheUpdateEmptyKeepsPreviousNeverShortens() {
    let now = Date()
    let old: [Entry] = [("A", "a1"), ("B", "b1")]
    // A gedrosselt (leer), B ausgefallen: alter Stand bleibt unverändert (N-1), kein Zurückdatieren (N1).
    let o = StreamCacheUpdate.apply(fresh: [], answered: ["A"], failed: ["B"],
                                    previous: (now.addingTimeInterval(-200), old), previousFetchedAt: [:], now: now)
    #expect(stored(o) == nil)
    // Alles ausgefallen, kein alter Stand: ebenfalls nichts ablegen.
    let o2 = StreamCacheUpdate.apply(fresh: [Entry](), answered: [], failed: ["A", "B"],
                                     previous: nil, previousFetchedAt: [:], now: now)
    #expect(stored(o2) == nil)
}

@Test func cacheUpdateRepeatedPartialDropsFailedAddonAfter30Minutes() {
    let t0 = Date()
    var cache: (at: Date, list: [Entry]) = (t0, [("A", "a0"), ("B", "b0")])
    var fetched: [String: Date] = ["A": t0, "B": t0]
    // B fällt ab Minute 5 dauerhaft aus; alle 5 min eine neue Suche.
    for minutes in stride(from: 5.0, through: 25, by: 5) {
        let now = t0.addingTimeInterval(minutes * 60)
        let s = stored(StreamCacheUpdate.apply(fresh: [("A", "a\(Int(minutes))")], answered: ["A"], failed: ["B"],
                                               previous: cache, previousFetchedAt: fetched, now: now))!
        #expect(s.list.contains("b0"))
        cache = (s.at, s.list.map { $0 == "b0" ? ("B", $0) : ("A", $0) }); fetched = s.fetchedAt
    }
    // Beim Lesen nach 31 min: b0 nicht mehr zeigen (M-A), obwohl der Stand selbst noch zeigbar ist.
    let read = t0.addingTimeInterval(31 * 60)
    #expect(RevalidationPolicy.streams.isUsable(storedAt: cache.at, now: read))
    let shown = StreamListMerge.usable(cache.list, fetchedAt: fetched, storedAt: cache.at, now: read,
                                       maxAge: RevalidationPolicy.streams.usableFor)
    #expect(shown.map(\.stream) == ["a25"])
    // Nächste Suche nach 31 min: b0 fällt auch beim Zusammenführen weg.
    let s = stored(StreamCacheUpdate.apply(fresh: [("A", "a31")], answered: ["A"], failed: ["B"],
                                           previous: cache, previousFetchedAt: fetched, now: read))!
    #expect(s.list == ["a31"])
}

@Test func usableFallsBackToStoredAt() {
    let now = Date()
    let list: [Entry] = [("A", "a"), ("B", "b")]
    let r = StreamListMerge.usable(list, fetchedAt: ["A": now.addingTimeInterval(-2000)],
                                   storedAt: now.addingTimeInterval(-10), now: now, maxAge: 1800)
    #expect(r.map(\.stream) == ["b"])
}
