import Foundation
import Testing
@testable import PlayerCore

private let sha40 = "e2930969f038b6b901b5c5f1da6598d5589355db"
private let sha41 = "0123456789abcdef0123456789abcdef01234567"

private func runsJSON(_ n: Int, _ sha: String) -> String {
    #"{"total_count":2,"workflow_runs":[{"id":9,"name":"build-ipa","head_branch":"main","head_sha":"\#(sha)","run_number":\#(n),"status":"completed","conclusion":"success","created_at":"2026-11-21T13:40:28Z"}]}"#
}

private func releaseJSON(_ n: Int, _ sha: String, asset: String = "Player.ipa") -> String {
    #"{"tag_name":"app-main","name":"Player Build \#(n)","draft":false,"prerelease":false,"body":"Build \#(n) · Commit \#(sha) · Branch main","assets":[{"name":"\#(asset)","size":1234,"browser_download_url":"https://github.com/haskoman-beep/tvos-player/releases/download/app-main/\#(asset)"}]}"#
}

private let appsJSON = #"""
{"code":200,"msg":"success","data":[
 {"ID":3,"bundle_identifier":"com.other.app","version":"1.0","udid":"U1","account":"user@example.com","ipa_path":"/data/3/app.ipa","enabled":true,"source":{"kind":"","url":""}},
 {"ID":10,"bundle_identifier":"de.haskoman.player","version":"0.4.0","udid":"U1","account":"user@example.com","ipa_path":"/data/10/app.ipa","enabled":true,"source":{"kind":"","url":"","filter":""},"password":"x"}
]}
"""#
private let devicesJSON = #"{"code":200,"msg":"success","data":[{"id":"dev-1","name":"Wohnzimmer","udid":"U1","device_class":"AppleTV","ip":"10.0.0.2"}]}"#

private func sse(_ json: String) -> String { "event: message\nid: X_0\ndata: \(json)\n\n" }

@Test func buildInfoFromInfoPlist() {
    let ci = AppBuildInfo(info: ["CFBundleShortVersionString": "0.4.0", "CFBundleVersion": "40", "PlayerBuildCommit": sha40.uppercased(), "PlayerBuildBranch": "main"])
    #expect(ci.build == 40 && ci.commit == sha40 && ci.buildLabel == "40 · main · e293096")
    let local = AppBuildInfo(info: ["CFBundleShortVersionString": "0.4.0", "CFBundleVersion": "1", "PlayerBuildCommit": "$(PLAYER_BUILD_COMMIT)"])
    #expect(local.commit.isEmpty && local.buildLabel == "1 (ohne CI)")
    #expect(AppBuildInfo(info: nil).build == nil)
}

@Test func parsesLatestRunAndRelease() throws {
    let run = try #require(GitHubBuilds.parseLatestRun(Data(runsJSON(40, sha40).utf8)))
    #expect(run.number == 40 && run.commit == sha40 && run.date != nil)
    #expect(GitHubBuilds.parseLatestRun(Data(#"{"total_count":0,"workflow_runs":[]}"#.utf8)) == nil)
    let rel = try #require(GitHubBuilds.parseRelease(Data(releaseJSON(40, sha40).utf8)))
    #expect(rel.number == 40 && rel.commit == sha40 && rel.size == 1234)
    #expect(rel.ipaURL.absoluteString == "https://github.com/haskoman-beep/tvos-player/releases/download/app-main/Player.ipa")
    #expect(GitHubBuilds.parseRelease(Data(releaseJSON(40, sha40, asset: "other.zip").utf8)) == nil)
    // Nur genau die Release-Adresse des Repos geht an atvloadly.
    let foreign = releaseJSON(40, sha40).replacingOccurrences(of: "github.com/haskoman-beep/", with: "github.com/someone-else/")
    #expect(GitHubBuilds.parseRelease(Data(foreign.utf8)) == nil)
    #expect(GitHubBuilds.ipaURL.absoluteString == "https://github.com/haskoman-beep/tvos-player/releases/download/app-main/Player.ipa")
    #expect(GitHubBuilds.latestRunURL.absoluteString.contains("branch=main&status=success&per_page=1"))
}

@Test func updateDecision() {
    let latest = CIBuild(number: 41, commit: sha41)
    let rel41 = ReleaseBuild(number: 41, commit: sha41, ipaURL: URL(string: "https://x/Player.ipa")!)
    let rel40 = ReleaseBuild(number: 40, commit: sha40, ipaURL: URL(string: "https://x/Player.ipa")!)
    let installed40 = AppBuildInfo(version: "0.4.0", build: 40, commit: sha40, branch: "main")
    #expect(UpdateState.decide(current: installed40, latest: latest, release: rel41) == .available(rel41, latest: latest))
    #expect(UpdateState.decide(current: AppBuildInfo(version: "", build: 41, commit: "0123456", branch: "main"), latest: latest, release: rel41) == .upToDate(latest))
    // Paket noch auf dem installierten Stand bzw. gar keins: nichts zu installieren.
    #expect(UpdateState.decide(current: installed40, latest: latest, release: rel40) == .notPublished(latest))
    #expect(UpdateState.decide(current: installed40, latest: latest, release: nil) == .notPublished(latest))
    // Lokaler Build ohne Commit: immer installierbar.
    let local = AppBuildInfo(version: "0.4.0", build: 1, commit: "", branch: "")
    #expect(UpdateState.decide(current: local, latest: latest, release: rel41) == .available(rel41, latest: latest))
    #expect(!UpdateState.sameCommit("", "") && !UpdateState.sameCommit("abc", "abcdef0"))
}

@Test func newerThanMainInstalled() {
    let latest = CIBuild(number: 41, commit: sha41)
    let rel41 = ReleaseBuild(number: 41, commit: sha41, ipaURL: GitHubBuilds.ipaURL)
    let rel40 = ReleaseBuild(number: 40, commit: sha40, ipaURL: GitHubBuilds.ipaURL)
    // Branch-Build 45 ist neuer als main: kein Angebot zum „Zurückinstallieren“.
    let branch45 = AppBuildInfo(version: "0.4.0", build: 45, commit: "abcdef0123456789", branch: "welle-a-d")
    #expect(UpdateState.decide(current: branch45, latest: latest, release: rel41) == .newerInstalled(main: 41))
    #expect(UpdateState.decide(current: branch45, latest: latest, release: nil) == .newerInstalled(main: 41))
    // Verglichen wird mit dem Paket, das installiert würde.
    let branch41 = AppBuildInfo(version: "0.4.0", build: 41, commit: "abcdef0123456789", branch: "welle-a-d")
    #expect(UpdateState.decide(current: branch41, latest: latest, release: rel40) == .newerInstalled(main: 40))
    // Älterer Branch-Build bekommt das main-Paket angeboten, lokaler Build ohne Commit auch.
    let branch39 = AppBuildInfo(version: "0.4.0", build: 39, commit: "abcdef0123456789", branch: "welle-a-d")
    #expect(UpdateState.decide(current: branch39, latest: latest, release: rel41) == .available(rel41, latest: latest))
    let local = AppBuildInfo(version: "0.4.0", build: 99, commit: "", branch: "")
    #expect(UpdateState.decide(current: local, latest: latest, release: rel41) == .available(rel41, latest: latest))
}

@Test func atvloadlyAddressNormalizing() {
    #expect(AtvloadlyAddress.normalize("pi-name.local")?.absoluteString == "http://pi-name.local:5533")
    #expect(AtvloadlyAddress.normalize(" http://10.0.0.5:5533/ ")?.absoluteString == "http://10.0.0.5:5533")
    #expect(AtvloadlyAddress.normalize("10.0.0.5:8080")?.absoluteString == "http://10.0.0.5:8080")
    #expect(AtvloadlyAddress.normalize("https://atv.example.org/sub/")?.absoluteString == "https://atv.example.org/sub")
    #expect(AtvloadlyAddress.normalize("") == nil && AtvloadlyAddress.normalize("ftp://x") == nil && AtvloadlyAddress.normalize("a b") == nil)
    let base = AtvloadlyAddress.normalize("pi-name.local")!
    #expect(base.appendingPathComponent("api/version").absoluteString == "http://pi-name.local:5533/api/version")
}

@Test func atvloadlyHomeNetworkCheck() {
    func home(_ s: String) -> Bool { AtvloadlyAddress.isHomeNetwork(AtvloadlyAddress.normalize(s)!) }
    // Heimnetz: .local, Name ohne Punkt, RFC 1918, link-local, ULA.
    for s in ["pi-name.local", "PI.Local.", "raspberrypi", "10.1.2.3", "172.16.0.9", "172.31.255.1", "192.168.0.2:8080",
              "169.254.10.20", "http://[fd12:3456::1]:5533", "[fe80::1]", "[FC00::2]"] {
        #expect(home(s), "\(s) sollte als Heimnetz gelten")
    }
    // Sonst nur Warnung (normalize lehnt nicht ab).
    for s in ["https://atv.example.org/sub", "8.8.8.8", "172.32.0.1", "11.0.0.1", "192.169.0.1", "[2001:db8::1]", "[::1]", "300.1.1.1", "12345"] {
        #expect(AtvloadlyAddress.normalize(s) != nil && !home(s), "\(s) sollte als nicht Heimnetz gelten")
    }
    #expect(AtvloadlyAddress.notHomeWarning == "Adresse ist nicht im Heimnetz")
}

@Test func bonjourWorkstationHosts() {
    #expect(AtvloadlyAddress.host(fromWorkstation: "raspberrypi [aa:bb:cc:dd:ee:ff]") == "raspberrypi.local")
    #expect(AtvloadlyAddress.host(fromWorkstation: "nas-2") == "nas-2.local")
    #expect(AtvloadlyAddress.host(fromWorkstation: "Mein Rechner [aa:bb]") == nil)
    let c = AtvloadlyAddress.candidates(workstations: ["box [aa:bb]", "raspberrypi [cc:dd]", "box [aa:bb]"]).map(\.absoluteString)
    #expect(c == ["http://box.local:5533", "http://raspberrypi.local:5533"])
}

@Test func atvloadlyEnvelopes() throws {
    #expect(try Atvloadly.parseVersion(Data(#"{"code":200,"msg":"success","data":{"commit":"e3737b7","version":"v0.8.5"}}"#.utf8)) == "v0.8.5")
    let apps = try Atvloadly.parseApps(Data(appsJSON.utf8))
    #expect(apps.count == 2 && apps[1].id == 10 && apps[1].bundleID == "de.haskoman.player" && apps[1].udid == "U1")
    #expect(try Atvloadly.parseApps(Data(#"{"code":200,"msg":"success","data":[]}"#.utf8)).isEmpty)
    #expect(try Atvloadly.parseDevices(Data(devicesJSON.utf8)) == [AtvloadlyDevice(id: "dev-1", name: "Wohnzimmer", udid: "U1")])
    #expect(throws: AppUpdateError.atvloadly("app is installing")) {
        try Atvloadly.parseSourceUpdate(Data(#"{"code":-1,"msg":"app is installing"}"#.utf8))
    }
    #expect(try Atvloadly.parseSourceUpdate(Data(#"{"code":200,"msg":"success","data":{"status":"installing","version":"0.4.0","build_name":"Player Build 41"}}"#.utf8)) == "0.4.0 (Player Build 41)")
    #expect(throws: AppUpdateError.invalidResponse) { try Atvloadly.parseApps(Data("<html>".utf8)) }
}

@Test func installRouteChoice() throws {
    let devices = [AtvloadlyDevice(id: "dev-1", name: "TV", udid: "U1")]
    let plain = AtvloadlyApp(id: 10, bundleID: "de.haskoman.player", udid: "U1", account: "user@example.com")
    let h: (String) -> String = { "h(\($0.count))" }
    let r = try InstallRoute.plan(apps: [plain], devices: devices, bundleID: "de.haskoman.player", accountID: h)
    #expect(r.appID == 10 && r.route == .mcp(deviceID: "dev-1", accountID: "h(16)"))
    // Die Apple-ID steht nicht im Weg (nur ihr Hash).
    #expect(!String(describing: r.route).contains("@"))
    var linked = plain; linked.id = 11; linked.sourceKind = "github"; linked.sourceURL = "https://github.com/Haskoman-Beep/tvos-player.git"
    #expect(try InstallRoute.plan(apps: [plain, linked], devices: devices, bundleID: "de.haskoman.player", accountID: h).route == .sourceUpdate(appID: 11))
    // Eintrag auf einem gerade nicht verbundenen Gerät verliert gegen den verbundenen.
    var away = plain; away.id = 12; away.udid = "U9"
    #expect(try InstallRoute.plan(apps: [plain, away], devices: devices, bundleID: "de.haskoman.player", accountID: h).appID == 10)
    #expect(throws: AppUpdateError.noApp) { try InstallRoute.plan(apps: [], devices: devices, bundleID: "de.haskoman.player", accountID: h) }
    #expect(throws: AppUpdateError.noDevice) { try InstallRoute.plan(apps: [away], devices: devices, bundleID: "de.haskoman.player", accountID: h) }
    var noAcc = plain; noAcc.account = ""
    #expect(throws: AppUpdateError.noAccount) { try InstallRoute.plan(apps: [noAcc], devices: devices, bundleID: "de.haskoman.player", accountID: h) }
    #expect(Atvloadly.repoSlug("haskoman-beep/tvos-player") == "haskoman-beep/tvos-player")
    #expect(Atvloadly.repoSlug("https://github.com/haskoman-beep/tvos-player/releases") == "haskoman-beep/tvos-player")
}

@Test func installingMatch() {
    let ipa = URL(string: "https://github.com/haskoman-beep/tvos-player/releases/download/app-main/Player.ipa")!
    let mcpEntry = AtvloadlyApp(id: 0, bundleID: "", ipaPath: ipa.absoluteString)
    #expect(Atvloadly.isInstalling([mcpEntry], appID: 10, bundleID: "de.haskoman.player", ipaURL: ipa))
    #expect(!Atvloadly.isInstalling([mcpEntry], appID: 10, bundleID: "de.haskoman.player", ipaURL: nil))
    #expect(Atvloadly.isInstalling([AtvloadlyApp(id: 10, bundleID: "")], appID: 10, bundleID: "x", ipaURL: nil))
    #expect(!Atvloadly.isInstalling([AtvloadlyApp(id: 3, bundleID: "com.other.app")], appID: 10, bundleID: "de.haskoman.player", ipaURL: ipa))
}

@Test func mcpBodiesAndResponses() throws {
    let ini = try #require(JSONSerialization.jsonObject(with: AtvloadlyMCP.initialize(id: 1, client: "player-tvos", version: "0.4.0")) as? [String: Any])
    #expect(ini["jsonrpc"] as? String == "2.0" && ini["method"] as? String == "initialize" && ini["id"] as? Int == 1)
    #expect((ini["params"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
    let note = String(decoding: AtvloadlyMCP.initialized(), as: UTF8.self)
    #expect(note == #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
    let call = try #require(JSONSerialization.jsonObject(with: AtvloadlyMCP.installApp(id: 2, ipaURL: URL(string: "https://x/Player.ipa")!, deviceID: "dev-1", accountID: "abc")) as? [String: Any])
    let args = (call["params"] as? [String: Any])?["arguments"] as? [String: String]
    #expect(args == ["ipa_url": "https://x/Player.ipa", "device_id": "dev-1", "account_id": "abc"])

    // Antwortformate: SSE (Standard von go-sdk) und reines JSON.
    let iniReply = sse(#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"tools":{"listChanged":true}},"protocolVersion":"2025-03-26","serverInfo":{"name":"atvloadly-mcp","version":"v0.8.5"}}}"#)
    #expect(try AtvloadlyMCP.negotiatedVersion(Data(iniReply.utf8), id: 1) == "2025-03-26")
    let status = sse(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"install_in_progress\":false,\"install_state\":\"completed\"}"}],"structuredContent":{"install_in_progress":false,"install_state":"completed"}}}"#)
    let s = try AtvloadlyMCP.toolResult(Data(status.utf8), id: 2)
    #expect(s.status == "completed" && s.inProgress == false && !s.isError)
    let ok = #"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{}"}],"structuredContent":{"status":"installing","message":"Install task queued to task.StartInstallApps.","selected_device":{"id":"dev-1"}}}}"#
    #expect(try AtvloadlyMCP.checkInstall(try AtvloadlyMCP.toolResult(Data(ok.utf8), id: 2)) == "Install task queued to task.StartInstallApps.")
    let choice = sse(#"{"jsonrpc":"2.0","id":2,"result":{"content":[],"structuredContent":{"status":"require_account","available_accounts":[{"account_email":"u***@example.com"}]}}}"#)
    #expect(throws: AppUpdateError.needsChoice("require_account")) { try AtvloadlyMCP.checkInstall(try AtvloadlyMCP.toolResult(Data(choice.utf8), id: 2)) }
    let toolErr = sse(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ipa_url must point to an .ipa file"}],"isError":true}}"#)
    #expect(throws: AppUpdateError.mcp("ipa_url must point to an .ipa file")) { try AtvloadlyMCP.checkInstall(try AtvloadlyMCP.toolResult(Data(toolErr.utf8), id: 2)) }
    let rpcErr = "event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"bad\"}}\r\n\r\n"
    #expect(throws: AppUpdateError.mcp("bad")) { try AtvloadlyMCP.toolResult(Data(rpcErr.utf8), id: 2) }
    #expect(throws: AppUpdateError.invalidResponse) { try AtvloadlyMCP.toolResult(Data(sse(#"{"jsonrpc":"2.0","id":7,"result":{}}"#).utf8), id: 2) }
}

@Test func logRedaction() {
    #expect(AppUpdateLog.redact("account_id not found: 0123456789abcdef0123456789abcdef") == "account_id not found: …")
    #expect(AppUpdateLog.redact("Konto (user@example.com) fehlt") == "Konto … fehlt")
    #expect(AppUpdateError.atvloadly("x user@example.com").text == "atvloadly: x …")
    // key=value: nur der Wert, ab 33 Zeichen oder bei Konto/Hash.
    #expect(AppUpdateLog.redact("GET /x?token=abcdefghijklmnopqrstuvwxyz0123456789 ok") == "GET /x?token=… ok")
    #expect(AppUpdateLog.redact("a=1&secret=0123456789abcdef0123456789abcdef") == "a=1&secret=…")
    #expect(AppUpdateLog.redact("account=user@example.com, mode=short") == "account=… mode=short")
    #expect(AppUpdateLog.redact("k=abcdefghijklmnopqrstuvwxyz012345") == "k=abcdefghijklmnopqrstuvwxyz012345")
}

@Test func installWatchNeedsSeenEntry() {
    let ipa = GitHubBuilds.ipaURL
    let entry = AtvloadlyApp(id: 0, bundleID: "", ipaPath: ipa.absoluteString)
    func watch() -> InstallWatch { InstallWatch(appID: 10, bundleID: "de.haskoman.player", ipaURL: ipa) }
    // Leere Liste vor dem ersten Auftauchen ist nicht „fertig“.
    var w = watch()
    #expect(w.observe([], elapsed: 0) == .waiting && w.observe([], elapsed: 59) == .waiting && !w.seen)
    #expect(w.observe([entry], elapsed: 62) == .running && w.seen)
    #expect(w.failed(elapsed: 65) == .running)
    #expect(w.observe([], elapsed: 68) == .finished)
    #expect(InstallWatch.Outcome.finished.text?.hasPrefix("Installation offenbar fehlgeschlagen (App läuft noch)") == true)
    // Nie aufgetaucht: nach der Gnadenfrist „nicht gestartet“.
    var never = watch()
    #expect(never.observe([], elapsed: 30) == .waiting && never.observe([], elapsed: InstallWatch.grace) == .notStarted)
    #expect(InstallWatch.Outcome.notStarted.text == "atvloadly hat die Aufgabe nicht gestartet.")
    // Fehler in Folge; eine Antwort setzt den Zähler zurück.
    var flaky = watch()
    for i in 1..<InstallWatch.maxMisses { #expect(flaky.failed(elapsed: Double(i)) == .waiting) }
    #expect(flaky.observe([entry], elapsed: 12) == .running && flaky.misses == 0)
    for i in 1..<InstallWatch.maxMisses { #expect(flaky.failed(elapsed: 12 + Double(i)) == .running) }
    #expect(flaky.failed(elapsed: 30) == .unreachable)
    var long = watch()
    #expect(long.observe([entry], elapsed: InstallWatch.limit) == .timedOut)
    #expect(!InstallWatch.Outcome.waiting.isFinal && !InstallWatch.Outcome.running.isFinal && InstallWatch.Outcome.finished.isFinal)
    #expect(InstallWatch.Outcome.running.text == nil)
}

@Test func githubCheckFlow() async throws {
    let http = ScriptSender([.ok(200, runsJSON(41, sha41)), .ok(200, releaseJSON(41, sha41))])
    let client = AppUpdateClient(http: http, accountID: { _ in "h" })
    let installed = AppBuildInfo(version: "0.4.0", build: 40, commit: sha40, branch: "main")
    guard case .available(let rel, let latest) = try await client.check(current: installed) else { Issue.record("kein Update"); return }
    #expect(rel.number == 41 && latest.number == 41)
    #expect(http.sent.map(\.url) == [GitHubBuilds.latestRunURL, GitHubBuilds.releaseURL])
    #expect(http.sent[0].headers["Accept"] == "application/vnd.github+json")

    let noRelease = ScriptSender([.ok(200, runsJSON(41, sha41)), .ok(404, #"{"message":"Not Found"}"#)])
    #expect(try await AppUpdateClient(http: noRelease, accountID: { _ in "" }).check(current: installed) == .notPublished(CIBuild(number: 41, commit: sha41, date: GitHubBuilds.parseDate("2026-11-21T13:40:28Z"))))
    let limited = ScriptSender([.ok(403, #"{"message":"API rate limit exceeded"}"#)])
    await #expect(throws: AppUpdateError.github(403)) { try await AppUpdateClient(http: limited, accountID: { _ in "" }).check(current: installed) }
}

@Test func mcpInstallFlow() async throws {
    let base = AtvloadlyAddress.normalize("pi-name.local")!
    let release = ReleaseBuild(number: 41, commit: sha41, ipaURL: URL(string: "https://github.com/haskoman-beep/tvos-player/releases/download/app-main/Player.ipa")!)
    let installOK = sse(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{}"}],"structuredContent":{"status":"installing","message":"queued"}}}"#)
    let http = ScriptSender([
        .ok(200, #"{"code":200,"msg":"success","data":[]}"#),
        .ok(200, appsJSON),
        .ok(200, devicesJSON),
        .ok(200, sse(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}"#), ["Mcp-Session-Id": "S1"]),
        .ok(202, ""),
        .ok(200, installOK),
        .ok(204, ""),
    ])
    let client = AppUpdateClient(http: http, accountID: { "md5(\($0.count))" })
    let started = try await client.start(base: base, bundleID: "de.haskoman.player", release: release)
    #expect(started == AppUpdateClient.Started(route: .mcp(deviceID: "dev-1", accountID: "md5(16)"), appID: 10, message: "queued"))
    #expect(http.sent.map { "\($0.method) \($0.url.path)" } == ["GET /api/apps/installing", "GET /api/apps", "GET /api/devices",
                                                                 "POST /mcp", "POST /mcp", "POST /mcp", "DELETE /mcp"])
    #expect(http.sent[3].headers["Accept"] == "application/json, text/event-stream" && http.sent[3].headers["Mcp-Session-Id"] == nil)
    #expect(http.sent[4].headers["Mcp-Session-Id"] == "S1" && http.sent[4].headers["Mcp-Protocol-Version"] == "2025-06-18")
    let args = ((try JSONSerialization.jsonObject(with: http.sent[5].body ?? Data()) as? [String: Any])?["params"] as? [String: Any])?["arguments"] as? [String: String]
    #expect(args == ["ipa_url": release.ipaURL.absoluteString, "device_id": "dev-1", "account_id": "md5(16)"])
    #expect(http.sent[6].headers["Mcp-Session-Id"] == "S1")
    // Kein Konto-Klartext in den gesendeten Anfragen.
    #expect(!http.sent.contains { String(decoding: $0.body ?? Data(), as: UTF8.self).contains("@") })
}

@Test func mcpInstallClosesSessionOnError() async throws {
    let base = AtvloadlyAddress.normalize("pi-name.local")!
    let release = ReleaseBuild(number: 41, commit: sha41, ipaURL: GitHubBuilds.ipaURL)
    let http = ScriptSender([
        .ok(200, #"{"code":200,"msg":"success","data":[]}"#), .ok(200, appsJSON), .ok(200, devicesJSON),
        .ok(200, sse(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}"#), ["mcp-session-id": "S2"]),
        .ok(202, ""),
        .ok(200, sse(#"{"jsonrpc":"2.0","id":2,"result":{"content":[],"structuredContent":{"status":"require_signing"}}}"#)),
        .ok(204, ""),
    ])
    await #expect(throws: AppUpdateError.needsChoice("require_signing")) {
        try await AppUpdateClient(http: http, accountID: { _ in "h" }).start(base: base, bundleID: "de.haskoman.player", release: release)
    }
    #expect(http.sent.last?.method == "DELETE")
}

@Test func sourceUpdateFlowAndBusy() async throws {
    let base = AtvloadlyAddress.normalize("pi-name.local")!
    let release = ReleaseBuild(number: 41, commit: sha41, ipaURL: GitHubBuilds.ipaURL)
    let linkedApps = appsJSON.replacingOccurrences(of: #""source":{"kind":"","url":"","filter":""}"#,
                                                   with: #""source":{"kind":"github","url":"haskoman-beep/tvos-player","filter":""}"#)
    let http = ScriptSender([
        .ok(200, #"{"code":200,"msg":"success","data":[]}"#), .ok(200, linkedApps), .ok(200, devicesJSON),
        .ok(200, #"{"code":200,"msg":"success","data":{"status":"installing","version":"0.4.0","build_name":"Player Build 41"}}"#),
    ])
    let started = try await AppUpdateClient(http: http, accountID: { _ in "h" }).start(base: base, bundleID: "de.haskoman.player", release: release)
    #expect(started.route == .sourceUpdate(appID: 10) && started.message == "0.4.0 (Player Build 41)")
    #expect(http.sent.last.map { "\($0.method) \($0.url.path)" } == "POST /api/apps/10/source/update")

    let busy = ScriptSender([.ok(200, #"{"code":200,"msg":"success","data":[{"ID":10,"bundle_identifier":"de.haskoman.player"}]}"#)])
    await #expect(throws: AppUpdateError.busy) {
        try await AppUpdateClient(http: busy, accountID: { _ in "h" }).start(base: base, bundleID: "de.haskoman.player", release: release)
    }
    #expect(busy.sent.count == 1)

    // Andere Paketadresse: abgelehnt, bevor atvloadly gefragt wird.
    let none = ScriptSender([])
    let foreign = ReleaseBuild(number: 41, commit: sha41, ipaURL: URL(string: "https://x/Player.ipa")!)
    await #expect(throws: AppUpdateError.wrongPackage) {
        try await AppUpdateClient(http: none, accountID: { _ in "h" }).start(base: base, bundleID: "de.haskoman.player", release: foreign)
    }
    #expect(none.sent.isEmpty)
}
