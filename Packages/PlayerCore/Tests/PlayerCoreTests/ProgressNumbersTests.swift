import Foundation
import Testing
@testable import PlayerCore

// Phase 0a.1 (part 3): invalid numbers in `ProgressBook` and `FileProgressBook`. A bad player report or remote
// fraction is ignored (the existing entry stays); a bad stored number is repaired field by field; every number that
// leaves a book is finite and in its range, and encoding never fails because of a number.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let film = MetaPreview(id: "tt1", type: "movie", name: "Der Film")
private let show = MetaPreview(id: "tt9", type: "series", name: "Die Serie")
private let fileKey = "torbox:1:1"

/// Test arguments are number names, not Doubles: Swift Testing may identify an Encodable argument by its JSON form,
/// which NaN and the infinities do not have.
private func number(_ name: String) -> Double {
    switch name {
    case "nan": return .nan
    case "+inf": return .infinity
    case "-inf": return -.infinity
    default: return Double(name)!
    }
}

private let nonFinite = ["nan", "+inf", "-inf"]

/// (position, duration) pairs of entries written directly into a book.
private let badPairs: [(String, String)] = [
    ("nan", "2400"), ("+inf", "2400"), ("-inf", "2400"), ("-50", "2400"), ("5000", "2400"),
    ("600", "nan"), ("600", "+inf"), ("600", "-inf"), ("600", "-10"), ("600", "0"), ("nan", "nan"),
]

/// Remote fractions of entries written directly into a book.
private let badRemoteFractions: [Double?] = [nil, .nan, .infinity, -0.5, 0.4, 3]

private func nums(_ e: WatchProgress?) -> [Double]? { e.map { [$0.position, $0.duration] } }
private func nums(_ e: FileProgressBook.Entry?) -> [Double]? { e.map { [$0.position, $0.duration] } }

/// ISO 8601 coders like `ProgressStore`.
private func isoEncoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
private func isoDecoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

/// A book with one good, half-watched film entry.
private func goodBook() -> ProgressBook {
    var b = ProgressBook()
    b.record(id: "tt1", item: film, position: 600, duration: 2400, now: t0)
    return b
}

private func goodFileBook() -> FileProgressBook {
    var b = FileProgressBook()
    b.record(fileKey, position: 600, duration: 2400, now: t0)
    return b
}

/// Every number a book hands out for `id` is finite and in its range.
private func expectUsable(_ b: ProgressBook, _ id: String, itemID: String) {
    if let e = b.entries[id] {
        #expect(e.fraction.isFinite && (0...1).contains(e.fraction))
        let n = e.normalized()
        #expect(n.position.isFinite && n.position >= 0 && n.duration.isFinite && n.duration >= 0)
        if n.duration > 0 { #expect(n.position <= n.duration) }
    }
    if let p = b.resumePosition(for: id) {
        let d = b.entries[id]?.normalized().duration ?? 0
        #expect(p.isFinite && p >= 0 && (d == 0 || p <= d))
    }
    if let f = b.resumeFraction(for: id) { #expect(f.isFinite && (0...1).contains(f)) }
    if let c = b.cardState(itemID: itemID) {
        if let f = c.fraction { #expect(f.isFinite && (0...1).contains(f)) }
        if let r = c.remainingSeconds { #expect(r.isFinite && r >= 0) }
    }
    for e in b.continueWatching() + b.history() {
        #expect(e.position.isFinite && e.duration.isFinite && e.fraction.isFinite)
        #expect(e.updated.timeIntervalSinceReferenceDate.isFinite)
    }
    #expect(throws: Never.self) { _ = try JSONEncoder().encode(b) }
    #expect(throws: Never.self) { _ = try isoEncoder().encode(b) }
}

// MARK: ProgressBook – player reports

@Test(arguments: nonFinite + ["-1", "-0.001", "-6000"])
func progressReportWithBadPositionIsIgnored(badName: String) throws {
    let bad = number(badName)
    var b = goodBook()
    let before = b.entries["tt1"]
    b.record(id: "tt1", item: film, position: bad, duration: 2400, now: t0.addingTimeInterval(60))
    #expect(b.entries["tt1"] == before)                     // the good entry is not damaged
    b.record(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "Neu"), position: bad, duration: 2400, now: t0)
    #expect(b.entries["tt2"] == nil)                        // and no new entry
    expectUsable(b, "tt1", itemID: "tt1")
}

@Test(arguments: nonFinite + ["0", "-0.0", "-1", "-2400"])
func progressReportWithBadDurationIsIgnored(badName: String) throws {
    let bad = number(badName)
    var b = goodBook()
    let before = b.entries["tt1"]
    b.record(id: "tt1", item: film, position: 900, duration: bad, now: t0.addingTimeInterval(60))
    #expect(b.entries["tt1"] == before)
    b.record(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "Neu"), position: 900, duration: bad, now: t0)
    #expect(b.entries["tt2"] == nil)
    expectUsable(b, "tt1", itemID: "tt1")
}

@Test func progressReportWithBothNumbersBadIsIgnored() {
    var b = goodBook()
    let before = b.entries["tt1"]
    b.record(id: "tt1", item: film, position: .nan, duration: .nan, now: t0.addingTimeInterval(60))
    b.record(id: "tt1", item: film, position: .infinity, duration: .infinity, now: t0.addingTimeInterval(60))
    #expect(b.entries["tt1"] == before)
}

@Test(arguments: [2400.001, 2401, 1e9, Double.greatestFiniteMagnitude])
func progressReportBeyondTheEndCountsAsTheEnd(position: Double) throws {
    var b = ProgressBook()
    b.record(id: "tt1", item: film, position: position, duration: 2400, now: t0)
    let e = try #require(b.entries["tt1"])
    #expect(e.finished && e.position == 0 && e.duration == 2400)   // clamped to 2400 → the 92 % rule: watched
    expectUsable(b, "tt1", itemID: "tt1")
}

@Test func progressReportBeyondTheEndOfAnEpisodeKeepsTheSeriesRules() throws {
    var b = ProgressBook()
    b.record(id: "tt9:1:1", item: show, season: 1, episode: 1, position: 1e12, duration: 2400, now: t0)
    #expect(b.isWatched("tt9:1:1"))
    #expect(b.cardState(itemID: "tt9") == CardState(episode: "S1 F1"))
}

@Test func progressReportWithBadRemoteFractionKeepsNoBadNumber() throws {
    var b = ProgressBook()
    b.record(WatchProgress(id: "tt1", item: film, position: 600, duration: 2400, remoteFraction: .nan), now: t0)
    #expect(b.entries["tt1"]?.remoteFraction == nil)
    b.record(WatchProgress(id: "tt1", item: film, position: 700, duration: 2400, remoteFraction: 7), now: t0)
    #expect(b.entries["tt1"]?.remoteFraction == 1)
}

@Test func progressReportWithBadDateGetsAUsableDate() throws {
    var b = ProgressBook()
    b.record(id: "tt1", item: film, position: 600, duration: 2400, now: Date(timeIntervalSinceReferenceDate: .nan))
    #expect(b.entries["tt1"]?.updated == .distantPast)
    b.record(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "B"), position: 600, duration: 2400,
             now: Date(timeIntervalSinceReferenceDate: 1e300))
    #expect(b.entries["tt2"]?.updated == .distantFuture)
    b.recordNextUp(id: "tt9:1:2", item: show, season: 1, episode: 2, now: Date(timeIntervalSinceReferenceDate: -.infinity))
    #expect(b.entries["tt9:1:2"]?.updated == .distantPast)
    let back = try isoDecoder().decode(ProgressBook.self, from: try isoEncoder().encode(b))
    #expect(Set(back.entries.keys) == ["tt1", "tt2", "tt9:1:2"])
}

// MARK: ProgressBook – remote merge

@Test(arguments: nonFinite + ["-0.2", "-1"])
func remoteProgressWithBadFractionIsIgnored(badName: String) throws {
    let bad = number(badName)
    var b = goodBook()
    let before = b.entries["tt1"]
    b.merge(remote: [RemoteProgress(id: "tt1", item: film, fraction: bad, updated: t0.addingTimeInterval(3600)),
                     RemoteProgress(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "B"), fraction: bad,
                                    updated: t0.addingTimeInterval(3600))])
    #expect(b.entries["tt1"] == before)
    #expect(b.entries["tt2"] == nil)
}

@Test func remoteProgressAboveOneCountsAsWatched() throws {
    var b = goodBook()
    b.merge(remote: [RemoteProgress(id: "tt1", item: film, fraction: 1.05, updated: t0.addingTimeInterval(3600)),
                     RemoteProgress(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "B"), fraction: 40,
                                    updated: t0.addingTimeInterval(3600))])
    let a = try #require(b.entries["tt1"]), c = try #require(b.entries["tt2"])
    #expect(a.finished && a.position == 2400 && a.duration == 2400)   // merge keeps fraction × length, as before
    #expect(c.finished && c.remoteFraction == 1 && c.duration == 0)
    expectUsable(b, "tt1", itemID: "tt1")
    expectUsable(b, "tt2", itemID: "tt2")
}

@Test func remoteProgressInRangeStillWorks() throws {
    var b = goodBook()
    b.merge(remote: [RemoteProgress(id: "tt1", item: film, fraction: 0.5, updated: t0.addingTimeInterval(3600))])
    #expect(b.entries["tt1"]?.position == 1200 && b.entries["tt1"]?.remoteFraction == nil)
}

@Test func remoteProgressWithBadDateLosesAgainstLocal() throws {
    var b = goodBook()
    let before = b.entries["tt1"]
    b.merge(remote: [RemoteProgress(id: "tt1", item: film, fraction: 0.5, updated: Date(timeIntervalSinceReferenceDate: .nan))])
    #expect(b.entries["tt1"] == before)                     // NaN date → distantPast → the local entry is newer
    b.merge(remote: [RemoteProgress(id: "tt2", item: MetaPreview(id: "tt2", type: "movie", name: "B"), fraction: 0.5,
                                    updated: Date(timeIntervalSinceReferenceDate: .nan))])
    #expect(b.entries["tt2"]?.updated == .distantPast && b.entries["tt2"]?.remoteFraction == 0.5)
    #expect(throws: Never.self) { _ = try JSONEncoder().encode(b) }
}

@Test func remoteMergeIgnoresABadLocalDuration() throws {
    var b = ProgressBook()
    b.entries["tt1"] = WatchProgress(id: "tt1", item: film, position: 600, duration: .infinity, updated: t0)
    b.merge(remote: [RemoteProgress(id: "tt1", item: film, fraction: 0.5, updated: t0.addingTimeInterval(3600))])
    let e = try #require(b.entries["tt1"])
    #expect(e.duration == 0 && e.position == 0 && e.remoteFraction == 0.5)   // length unknown → remote fraction
    expectUsable(b, "tt1", itemID: "tt1")
}

// MARK: ProgressBook – bad entries in memory (direct writes) never leave the book

@Test(arguments: badPairs)
func badEntryInMemoryGivesUsableNumbers(positionName: String, durationName: String) throws {
    let position = number(positionName), duration = number(durationName)
    for rf in badRemoteFractions {
        var b = ProgressBook()
        b.entries["tt1"] = WatchProgress(id: "tt1", item: film, position: position, duration: duration, updated: t0, remoteFraction: rf)
        b.entries["tt9:1:1"] = WatchProgress(id: "tt9:1:1", item: show, season: 1, episode: 1, position: position,
                                             duration: duration, updated: t0, remoteFraction: rf)
        expectUsable(b, "tt1", itemID: "tt1")
        expectUsable(b, "tt9:1:1", itemID: "tt9")
        // Encoded, the repaired entries come back.
        let back = try JSONDecoder().decode(ProgressBook.self, from: try JSONEncoder().encode(b))
        #expect(back.entries["tt1"] == b.entries["tt1"]?.normalized())
        #expect(back.entries["tt9:1:1"] == b.entries["tt9:1:1"]?.normalized())
    }
}

@Test func positionBeyondTheEndInMemoryResumesAtTheEnd() throws {
    var b = ProgressBook()
    b.entries["tt1"] = WatchProgress(id: "tt1", item: film, position: 5000, duration: 2400, updated: t0)
    #expect(b.resumePosition(for: "tt1") == 2400)
    #expect(b.entries["tt1"]?.fraction == 1)
    #expect(b.cardState(itemID: "tt1") == CardState(fraction: 1, remainingSeconds: 0))
}

@Test func encodeNeverFailsOnBadDatesFromThePublicAPI() throws {
    var b = ProgressBook()
    b.entries["tt1"] = WatchProgress(id: "tt1", item: film, position: .nan, duration: .infinity,
                                     updated: Date(timeIntervalSinceReferenceDate: .nan), remoteFraction: -.infinity)
    b.rememberSource(StreamItem(name: "A", url: "https://example.invalid/a"), addon: "A", for: "tt1",
                     now: Date(timeIntervalSinceReferenceDate: .nan))
    b.sources?["tt2"] = LastSource(stream: StreamItem(name: "B", url: "https://example.invalid/b"), addon: "B",
                                   contentID: "tt2", savedAt: Date(timeIntervalSinceReferenceDate: .infinity))
    #expect(b.lastSource(for: "tt1")?.savedAt == .distantPast)
    let plain = try JSONEncoder().encode(b)
    let iso = try isoEncoder().encode(b)
    let back = try JSONDecoder().decode(ProgressBook.self, from: plain)
    let backISO = try isoDecoder().decode(ProgressBook.self, from: iso)
    for x in [back, backISO] {
        let e = try #require(x.entries["tt1"])
        #expect(e.position == 0 && e.duration == 0 && e.remoteFraction == nil)
        #expect(e.updated < t0 && x.sources?["tt2"].map { $0.savedAt < t0 } == true)
    }
    // Exact through the numeric form (the ISO 8601 form of year 1 may differ by the calendar's days).
    #expect(back.entries["tt1"]?.updated == .distantPast && back.sources?["tt2"]?.savedAt == .distantPast)
    // Also inside a backup (default JSONEncoder, dates as numbers).
    let backup = Backup(profiles: StoredProfiles.makeDefault(), progress: [UUID(): b])
    #expect(throws: Never.self) { _ = try backup.encoded() }
}

// MARK: ProgressBook – stored blocks

/// A stored block (ISO 8601 dates, as `ProgressStore` writes it) with one good and several bad entries.
private let storedBlock = #"""
{"schemaVersion":1,"entries":{
 "tt1":{"id":"tt1","item":{"id":"tt1","type":"movie","name":"Gut"},"position":600,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false},
 "tt2":{"id":"tt2","item":{"id":"tt2","type":"movie","name":"Rückwärts"},"position":-50,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false},
 "tt3":{"id":"tt3","item":{"id":"tt3","type":"movie","name":"Minuslänge"},"position":700,"duration":-10,"updated":"2027-01-15T08:00:00Z","finished":false},
 "tt4":{"id":"tt4","item":{"id":"tt4","type":"movie","name":"Zu weit"},"position":5000,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false},
 "tt5":{"id":"tt5","item":{"id":"tt5","type":"movie","name":"Fern hoch"},"position":0,"duration":0,"updated":"2027-01-15T08:00:00Z","finished":false,"remoteFraction":1.7},
 "tt6":{"id":"tt6","item":{"id":"tt6","type":"movie","name":"Fern tief"},"position":0,"duration":0,"updated":"2027-01-15T08:00:00Z","finished":false,"remoteFraction":-0.3},
 "tt7:1:2":{"id":"tt7:1:2","item":{"id":"tt7","type":"series","name":"Serie"},"season":1,"episode":2,"position":0,"duration":0,"updated":"2027-01-15T08:00:00Z","finished":false,"nextUp":true},
 "tt9":{"id":"tt9","item":{"id":"tt9","type":"movie","name":"Falscher Typ"},"position":"viel","duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false},
 "tt10":{"id":"tt10","item":{"id":"tt10","type":"movie","name":"Gesehen zu weit"},"position":9000,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":true}
}}
"""#

@Test func storedBlockWithBadEntriesKeepsTheGoodOnesAndRepairsTheRest() throws {
    let (b, report) = try isoDecoder().decodeReporting(ProgressBook.self, from: Data(storedBlock.utf8))
    let good = try #require(b.entries["tt1"])
    #expect(good.position == 600 && good.duration == 2400 && !good.finished && good.item.name == "Gut")
    #expect(nums(b.entries["tt2"]) == [0, 2400])
    #expect(nums(b.entries["tt3"]) == [700, 0])                                  // length unknown, position kept
    #expect(nums(b.entries["tt4"]) == [2400, 2400] && b.entries["tt4"]?.finished == false)
    #expect(b.entries["tt5"]?.remoteFraction == 1 && b.entries["tt6"]?.remoteFraction == 0)
    #expect(b.entries["tt7:1:2"]?.nextUp == true && b.entries["tt7:1:2"]?.season == 1)   // other fields stay
    #expect(b.entries["tt9"] == nil)                                             // unreadable: dropped, noted
    #expect(report.ignored.contains(where: { $0.contains("tt9") }))
    let seen = try #require(b.entries["tt10"])
    #expect(seen.finished && seen.position == 2400)
    for id in b.entries.keys { expectUsable(b, id, itemID: b.entries[id]?.item.id ?? id) }
    // Re-encoded and read again: the same repaired book, nothing dropped any more.
    let again = try isoDecoder().decode(ProgressBook.self, from: try isoEncoder().encode(b))
    #expect(again == b)
}

@Test func storedBlockThroughTheStoreKeepsTheGoodEntries() throws {
    let dir = tempDir()
    let store = ProgressStore(directory: dir)
    let id = UUID()
    try Data(storedBlock.utf8).write(to: dir.appendingPathComponent("progress-\(id.uuidString).json"))
    let b = try #require(store.load(profile: id))
    #expect(b.entries["tt1"]?.position == 600 && b.entries["tt9"] == nil)
    // The unreadable entry is left out; the file as it was stays as .bak.
    let bak = dir.appendingPathComponent("progress-\(id.uuidString).json.bak")
    #expect(try Data(contentsOf: bak) == Data(storedBlock.utf8))
    try store.save(b, profile: id)
    let again = try #require(store.load(profile: id))
    #expect(again == b)
}

@Test func storedBlockWithAbsurdDatesIsRepaired() throws {
    // Dates as numbers (default strategy, as in a backup): absurd but finite values are clamped, so the ISO 8601
    // form `ProgressStore` writes afterwards stays readable.
    let json = #"""
    {"schemaVersion":1,"entries":{
     "a":{"id":"a","item":{"id":"a","type":"movie","name":"A"},"position":600,"duration":2400,"updated":1e300,"finished":false},
     "b":{"id":"b","item":{"id":"b","type":"movie","name":"B"},"position":600,"duration":2400,"updated":-1e300,"finished":false}
    }}
    """#
    let b = try JSONDecoder().decode(ProgressBook.self, from: Data(json.utf8))
    #expect(b.entries["a"]?.updated == .distantFuture && b.entries["b"]?.updated == .distantPast)
    let back = try isoDecoder().decode(ProgressBook.self, from: try isoEncoder().encode(b))
    #expect(back.entries["a"].map { $0.updated > t0 } == true && back.entries["b"].map { $0.updated < t0 } == true)
}

@Test func backupWithBadProgressEntryKeepsTheBook() throws {
    let s = StoredProfiles.makeDefault()
    let pid = UUID()
    // Backup form: default JSONEncoder, dates as numbers.
    let progress = #"""
    {"\#(pid.uuidString)":{"schemaVersion":1,"entries":{
     "tt1":{"id":"tt1","item":{"id":"tt1","type":"movie","name":"Gut"},"position":600,"duration":2400,"updated":820000000,"finished":false},
     "tt2":{"id":"tt2","item":{"id":"tt2","type":"movie","name":"Kaputt"},"position":-5,"duration":-1,"updated":820000000,"finished":false,"remoteFraction":9},
     "tt3":{"id":"tt3","item":{"id":"tt3","type":"movie","name":"Unlesbar"},"position":"x","duration":1,"updated":820000000,"finished":false}
    }}}
    """#
    var json = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(s)) as? [String: Any])
    json["backupVersion"] = 2
    json["progress"] = try JSONSerialization.jsonObject(with: Data(progress.utf8))
    let b = try Backup.decode(try JSONSerialization.data(withJSONObject: json))
    let book = try #require(b.progress[pid])
    #expect(book.entries["tt1"]?.position == 600)
    #expect(nums(book.entries["tt2"]) == [0, 0] && book.entries["tt2"]?.remoteFraction == 1)
    #expect(book.entries["tt3"] == nil)
    #expect(throws: Never.self) { _ = try b.encoded() }
}

// MARK: Number literals JSONDecoder cannot hold

/// `1e400` does not fit a Double. JSONDecoder refuses that value (the entry is dropped) or reads it as infinity
/// (repaired to 0); either way the other entries of the book stay.
@Test func hugeNumberLiteralCostsAtMostItsEntry() throws {
    let json = #"""
    {"schemaVersion":1,"entries":{
     "tt1":{"id":"tt1","item":{"id":"tt1","type":"movie","name":"Gut"},"position":600,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false},
     "tt8":{"id":"tt8","item":{"id":"tt8","type":"movie","name":"Riesig"},"position":1e400,"duration":2400,"updated":"2027-01-15T08:00:00Z","finished":false}
    }}
    """#
    let b = try isoDecoder().decode(ProgressBook.self, from: Data(json.utf8))
    #expect(b.entries["tt1"]?.position == 600)
    if let huge = b.entries["tt8"] { #expect(nums(huge) == [0, 2400]) }
    let file = #"{"entries":{"good":{"position":600,"duration":2400,"updated":820000000,"finished":false},"huge":{"position":600,"duration":1e400,"updated":820000000,"finished":false}}}"#
    let f = try JSONDecoder().decode(FileProgressBook.self, from: Data(file.utf8))
    #expect(f.entries["good"]?.position == 600)
    if let huge = f.entries["huge"] { #expect(huge.duration == 0) }
}

// MARK: FileProgressBook

@Test(arguments: nonFinite + ["-1", "-0.001"])
func fileProgressReportWithBadPositionIsIgnored(badName: String) {
    let bad = number(badName)
    var b = goodFileBook()
    let before = b.entries[fileKey]
    b.record(fileKey, position: bad, duration: 2400, now: t0.addingTimeInterval(60))
    b.record("torbox:1:2", position: bad, duration: 2400, now: t0)
    #expect(b.entries[fileKey] == before && b.entries["torbox:1:2"] == nil)
}

@Test(arguments: nonFinite + ["0", "-0.0", "-1", "-2400"])
func fileProgressReportWithBadDurationIsIgnored(badName: String) {
    let bad = number(badName)
    var b = goodFileBook()
    let before = b.entries[fileKey]
    b.record(fileKey, position: 900, duration: bad, now: t0.addingTimeInterval(60))
    b.record("torbox:1:2", position: 900, duration: bad, now: t0)
    #expect(b.entries[fileKey] == before && b.entries["torbox:1:2"] == nil)
}

@Test(arguments: [2400.001, 2401, 1e9, Double.greatestFiniteMagnitude])
func fileProgressReportBeyondTheEndCountsAsTheEnd(position: Double) throws {
    var b = FileProgressBook()
    b.record(fileKey, position: position, duration: 2400, now: t0)
    let e = try #require(b.entries[fileKey])
    #expect(e.finished && e.position == 0 && e.duration == 2400 && b.isWatched(fileKey))
}

@Test func fileProgressReportWithBadDateGetsAUsableDate() throws {
    var b = FileProgressBook()
    b.record(fileKey, position: 600, duration: 2400, now: Date(timeIntervalSinceReferenceDate: .nan))
    #expect(b.entries[fileKey]?.updated == .distantPast)
    #expect(throws: Never.self) { _ = try JSONEncoder().encode(b) }
}

@Test(arguments: badPairs)
func fileBadEntryInMemoryGivesUsableNumbers(positionName: String, durationName: String) throws {
    let position = number(positionName), duration = number(durationName)
    var b = FileProgressBook()
    b.entries[fileKey] = FileProgressBook.Entry(position: position, duration: duration,
                                                updated: Date(timeIntervalSinceReferenceDate: .nan), finished: false)
    if let f = b.fraction(for: fileKey) { #expect(f.isFinite && (0...1).contains(f)) }
    if let p = b.resumePosition(for: fileKey) {
        #expect(p.isFinite && p >= 0)
        if duration.isFinite && duration > 0 { #expect(p <= duration) }
    }
    let back = try JSONDecoder().decode(FileProgressBook.self, from: try JSONEncoder().encode(b))
    let e = try #require(back.entries[fileKey])
    #expect(e == b.entries[fileKey]?.normalized())
    #expect(e.position.isFinite && e.duration.isFinite && e.updated == .distantPast)
}

@Test func filePositionBeyondTheEndInMemoryResumesAtTheEnd() {
    var b = FileProgressBook()
    b.entries[fileKey] = FileProgressBook.Entry(position: 5000, duration: 2400, updated: t0, finished: false)
    #expect(b.resumePosition(for: fileKey) == 2400 && b.fraction(for: fileKey) == 1)
}

@Test func storedFileBlockWithBadEntriesKeepsTheGoodOnes() throws {
    // As PlayerMemory stores it: default JSONEncoder, dates as numbers.
    let json = #"""
    {"entries":{
     "good":{"position":600,"duration":2400,"updated":820000000,"finished":false},
     "neg":{"position":-50,"duration":2400,"updated":820000000,"finished":false},
     "negdur":{"position":700,"duration":-10,"updated":820000000,"finished":false},
     "over":{"position":5000,"duration":2400,"updated":820000000,"finished":false},
     "seen":{"position":9000,"duration":2400,"updated":820000000,"finished":true},
     "date":{"position":600,"duration":2400,"updated":1e300,"finished":false},
     "type":{"position":600,"duration":"lang","updated":820000000,"finished":false}
    }}
    """#
    let (b, report) = try JSONDecoder().decodeReporting(FileProgressBook.self, from: Data(json.utf8))
    #expect(b.entries["good"]?.position == 600 && b.entries["good"]?.duration == 2400)
    #expect(b.resumePosition(for: "good") == 600 && b.fraction(for: "good") == 0.25)
    #expect(nums(b.entries["neg"]) == [0, 2400])
    #expect(nums(b.entries["negdur"]) == [700, 0])
    #expect(nums(b.entries["over"]) == [2400, 2400] && b.entries["over"]?.finished == false)
    #expect(nums(b.entries["seen"]) == [2400, 2400] && b.entries["seen"]?.finished == true)
    #expect(b.entries["date"]?.updated == .distantFuture)
    #expect(b.entries["type"] == nil && report.ignored.contains(where: { $0.contains("type") }))
    let again = try JSONDecoder().decode(FileProgressBook.self, from: try JSONEncoder().encode(b))
    #expect(again == b)
}
