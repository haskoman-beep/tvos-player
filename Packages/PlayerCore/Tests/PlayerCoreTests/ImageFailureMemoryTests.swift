import Foundation
import Testing
@testable import PlayerCore

@Test func imageFailureOnlyGoneAnswersBlockFiveMinutes() {
    #expect(ImageFailure.classify(status: 200) == nil)
    #expect(ImageFailure.classify(status: 404) == .gone)
    #expect(ImageFailure.classify(status: 410) == .gone)
    #expect(ImageFailure.classify(status: 503) == .transient)
    #expect(ImageFailure.classify(status: 403) == .transient)
    #expect(ImageFailure.classify(error: URLError(.notConnectedToInternet)) == .transient)
    #expect(ImageFailure.classify(error: URLError(.timedOut)) == .transient)
    #expect(ImageFailure.classify(error: URLError(.networkConnectionLost)) == .transient)
    #expect(ImageFailure.classify(error: URLError(.cancelled)) == nil)
    #expect(ImageFailure.classify(error: CancellationError()) == nil)
}

@Test func imageFailureMemoryDurations() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    #expect(ImageFailure.transient.blocks(since: t0, now: t0.addingTimeInterval(19)))
    #expect(!ImageFailure.transient.blocks(since: t0, now: t0.addingTimeInterval(20)))
    #expect(ImageFailure.gone.blocks(since: t0, now: t0.addingTimeInterval(299)))
    #expect(!ImageFailure.gone.blocks(since: t0, now: t0.addingTimeInterval(300)))
    #expect(ImageFailure.combine(nil, .gone) == .gone)
    #expect(ImageFailure.combine(.gone, .transient) == .transient)
    #expect(ImageFailure.combine(.transient, .gone) == .transient)
}
