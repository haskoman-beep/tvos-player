import Foundation
import Testing
@testable import PlayerCore

// Wave X0: debug probe on pause (start rule, content label, frame verdict, log lines).

@Test func xrayProbeStartsOnlyOnARealPause() {
    let ok = { (enabled: Bool, was: Bool, now: Bool, loading: Bool, dur: Double, failed: Bool, blocked: Bool) in
        XRayProbe.shouldStart(enabled: enabled, wasPlaying: was, playing: now, loading: loading, ended: false,
                              sceneActive: true, duration: dur, failed: failed, blocked: blocked)
    }
    #expect(ok(true, true, false, false, 3600, false, false))
    // Switch off: never.
    #expect(!ok(false, true, false, false, 3600, false, false))
    // Not a transition (paused at load, resume).
    #expect(!ok(true, false, false, false, 3600, false, false))
    #expect(!ok(true, false, true, false, 3600, false, false))
    // Loading/buffering, no duration yet, engine error, panel/scrub/leave.
    #expect(!ok(true, true, false, true, 3600, false, false))
    #expect(!ok(true, true, false, false, 0, false, false))
    #expect(!ok(true, true, false, false, 3600, true, false))
    #expect(!ok(true, true, false, false, 3600, false, true))
    // End of file (autoplay follows) and an inactive scene (TV button) are no pause.
    #expect(!XRayProbe.shouldStart(enabled: true, wasPlaying: true, playing: false, loading: false, ended: true,
                                   sceneActive: true, duration: 3600, failed: false, blocked: false))
    #expect(!XRayProbe.shouldStart(enabled: true, wasPlaying: true, playing: false, loading: false, ended: false,
                                   sceneActive: false, duration: 3600, failed: false, blocked: false))
}

@Test func xrayProbeContentLabels() {
    #expect(XRayProbe.contentLabel(format: "sdr", dvProfile: nil, convertedToP81: false) == "SDR")
    #expect(XRayProbe.contentLabel(format: "hdr10", dvProfile: nil, convertedToP81: false) == "HDR10")
    #expect(XRayProbe.contentLabel(format: "hdr10Plus", dvProfile: nil, convertedToP81: false) == "HDR10+")
    #expect(XRayProbe.contentLabel(format: "hlg", dvProfile: nil, convertedToP81: false) == "HLG")
    #expect(XRayProbe.contentLabel(format: "dolbyVision", dvProfile: 5, convertedToP81: false) == "DV P5")
    #expect(XRayProbe.contentLabel(format: "dolbyVision", dvProfile: 8, convertedToP81: false) == "DV P8")
    #expect(XRayProbe.contentLabel(format: "dolbyVision", dvProfile: 7, convertedToP81: true) == "DV P7→8.1")
    #expect(XRayProbe.contentLabel(format: "dolbyVision", dvProfile: 7, convertedToP81: false) == "DV P7")
    #expect(XRayProbe.contentLabel(format: "dolbyVision", dvProfile: nil, convertedToP81: false) == "DV ?")
    #expect(XRayProbe.contentLabel(format: nil, dvProfile: nil, convertedToP81: false) == "?")
    #expect(XRayProbe.isProfile5(dvProfile: 5))
    #expect(XRayProbe.isProfile5(dvProfile: 10))
    #expect(!XRayProbe.isProfile5(dvProfile: 8))
    #expect(!XRayProbe.isProfile5(dvProfile: nil))
}

@Test func xrayProbeFrameVerdict() {
    #expect(XRayProbe.verdict(requested: 100, actual: 100.04, refined: true) == .atTarget)
    #expect(XRayProbe.verdict(requested: 100, actual: 99.95, refined: true) == .atTarget)
    #expect(XRayProbe.verdict(requested: 100, actual: 98, refined: true) == .offTarget(seconds: -2))
    #expect(XRayProbe.verdict(requested: 100, actual: 100, refined: false) == .unrefined(seconds: 0))
    #expect(XRayProbe.verdictText(.atTarget) == "am Ziel")
    #expect(XRayProbe.verdictText(.offTarget(seconds: -2)) == "daneben -2.00 s")
    #expect(XRayProbe.verdictText(.unrefined(seconds: 0.5)) == "nicht verfeinert +0.50 s")
}

@Test func xrayProbeLogLines() {
    #expect(XRayProbe.startLine(content: "DV P5", at: 12.346, stills: true, drawsInView: false, reshapingBuiltIn: true)
            == "Pause bei 12.35 s · DV P5 · Standbilder ja · Vorschau nur im View nein · P5-Umformung eingebaut")
    #expect(XRayProbe.frameLine(ms: 312, width: 1920, height: 800, verdict: .atTarget, content: "HDR10")
            == "Bild 1920×800 in 312 ms · am Ziel · HDR10")
    #expect(XRayProbe.noFrameLine(ms: 5, content: "DV P5", reason: "keine Standbilder")
            == "kein Bild nach 5 ms · DV P5 · keine Standbilder")
    #expect(XRayProbe.visionLine(ms: 80, faces: 1, frameWidth: 1920) == "Vision 80 ms · 1 Gesicht · Breite 1920")
    #expect(XRayProbe.visionLine(ms: 80, faces: 3, frameWidth: 1920) == "Vision 80 ms · 3 Gesichter · Breite 1920")
    let f = XRayProbe.Face(width: 120, height: 130, confidence: 0.987, yaw: -31.6, roll: 4.2, quality: 0.41, landmarks: true)
    #expect(XRayProbe.faceLine(index: 0, f)
            == "Gesicht 1: 120×130 px · Konfidenz 0.99 · Gier -32° · Roll 4° · Qualität 0.41 · Landmarken ja")
    let bare = XRayProbe.Face(width: 40, height: 40, confidence: 0.5)
    #expect(XRayProbe.faceLine(index: 2, bare) == "Gesicht 3: 40×40 px · Konfidenz 0.50 · Landmarken nein")
    #expect(XRayProbe.totalLine(ms: 900, outcome: "2 Gesichter") == "fertig nach 900 ms · 2 Gesichter")
}

@Test func xrayProbeLogsLargestFacesFirstAndCaps() {
    let faces = (1...12).map { XRayProbe.Face(width: $0 * 10, height: $0 * 10, confidence: 1) }
    let logged = XRayProbe.facesForLog(faces)
    #expect(logged.count == XRayProbe.maxLoggedFaces)
    #expect(logged.first?.width == 120)
    #expect(logged.last?.width == 50)
}

@Test func xrayHeldPictureLineOnlyForReshapedHolds() {
    #expect(XRayProbe.heldPictureLine(engineLine:
        "[AetherEngine] held picture: up after 412ms (Dolby Vision reshaped, 1920x1080, hdr=false)")
            == "P5 gehaltenes Bild per CPU (412 ms)")
    #expect(XRayProbe.heldPictureLine(engineLine:
        "[AetherEngine] held picture: up after 20ms (native output, 3840x2160, hdr=true)") == nil)
    #expect(XRayProbe.heldPictureLine(engineLine: "[AetherEngine] held picture: no frame from the outgoing picture") == nil)
    #expect(XRayProbe.heldPictureLine(engineLine: "held picture: up after ms (Dolby Vision reshaped)") == nil)
}

@Test func xraySourceKeyDropsQueryAndCredentials() throws {
    let a = try #require(URL(string: "https://user:pw@cdn.example.com:8443/d/ABC/film.mkv?token=1&exp=2#x"))
    #expect(XRayProbe.sourceKey(a) == "https://cdn.example.com:8443/d/ABC/film.mkv")
    let b = try #require(URL(string: "https://cdn.example.com:8443/d/ABC/film.mkv?token=9"))
    #expect(XRayProbe.sourceKey(a) == XRayProbe.sourceKey(b))
}

@Test func recentKeySetKeepsNewestWithinCapacity() throws {
    var set = RecentKeySet(capacity: 3)
    let newA = set.insert("a"), newB = set.insert("b")
    let againA = set.insert("a")   // known: moved to the front
    #expect(newA && newB && !againA)
    #expect(set.keys == ["a", "b"])
    set.insert("c"); set.insert("d")
    #expect(set.keys == ["d", "c", "a"])
    #expect(!set.contains("b"))
    let data = try JSONEncoder().encode(set)
    #expect(try JSONDecoder().decode(RecentKeySet.self, from: data) == set)
    #expect(RecentKeySet(keys: ["1", "2", "3", "4"], capacity: 2).keys == ["1", "2"])
}

@Test func xrayForwardsHeldPictureAndLadderLinesOnly() {
    #expect(XRayProbe.forwardedLine(engineLine:
        "[AetherEngine] held picture: up after 90ms (Dolby Vision reshaped, 1920x1080, hdr=false)")
            == "P5 gehaltenes Bild per CPU (90 ms)")
    #expect(XRayProbe.forwardedLine(engineLine: "[HLSVideoEngine] [StillLadder] rung idx=12 t=480.0s")
            == "Leiter: [StillLadder] rung idx=12 t=480.0s")
    #expect(XRayProbe.forwardedLine(engineLine: "[HLSVideoEngine] segment 4 ready") == nil)
}
