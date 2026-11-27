import Foundation
import Testing
@testable import PlayerCore

// Phase 0a.1: which copy of a blob is current depends on sequence numbers (sidecar `<name>.seq`, record
// `seq.<key>`), not on the clock. Older states must never win over newer ones when the device clock jumps.

private typealias TS = TieredBlobStorage

/// Never goes to UserDefaults (file-only prefix), so only the folders decide.
private let fileOnly = TieredBlobStorage.fileOnlyPrefix + "seq-test.json"
/// Small enough for UserDefaults.
private let small = "progress-seq.json"
private let yearAgo = Date(timeIntervalSinceNow: -365 * 86_400)
private let inAYear = Date(timeIntervalSinceNow: 365 * 86_400)

private func d(_ s: String) -> Data { Data(s.utf8) }

/// [Application Support, Caches] as in the app.
private func folders(_ n: Int = 2) -> [FileBlobStorage] { (0..<n).map { _ in FileBlobStorage(directory: tempDir()) } }

private func setDate(_ dir: FileBlobStorage, _ name: String, _ date: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dir.url(name).path)
}

/// Phase 0a date revision as stored under `rev.<key>`.
private func revision(_ date: Date) -> Data {
    withUnsafeBytes(of: date.timeIntervalSinceReferenceDate.bitPattern) { Data($0) }
}

private func stamps(_ list: [(UInt64, Data)]) -> Data {
    TS.encodeStamps(list.map { TS.Stamp(seq: $0.0, print: TS.fingerprint($0.1)) })
}

private func sidecarSeq(_ dir: FileBlobStorage, _ name: String) -> UInt64? {
    TS.decodeStamps(dir.read(TS.sidecarName(name)))?.first?.seq
}

/// Every entry of the store, as the next app start would find it.
private func everything(_ kv: MemoryKeyValueBlobs) -> [String: Data] {
    var out: [String: Data] = [:]
    for k in kv.keys(withPrefix: "") { out[k] = kv.data(forKey: k) }
    return out
}

/// Folder that cannot be created (a file is in the way), like tvOS code 513.
private func unwritable() -> FileBlobStorage {
    let f = tempDir().appendingPathComponent("datei")
    try? Data("x".utf8).write(to: f)
    return FileBlobStorage(directory: f.appendingPathComponent("unter"))
}

@Test func seqStampsRoundTrip() {
    let list = [TS.Stamp(seq: 7, print: TS.fingerprint(d("x"))), TS.Stamp(seq: .max, print: TS.fingerprint(Data()))]
    #expect(TS.decodeStamps(TS.encodeStamps(list)) == list)
    #expect(TS.encodeStamps(list).count == 49)
    #expect(TS.decodeStamps(Data([1, 2, 3])) == nil && TS.decodeStamps(nil) == nil)
    #expect(TS.fingerprint(d("a")).hash == 0xaf63_dc4c_8601_ec8c)   // FNV-1a 64 test vector
    #expect(TS.fingerprint(d("abc")).count == 3)
    #expect(TS.next(.max) == .max)
}

// MARK: Clock changes

@Test func seqClockBackwardsBetweenWritesAcrossFolders() throws {
    let dirs = folders()
    let s = TS(defaults: MemoryKeyValueBlobs(), directories: dirs)
    try s.write(fileOnly, d("A"))
    try setDate(dirs[0], fileOnly, inAYear)        // A written while the clock ran a year ahead
    try s.write(fileOnly, d("B"))
    try setDate(dirs[1], fileOnly, yearAgo)        // clock set back: Caches' copy of B is dated far behind
    try setDate(dirs[0], fileOnly, inAYear)
    #expect(s.read(fileOnly) == d("B"))
    #expect(dirs.allSatisfy { sidecarSeq($0, fileOnly) == 2 })
}

@Test func seqStaleFolderWithLaterDateLoses() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    try TS(defaults: kv, directories: dirs).write(fileOnly, d("A"))
    // Application Support refuses writes (code 513) for a while: only Caches gets B.
    let cachesOnly = TS(defaults: kv, directories: dirs, writeDirectories: [dirs[1]])
    try cachesOnly.write(fileOnly, d("B"))
    try setDate(dirs[0], fileOnly, inAYear)
    try setDate(dirs[1], fileOnly, yearAgo)
    #expect(dirs[0].read(fileOnly) == d("A"))
    #expect(cachesOnly.read(fileOnly) == d("B"))
    // Next start with both folders writable: the next write goes above both.
    let both = TS(defaults: kv, directories: dirs)
    #expect(both.read(fileOnly) == d("B"))
    try both.write(fileOnly, d("C"))
    #expect(sidecarSeq(dirs[0], fileOnly) == 3 && sidecarSeq(dirs[1], fileOnly) == 3)
    #expect(dirs.allSatisfy { $0.read(fileOnly) == d("C") } && both.read(fileOnly) == d("C"))
}

@Test func seqClockBackwardsDefaultsCopyVersusFiles() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    let before = everything(kv)
    try s.write(small, d("B"))
    for f in dirs { try setDate(f, small, yearAgo) }
    // Next start: the UserDefaults write of B was lost; the copy A carries a revision a year ahead.
    var lost = before
    lost["rev.blob." + small] = revision(inAYear)
    let next = TS(defaults: MemoryKeyValueBlobs(lost), directories: dirs)
    #expect(next.read(small) == d("B"))
    #expect(next.overtakenDefaults() == [small])

    // The other way round: only UserDefaults took B (no folder writable); the files hold A dated a year ahead.
    let kv2 = MemoryKeyValueBlobs()
    let dirs2 = folders()
    try TS(defaults: kv2, directories: dirs2).write(small, d("A"))
    try TS(defaults: kv2, directories: dirs2, writeDirectories: [unwritable()]).write(small, d("B"))
    for f in dirs2 { try setDate(f, small, inAYear) }
    kv2.set(revision(yearAgo), forKey: "rev.blob." + small)
    #expect(TS(defaults: kv2, directories: dirs2).read(small) == d("B"))
}

@Test func seqClockForwardsThenCorrected() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    // A was written while the clock ran a year ahead: files and revision carry that date.
    for f in dirs { try setDate(f, small, inAYear) }
    kv.set(revision(inAYear), forKey: "rev.blob." + small)
    let before = everything(kv)
    try s.write(small, d("B"))                     // clock corrected: B's dates lie before A's
    #expect(s.read(small) == d("B"))
    // B's UserDefaults write lost: the old rule (revision ≥ newest file date) would pick A.
    #expect(TS(defaults: MemoryKeyValueBlobs(before), directories: dirs).read(small) == d("B"))
}

@Test func seqDroppedDefaultsWriteWithLaterDatedStaleCopy() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    kv.dropsWrites = true
    try s.write(small, d("B"))                     // cfprefsd refuses: no record, no copy of B
    kv.dropsWrites = false
    // The next start finds A again, with a revision a year ahead; the files of B are dated a year back.
    kv.set(d("A"), forKey: "blob." + small)
    kv.set(revision(inAYear), forKey: "rev.blob." + small)
    for f in dirs { try setDate(f, small, yearAgo) }
    let next = TS(defaults: kv, directories: dirs)
    #expect(next.read(small) == d("B"))
    next.migrate()
    #expect(next.read(small) == d("B"))
}

// MARK: Interrupted writes

@Test func seqWriteInterruptedAfterSidecar() throws {
    let dirs = folders()
    let s = TS(defaults: MemoryKeyValueBlobs(), directories: dirs)
    try s.write(fileOnly, d("A"))
    // A write of B stopped after Application Support's sidecar: the payload there is still A (dated ahead).
    try dirs[0].write(TS.sidecarName(fileOnly), stamps([(2, d("B")), (1, d("A"))]))
    try setDate(dirs[0], fileOnly, inAYear)
    #expect(s.read(fileOnly) == d("A"))
    try s.write(fileOnly, d("C"))
    #expect(sidecarSeq(dirs[0], fileOnly) == 3 && s.read(fileOnly) == d("C"))
}

@Test func seqPayloadWithoutMatchingSidecarIsNewer() throws {
    // A payload that lies next to a sidecar not made for it (an older build wrote it, or the sidecar write was lost)
    // is newer than that sidecar says, whatever its date.
    let dirs = folders()
    let s = TS(defaults: MemoryKeyValueBlobs(), directories: dirs)
    try s.write(fileOnly, d("A"))
    try dirs[1].write(fileOnly, d("B"))
    try setDate(dirs[1], fileOnly, yearAgo)
    try setDate(dirs[0], fileOnly, inAYear)
    #expect(s.read(fileOnly) == d("B"))
    try s.write(fileOnly, d("C"))
    #expect(sidecarSeq(dirs[1], fileOnly) == 3)
}

@Test func seqDefaultsRecordWrittenButCopyNot() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    // A write of B (no folder took it) stopped between record and copy: the copy is still A and matches the
    // record's second stamp.
    kv.set(stamps([(2, d("B")), (1, d("A"))]), forKey: "seq.blob." + small)
    #expect(s.read(small) == d("A"))
    // The folders took B before (sidecar, then payload): B, even with A's revision a year ahead.
    for f in dirs {
        try f.write(TS.sidecarName(small), stamps([(2, d("B")), (1, d("A"))]))
        try f.write(small, d("B"))
        try setDate(f, small, yearAgo)
    }
    kv.set(revision(inAYear), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("B"))
    #expect(s.overtakenDefaults() == [small])
}

@Test func seqSidecarWithoutPayload() throws {
    let dirs = folders()
    let s = TS(defaults: MemoryKeyValueBlobs(), directories: dirs)
    try s.write(fileOnly, d("A"))
    try FileManager.default.removeItem(at: dirs[1].url(fileOnly))
    #expect(s.read(fileOnly) == d("A"))
    try FileManager.default.removeItem(at: dirs[0].url(fileOnly))
    #expect(s.read(fileOnly) == nil)
    // The sidecars still count for the next number.
    try s.write(fileOnly, d("B"))
    #expect(sidecarSeq(dirs[0], fileOnly) == 2 && s.read(fileOnly) == d("B"))
}

@Test func seqCachesPurgedPartly() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    try TS(defaults: kv, directories: dirs).write(fileOnly, d("A"))
    let cachesOnly = TS(defaults: kv, directories: dirs, writeDirectories: [dirs[1]])
    try cachesOnly.write(fileOnly, d("B"))
    try setDate(dirs[0], fileOnly, inAYear)
    // tvOS removes only the sidecar in Caches: the record in UserDefaults still vouches for B.
    dirs[1].remove(TS.sidecarName(fileOnly))
    #expect(cachesOnly.read(fileOnly) == d("B"))
    // Payload gone as well: only Application Support's older state is left (nothing else holds B).
    dirs[1].remove(fileOnly)
    #expect(cachesOnly.read(fileOnly) == d("A"))

    // A small blob survives the purge through its UserDefaults copy.
    try TS(defaults: kv, directories: dirs).write(small, d("A"))
    try cachesOnly.write(small, d("B"))
    try setDate(dirs[0], small, inAYear)
    dirs[1].remove(small)
    dirs[1].remove(TS.sidecarName(small))
    #expect(cachesOnly.read(small) == d("B"))
}

// MARK: Contradictory states

@Test func seqContradictoryFoldersSameNumber() throws {
    let dirs = folders()
    let s = TS(defaults: MemoryKeyValueBlobs(), directories: dirs)
    // Both verified with number 5 but different bytes: the folder order decides, not the date.
    try dirs[0].write(TS.sidecarName(fileOnly), stamps([(5, d("X"))]))
    try dirs[0].write(fileOnly, d("X"))
    try dirs[1].write(TS.sidecarName(fileOnly), stamps([(5, d("Y"))]))
    try dirs[1].write(fileOnly, d("Y"))
    try setDate(dirs[1], fileOnly, inAYear)
    #expect(s.read(fileOnly) == d("X"))
    // Both unstamped writes over number 4 (rank 5 each): the later date decides, as before Phase 0a.1.
    for (dir, v) in [(dirs[0], "P"), (dirs[1], "Q")] {
        try dir.write(TS.sidecarName(fileOnly), stamps([(4, d("Z"))]))
        try dir.write(fileOnly, d(v))
    }
    try setDate(dirs[0], fileOnly, inAYear)
    try setDate(dirs[1], fileOnly, yearAgo)
    #expect(s.read(fileOnly) == d("P"))
    try setDate(dirs[0], fileOnly, yearAgo)
    try setDate(dirs[1], fileOnly, inAYear)
    #expect(s.read(fileOnly) == d("Q"))
    // The next write goes above all of them.
    try s.write(fileOnly, d("R"))
    #expect(sidecarSeq(dirs[0], fileOnly) == 6 && s.read(fileOnly) == d("R"))
}

@Test func seqDefaultsRecordNotMatchingCopy() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    // An older build (downgrade) wrote B into UserDefaults only, with its date revision; the record is untouched.
    kv.set(d("B"), forKey: "blob." + small)
    kv.set(revision(yearAgo), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("B"))
    // An unreadable record proves nothing: the copy is ranked by the stamps of equal bytes in the folders.
    kv.set(d("A"), forKey: "blob." + small)
    kv.set(d("kaputt"), forKey: "seq.blob." + small)
    #expect(s.read(small) == d("A"))
    // A copy without record and without a matching stamp is a legacy copy (rank 0): the stamped files win.
    kv.set(d("C"), forKey: "blob." + small)
    kv.set(revision(inAYear), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("A"))
}

@Test func seqDowngradeThenUpgrade() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    // An older build writes files and UserDefaults without sidecar or record, its clock a year behind.
    for f in dirs {
        try f.write(small, d("B"))
        try setDate(f, small, yearAgo)
    }
    kv.set(d("B"), forKey: "blob." + small)
    kv.set(revision(yearAgo), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("B"))
    #expect(s.overtakenDefaults().isEmpty)
    // Upgrade again: the next write goes above the older build's writes.
    try s.write(small, d("C"))
    #expect(dirs.allSatisfy { sidecarSeq($0, small) == 3 })
    #expect(s.read(small) == d("C"))
}

// MARK: Legacy state and migration

@Test func seqLegacyStateDecidesByDatesAsBefore() throws {
    let dirs = folders()
    try dirs[0].write(small, d("old"))
    try setDate(dirs[0], small, yearAgo)
    try dirs[1].write(small, d("new"))
    let kv = MemoryKeyValueBlobs([TS.adoptedKey: Data([1]), "blob." + small: d("copy")])
    let s = TS(defaults: kv, directories: dirs)
    #expect(s.read(small) == d("new"))             // entry without revision gives way, newest file wins
    kv.set(revision(inAYear), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("copy"))            // revision not older than the newest file
    kv.set(revision(yearAgo.addingTimeInterval(-60)), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("new"))
    #expect(s.migrate().moved.isEmpty)
    // Nothing is rewritten at start: still no stamp anywhere.
    #expect(kv.keys(withPrefix: TS.sequencePrefix).isEmpty)
    #expect(dirs.allSatisfy { $0.read(TS.sidecarName(small)) == nil })
}

@Test func seqAdoptionIsRepeatableAndNeedsNoClock() throws {
    let dirs = folders()
    try dirs[0].write(small, d("old file"))
    try setDate(dirs[0], small, inAYear)           // even a file dated a year ahead
    let kv = MemoryKeyValueBlobs(["blob." + small: d("entry")])
    let s = TS(defaults: kv, directories: dirs)
    s.migrate()
    #expect(s.read(small) == d("entry"))
    #expect(TS.decodeStamps(kv.data(forKey: "seq.blob." + small)) == [TS.Stamp(seq: 1, print: TS.fingerprint(d("entry")))])
    // Its date revision is for older builds only: moving it behind the file changes nothing here.
    kv.set(revision(yearAgo), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("entry"))
    let after = everything(kv)
    s.migrate()                                    // runs twice
    #expect(everything(kv) == after)
    kv.remove(forKey: TS.adoptedKey)               // flag lost
    s.migrate()
    #expect(everything(kv) == after)
    #expect(s.read(small) == d("entry"))
}

@Test func seqAdoptionInterruptedHalfwayCompletesAtNextStart() throws {
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write("a.json", d("old a"))
    try dir.write("b.json", d("old b"))
    // The first run took over a.json (record written, stopped before its revision), not b.json, no flag.
    let kv = MemoryKeyValueBlobs(["blob.a.json": d("entry a"), "blob.b.json": d("entry b"),
                                  "seq.blob.a.json": stamps([(1, d("entry a"))])])
    let s = TS(defaults: kv, directories: [dir])
    #expect(s.read("a.json") == d("entry a"))      // decided by its record already
    #expect(s.read("b.json") == d("old b"))        // not taken over yet: the legacy rule
    s.migrate()
    #expect(s.read("a.json") == d("entry a") && s.read("b.json") == d("entry b"))
    #expect(TS.decodeStamps(kv.data(forKey: "seq.blob.a.json"))?.count == 1)
    #expect(kv.data(forKey: TS.adoptedKey) != nil)
}

@Test func seqAdoptionLeavesStampedNamesAlone() throws {
    // This build wrote B (stamped) into the folder; the entry without record or revision is not taken over.
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write(TS.sidecarName(small), stamps([(1, d("B"))]))
    try dir.write(small, d("B"))
    try setDate(dir, small, yearAgo)
    let kv = MemoryKeyValueBlobs(["blob." + small: d("A")])
    let s = TS(defaults: kv, directories: [dir])
    s.migrate()
    #expect(kv.data(forKey: "seq.blob." + small) == nil)
    #expect(s.read(small) == d("B"))
}

@Test func seqFirstWriteAfterUpdateStampsEverything() throws {
    let dirs = folders()
    // Legacy state; Application Support is not writable now and holds a file dated a year ahead.
    try dirs[0].write(small, d("legacy"))
    try setDate(dirs[0], small, inAYear)
    let kv = MemoryKeyValueBlobs(["blob." + small: d("legacy"), TS.adoptedKey: Data([1])])
    let s = TS(defaults: kv, directories: dirs, writeDirectories: [dirs[1]])
    try s.write(small, d("new"))
    #expect(sidecarSeq(dirs[1], small) == 1 && dirs[0].read(TS.sidecarName(small)) == nil)
    #expect(TS.decodeStamps(kv.data(forKey: "seq.blob." + small))?.first?.seq == 1)
    #expect(s.read(small) == d("new"))
    // Its UserDefaults write lost (old entry back, no record, revision ahead): the stamped file still wins.
    kv.set(d("legacy"), forKey: "blob." + small)
    kv.remove(forKey: "seq.blob." + small)
    kv.set(revision(inAYear), forKey: "rev.blob." + small)
    #expect(s.read(small) == d("new"))
}

// MARK: Housekeeping

@Test func seqRemoveCleansSidecarsAndRecords() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    try s.write(small, d("A"))
    try s.write(fileOnly, d("B"))
    s.remove(small)
    s.remove(fileOnly)
    #expect(kv.keys(withPrefix: "").isEmpty)
    for f in dirs { #expect(((try? FileManager.default.contentsOfDirectory(atPath: f.directory.path)) ?? []).isEmpty) }
    try s.write(small, d("C"))
    #expect(sidecarSeq(dirs[0], small) == 1 && s.read(small) == d("C"))
}

@Test func seqKeysAndSidecarsAreNoBlobs() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    let profile = UUID()
    let names = ["progress-\(profile.uuidString).json", "progress-\(profile.uuidString).json.bak",
                 TS.profileName, TS.profileName + ".1"]
    for n in names {
        try s.write(n, d("{}"))
        try s.write(n, d("{ }"))
    }
    #expect(Set(s.defaultsSizes().keys) == [names[0], TS.profileName])
    let m = s.migrate()
    #expect(m.moved.isEmpty && m.failed.isEmpty && Set(m.kept) == [names[0], TS.profileName])
    #expect(s.overtakenDefaults().isEmpty)
    #expect(kv.keys(withPrefix: TS.sequencePrefix).count == names.count)
    #expect(kv.keys(withPrefix: TS.sequencePrefix).allSatisfy { kv.data(forKey: $0)?.count == 25 || kv.data(forKey: $0)?.count == 49 })
    // Deleting the profile's blocks takes the sidecars and records along, and lists only the blocks.
    #expect(Set(ProfileBlocks.remove(profile: profile, from: s)) == [names[0], names[1]])
    for f in dirs { #expect(f.read(TS.sidecarName(names[0])) == nil && f.read(TS.sidecarName(names[1])) == nil) }
    #expect(kv.keys(withPrefix: TS.sequencePrefix).count == 2)
    #expect(s.read(TS.profileName) == d("{ }") && s.read(TS.profileName + ".1") == d("{ }"))
}

@Test func seqConcurrentWritesOfOneNameStayConsistent() throws {
    let dirs = folders()
    let kv = MemoryKeyValueBlobs()
    let s = TS(defaults: kv, directories: dirs)
    DispatchQueue.concurrentPerform(iterations: 40) { i in try? s.write(small, Data("v\(i)".utf8)) }
    let winner = try #require(s.read(small))
    #expect(dirs.allSatisfy { $0.read(small) == winner })
    #expect(kv.data(forKey: "blob." + small) == winner)
    #expect(dirs.allSatisfy { sidecarSeq($0, small) == 40 })
}
