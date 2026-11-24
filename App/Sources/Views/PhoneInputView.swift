import SwiftUI
import Network
import CoreImage.CIFilterBuiltins
import PlayerCore

/// Kleiner Web-Server im Heimnetz, solange die Seite offen ist (Spec §5, Handy-Eingabe).
/// Task 1.4: one-time QR address plus session cookie (`PhoneSession`), head checked before any body, at most
/// `PhoneLimits.maxConnections` connections with `PhoneLimits.requestDeadline` each, and a confirmation on the TV for
/// restore, addons, keys and the export with secrets (`PhoneConfirmGate`).
@MainActor
final class PhoneServer: ObservableObject {
    /// QR address (with the one-time token).
    @Published var address: String?
    /// Address as text on screen, without the token (SEC-16).
    @Published var shownAddress: String?
    @Published var failure: String?
    @Published private(set) var confirmation: PhoneConfirmation?
    /// Final review: why the typed code did not open the sealed backup; the request stays open for another try.
    @Published private(set) var codeProblem: String?
    /// Code of the last sealed backup; only on this screen, never sent and never stored.
    @Published private(set) var exportCode: String?
    @Published private(set) var connected = false
    let page = PhoneInputPage()
    private var session = PhoneSession(token: PhoneInputPage.randomToken(), now: Date())
    private var gate = PhoneConfirmGate()
    private var sealedFile: Data?
    private var sealedUntil: Date?
    private var sealedDelivered = false
    /// Fix round 1: why the last sealed export ended without a file (shown on the phone's download page).
    private var sealedOutcome: PhoneSealedOutcome?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var ticker: Task<Void, Never>?
    weak var model: AppModel?
    static let port: UInt16 = 8765
    /// The sealed file waits this long for its one download.
    static let sealedLifetime: TimeInterval = 5 * 60

    func start(model: AppModel) {
        self.model = model
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.accept(c) } }
            l.stateUpdateHandler = { [weak self] s in
                Task { @MainActor in if case .failed(let e) = s { self?.failure = "Server-Fehler: \(e)" } }
            }
            l.start(queue: .main)
            listener = l
            failure = nil   // final review: an old error (e.g. before a trip to the background) goes with a new start
            newSession()
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self else { return }
                    self.tick()
                }
            }
        } catch { failure = "Server startet nicht: \(error)" }
    }

    /// Closing the view or the app going to the background ends the session, open connections and any open request.
    /// Fix round 1: the code of a sealed backup stays on screen until the view closes (`closing`), so a trip to the
    /// background does not lose it.
    func stop(closing: Bool = true) {
        listener?.cancel(); listener = nil
        ticker?.cancel(); ticker = nil
        session.end()
        for c in connections.values { c.cancel() }
        connections = [:]
        _ = gate.resolve(allow: false, now: Date())
        confirmation = nil; codeProblem = nil
        sealedFile = nil; sealedUntil = nil; sealedDelivered = false; sealedOutcome = nil
        if closing { exportCode = nil }
        address = nil; shownAddress = nil; connected = false
    }

    /// „Neuer QR-Code“ and after expiry: new token, the old session (cookie) ends.
    func newSession() {
        guard listener != nil else { return }
        session.end()
        session = PhoneSession(token: PhoneInputPage.randomToken(), now: Date())
        connected = false
        if let ip = Self.localIPv4() {
            let base = "http://\(ip):\(Self.port)"
            shownAddress = base
            address = "\(base)/?t=\(session.token)"
        } else { failure = "Keine WLAN/LAN-Adresse gefunden." }
    }

    private func tick() {
        let now = Date()
        if session.needsNewCode(now: now) {
            RemoteLog.info("handy", "QR-Code erneuert (abgelaufen)")
            newSession()
        }
        syncConnected()
        if let c = confirmation, gate.current(now: now) == nil {
            confirmation = nil; codeProblem = nil
            if c.commands.contains(.exportSecrets) { sealedOutcome = .lapsed }
            RemoteLog.info("handy", c.logLine(.lapsed))
        }
        if let u = sealedUntil, now >= u { sealedFile = nil; sealedUntil = nil; sealedOutcome = .lapsed }
    }

    private func syncConnected() {
        guard connected != session.isConnected else { return }
        connected = session.isConnected
        if connected { RemoteLog.info("handy", "Sitzung gebunden") }   // Task 1.8: QR address used by the first phone
    }

    /// „Erlauben“ / „Ablehnen“ on the card. `code` is the code typed for a sealed backup. Final review: a code that does
    /// not open the backup keeps the request open (`PhoneConfirmGate.answer`) and shows the reason on the card.
    func answer(allow: Bool, code: String) {
        let now = Date()
        let wantedExport = confirmation?.commands.contains(.exportSecrets) ?? false
        let open = confirmation
        var problem: String?
        let result = gate.answer(allow: allow, now: now) { file in
            guard let model = self.model else { return nil }
            let opened = model.openSealedBackup(file, code: code)
            problem = opened.problem
            return opened.data
        }
        let cmds: [PhoneCommand]
        let outcome: PhoneConfirmation.Outcome
        switch result {
        case .codeRejected:
            codeProblem = problem ?? "Sicherung nicht geöffnet: Code falsch oder Datei beschädigt."
            RemoteLog.info("handy", "Bestätigung \(open?.logKind ?? "Import") Code abgewiesen")
            return
        case .allowed(let c): cmds = c; outcome = .allowed
        case .declined: cmds = []; outcome = .declined
        case .lapsed: cmds = []; outcome = .lapsed   // Task 1.8: allowed too late counts as lapsed (nothing runs).
        }
        confirmation = nil; codeProblem = nil
        if let open { RemoteLog.info("handy", open.logLine(outcome)) }
        if wantedExport && outcome == .declined { sealedOutcome = .declined }
        guard let model else { return }
        if outcome == .lapsed {
            if wantedExport { sealedOutcome = .lapsed }
            model.lastError = "Die Anfrage ist abgelaufen. Bitte am Handy erneut senden."; return
        }
        var run: [PhoneCommand] = []
        for c in cmds {
            switch c {
            case .exportSecrets:
                if let s = model.sealedBackup() {
                    sealedFile = s.file; sealedUntil = now.addingTimeInterval(Self.sealedLifetime); sealedDelivered = false
                    exportCode = s.code
                } else { sealedOutcome = .failed }
            default:
                run.append(c)   // a sealed backup arrives here already opened
            }
        }
        if !run.isEmpty { Task { await model.apply(run) } }
    }

    private func accept(_ c: NWConnection) {
        guard listener != nil, connections.count < PhoneLimits.maxConnections else { c.cancel(); return }
        connections[ObjectIdentifier(c)] = c
        c.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + PhoneLimits.requestDeadline) { [weak self] in
            Task { @MainActor in self?.close(c) }
        }
        receive(c, buffer: Data(), bodyLength: nil)
    }

    private func close(_ c: NWConnection) {
        guard connections.removeValue(forKey: ObjectIdentifier(c)) != nil else { return }
        c.cancel()
    }

    /// Address of the device (without port); the session cookie only counts from the first device.
    private static func peer(_ c: NWConnection) -> String {
        if case .hostPort(let host, _) = c.endpoint { return "\(host)" }
        return "\(c.endpoint)"
    }

    /// `bodyLength` is nil until the head was admitted; a body is only read after that.
    private func receive(_ c: NWConnection, buffer: Data, bodyLength: Int?) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self, self.connections[ObjectIdentifier(c)] != nil else { return }
                var buf = buffer; if let data { buf.append(data) }
                var admitted = bodyLength
                if admitted == nil {
                    switch HTTPRequest.parseHead(buf) {
                    case .incomplete:
                        if done || err != nil { self.close(c) } else { self.receive(c, buffer: buf, bodyLength: nil) }
                        return
                    case .invalid:
                        self.send(c, HTTPResponse(status: 400, body: Data("Ungültig".utf8)))
                        return
                    case .complete(let head):
                        switch self.session.admit(head, peer: Self.peer(c), now: Date()) {
                        case .respond(let r):
                            self.syncConnected()
                            self.send(c, r)
                            return
                        case .readBody(let n):
                            admitted = n
                        }
                    }
                }
                switch HTTPRequest.parse(buf) {
                case .complete(let r):
                    self.handle(r, on: c)
                case .incomplete where !done && err == nil:
                    self.receive(c, buffer: buf, bodyLength: admitted)
                case .tooLarge:
                    self.send(c, HTTPResponse(status: 413, body: Data("Zu groß".utf8)))
                default:
                    self.send(c, HTTPResponse(status: 400, body: Data("Ungültig".utf8)))
                }
            }
        }
    }

    private func handle(_ r: HTTPRequest, on c: NWConnection) {
        guard let model else { send(c, HTTPResponse(status: 503, body: Data())); return }
        let now = Date()
        let backups = PhoneBackupState(blocked: model.storeState != .ready, sealedFile: sealedFile, sealedDelivered: sealedDelivered,
                                       sealedOutcome: sealedOutcome, requestOpen: gate.current(now: now) != nil)
        let (resp, cmds) = page.handle(r, profileName: model.profile.name, home: model.phoneHomeState(), backups: backups) {
            model.backupData()
        }
        // One download of the sealed file; the code stays on screen until the view closes.
        if r.path == PhoneInputPage.sealedPath, resp.status == 200, let f = sealedFile, resp.body == f {
            sealedFile = nil; sealedUntil = nil; sealedDelivered = true
            RemoteLog.info("handy", "Verschlüsselte Sicherung abgeholt")
        }
        // Welle F-e: „Startseite ordnen“ vor der Antwort übernehmen, damit die Folgeseite den neuen Stand zeigt.
        let home = cmds.filter(\.isHomeEdit), rest = cmds.filter { !$0.isHomeEdit }
        if !home.isEmpty { model.applyHome(home) }
        send(c, resp)
        guard !rest.isEmpty else { return }
        let (plain, refused) = gate.offer(rest, now: now)
        if let open = gate.current(now: now), open != confirmation {
            confirmation = open; codeProblem = nil
            // A new sealed export starts from scratch: no old file, no old result.
            if open.commands.contains(.exportSecrets) {
                sealedFile = nil; sealedUntil = nil; sealedDelivered = false; sealedOutcome = nil
            }
            RemoteLog.info("handy", "Bestätigung am Fernseher angefragt: \(open.commands.count) Befehl(e)")
        }
        // The page already refuses while a request is open (`requestOpen`); this only catches a race.
        if !refused.isEmpty {
            if refused.contains(.exportSecrets) { sealedOutcome = .busy }
            model.lastError = PhoneInputPage.busyText
        }
        if !plain.isEmpty { Task { await model.apply(plain) } }
    }

    private func send(_ c: NWConnection, _ r: HTTPResponse) {
        c.send(content: r.serialized, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                if let self { self.close(c) } else { c.cancel() }
            }
        })
    }

    /// Erste private IPv4 (en0 = WLAN/LAN am Apple TV).
    static func localIPv4() -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var found: [(String, String)] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") { found.append((name, ip)) }
            }
        }
        return (found.first { $0.0.hasPrefix("en") } ?? found.first)?.1
    }
}

struct PhoneInputView: View {
    /// Welle F-e: Abschnitt, bei dem die Handy-Seite aufgeht (Anker in der QR-Adresse); nil = Seitenanfang.
    var section: PhoneSection? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var server = PhoneServer()
    @FocusState private var doneFocused: Bool
    @State private var backupCode = ""

    private var link: String? { server.address.map { PhoneSection.url($0, section: section) } }

    var body: some View {
        ZStack {
            HStack(spacing: 80) {
                if let a = link, let img = qr(a) {
                    Image(uiImage: img).interpolation(.none).resizable().frame(width: 480, height: 480)
                        .padding(24).background(.white, in: RoundedRectangle(cornerRadius: 24))
                }
                VStack(alignment: .leading, spacing: 24) {
                    Text("Am Handy eingeben").font(.title2.bold())
                    Text("QR-Code mit der iPhone-Kamera scannen. Auf der Seite Addon-URLs, Schlüssel, Nuvio-Export oder TMDB-Links einfügen und senden. Unter „Startseite ordnen“ Reihen per Finger verschieben und ausblenden. Dort kannst du auch alle Profile sichern.")
                        .frame(maxWidth: 900, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if let a = server.shownAddress { Text(a).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    if server.connected {
                        Text("Handy verbunden. Der QR-Code gilt nur einmal; für ein anderes Gerät „Neuer QR-Code“ wählen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let code = server.exportCode {
                        // Label and code on separate lines; the code must never be truncated (a cut-off code makes the backup useless).
                        Text("Code der Sicherung:").font(.headline)
                        Text(BackupCrypto.groupedCode(code) ?? code).font(.title3.monospaced().bold())
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Text("Jetzt notieren: Ohne diesen Code lässt sich die Datei nicht wiederherstellen. Er wird nirgends gespeichert.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let f = server.failure { Text(f).foregroundStyle(.red) }
                    if let n = model.notice { Text("✓ " + n).foregroundStyle(.green) }
                    Text("Das Handy muss im selben WLAN sein. Die Seite ist nur erreichbar, solange diese Ansicht offen ist; nach 30 Minuten braucht es einen neuen QR-Code. Sichern, Wiederherstellen, Addons und Schlüssel bestätigst du hier am Fernseher.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.l) {
                        // Sichtbarer Fokusanker (A4/N6): ohne ihn hat die Seite nichts Fokussierbares.
                        Button("Fertig") { dismiss() }
                            .focused($doneFocused)
                            .accessibilityHint("Schließt die Handy-Eingabe")
                        Button("Neuer QR-Code") { server.newSession() }
                            .accessibilityHint("Die bisherige Adresse und Sitzung gelten danach nicht mehr")
                    }
                }
            }
            .padding(80)
            .disabled(server.confirmation != nil)
            // Task 1.4: the confirmation card lies over the QR code; focus starts on „Ablehnen“.
            if let c = server.confirmation {
                PhoneConfirmationCard(confirmation: c, code: $backupCode, problem: server.codeProblem) { allow in
                    server.answer(allow: allow, code: backupCode)
                    // A rejected code stays in the field, so a typo can be fixed.
                    if server.confirmation == nil { backupCode = "" }
                }
            }
        }
        .onAppear { model.notice = nil; server.start(model: model); doneFocused = true }
        .onDisappear { server.stop() }
        // SEC-16: no server while the app is in the background (Home button). Fix round 1: only `.background` stops it;
        // `.inactive` (keyboard for the code, a short overlay) keeps the open request, the sealed file and the code.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: server.start(model: model)
            case .background: server.stop(closing: false)
            default: break
            }
        }
        .onChange(of: server.confirmation == nil) { _, closed in if closed { backupCode = ""; doneFocused = true } }
    }

}

/// Task 1.4: „Erlauben“ / „Ablehnen“ for a request from the phone. Same layout as `SettingsConfirmationView`;
/// the cautious answer comes first and gets the focus, Menu answers „Ablehnen“. The request lapses after 60 s, with a
/// sealed backup after 5 minutes (`PhoneConfirmGate.lifetime(for:)`), then the card disappears. `problem`: the typed
/// code did not open the backup; the card stays for another try.
private struct PhoneConfirmationCard: View {
    let confirmation: PhoneConfirmation
    @Binding var code: String
    let problem: String?
    let answer: (Bool) -> Void

    private enum Choice: Hashable { case deny, code, allow }
    @FocusState private var focus: Choice?

    private var codeMissing: Bool { confirmation.needsCode && BackupCrypto.normalizedCode(code) == nil }

    var body: some View {
        ZStack {
            Theme.Palette.scrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Anfrage vom Handy").textRole(.sectionTitle)
                ForEach(Array(confirmation.summary.enumerated()), id: \.offset) { _, line in
                    Text(line).textRole(.rowDetail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(confirmation.lapseText).textRole(.rowDetail)
                VStack(spacing: Theme.Space.s) {
                    Button { answer(false) } label: {
                        SettingsRowLabel(symbol: "xmark", tint: Theme.CategoryTint.system.color, title: "Ablehnen",
                                         reserveDetailSpace: false)
                    }
                    .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                    .focused($focus, equals: .deny)
                    if confirmation.needsCode {
                        TextField("Code der Sicherung (12 Zeichen, z. B. K7QM-2XPA-9DRT)", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .code)
                        if let problem {
                            Text(problem).textRole(.rowDetail).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button { answer(true) } label: {
                        SettingsRowLabel(symbol: "checkmark", tint: Theme.Tone.ok.color, title: "Erlauben",
                                         reserveDetailSpace: false)
                    }
                    .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                    .focused($focus, equals: .allow)
                    .disabled(codeMissing)
                }
                .padding(.top, Theme.Space.s)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: Theme.Layout.confirmationWidth)
            .background(Theme.Palette.overlayCard, in: RoundedRectangle(cornerRadius: Theme.Radius.overlayCard))
            .focusSection()
        }
        .defaultFocus($focus, .deny)
        .onAppear { focus = .deny }
        .onExitCommand { answer(false) }
    }
}

func qr(_ s: String) -> UIImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(s.utf8); f.correctionLevel = "M"
    guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
}
