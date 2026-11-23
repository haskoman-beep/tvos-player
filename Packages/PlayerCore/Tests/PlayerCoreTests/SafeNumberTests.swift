import Foundation
import Testing
@testable import PlayerCore

@Test func safeNumberRejectsNonFinite() {
    #expect(SafeNumber.int64(.nan) == nil)
    #expect(SafeNumber.int64(.infinity) == nil)
    #expect(SafeNumber.int64(-.infinity) == nil)
    #expect(SafeNumber.int(.nan) == nil)
    #expect(SafeNumber.int(.infinity) == nil)
    #expect(SafeNumber.int(-.infinity) == nil)
}

@Test func safeNumberRejectsOutOfRange() {
    // 2^63 ist als Double exakt darstellbar, liegt aber eins über Int64.max.
    #expect(SafeNumber.int64(9_223_372_036_854_775_808.0) == nil)
    #expect(SafeNumber.int64(-9_223_372_036_854_777_856.0) == nil)   // nächster Double unter Int64.min
    #expect(SafeNumber.int64(1e300) == nil)
    #expect(SafeNumber.int64(-1e300) == nil)
    #expect(SafeNumber.int(9_223_372_036_854_775_808.0) == nil)
    #expect(SafeNumber.int(1e300) == nil)
}

@Test func safeNumberConvertsInRangeLikeInit() {
    #expect(SafeNumber.int64(0) == 0)
    #expect(SafeNumber.int64(45.2e9) == 45_200_000_000)
    #expect(SafeNumber.int64(12.9) == 12)          // schneidet ab wie Int64(_:)
    #expect(SafeNumber.int64(-12.9) == -12)
    #expect(SafeNumber.int64(-9_223_372_036_854_775_808.0) == Int64.min)
    #expect(SafeNumber.int64(9_223_372_036_854_774_784.0) == 9_223_372_036_854_774_784)   // größter Double unter 2^63
    #expect(SafeNumber.int(83.7) == 83)
    #expect(SafeNumber.int(-0.5) == 0)
}

@Test func introDBDropsSegmentsBeyondOneDay() {
    // Endliche, aber unsinnig große Zeiten (SEC-10): fielen bisher durch die Längenprüfung und brachen die Logzeile ab.
    let json = """
    {"intro": {"start_sec": 1e300, "end_sec": 1e300},
     "recap": {"start_sec": 9223372036854774784, "end_sec": 9223372036854775808},
     "outro": {"start_sec": 86000, "end_sec": 86401},
     "post_credits": {"start_sec": 86300, "end_sec": 86400}}
    """
    let list = IntroDBClient.parse(Data(json.utf8))
    #expect(list.map(\.kind) == [.postCredits])
}
