import Testing
@testable import PlayerCore

// User decision 26.11.: back to the plan (Task 5.4): the up-next countdown runs 20 s.
@Test func upNextCountdownRunsTwentySeconds() {
    #expect(UpNextCountdown.seconds == 20)
    #expect(UpNextCountdown.line(seconds: UpNextCountdown.seconds) == "Nächste Folge in 20 s")
}
