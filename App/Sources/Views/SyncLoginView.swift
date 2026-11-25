import SwiftUI
import PlayerCore

/// Geräte-Login für Trakt/Simkl: Code am Handy eingeben, der Fernseher fragt nach.
struct SyncLoginView: View {
    @EnvironmentObject var model: AppModel
    let service: String
    @Environment(\.dismiss) private var dismiss
    @State private var code: DeviceCode?
    @State private var status = "Code wird geholt …"
    @State private var done = false
    @Environment(\.theme) private var theme

    var name: String { service == "trakt" ? "Trakt" : "Simkl" }
    var link: String? {
        guard let code else { return nil }
        return service == "simkl" ? "\(code.verificationURL)/\(code.userCode)" : code.verificationURL
    }

    var body: some View {
        VStack(spacing: theme.space.xl) {
            Text("Mit \(name) verbinden").textRole(.display)
            if let code, let link {
                HStack(spacing: theme.space.edge) {
                    if let img = qr(link) {
                        Image(uiImage: img).interpolation(.none).resizable()
                            .frame(width: Theme.Layout.qrLogin, height: Theme.Layout.qrLogin)
                            .padding(theme.space.m)
                            .background(Theme.Palette.qrBackground,
                                        in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
                            .accessibilityLabel("QR-Code zum Anmelden bei \(name)")
                    }
                    SyncLoginSteps(link: link, userCode: code.userCode)
                }
            }
            // Font only: `textRole` would set its own colour nearer the text than this state colour.
            Text(status).font(theme.type.font(.sectionTitle).weight(.regular))
                .foregroundStyle(done ? Theme.Tone.ok.textColor : theme.color.secondary)
            // N6 (Welle F-c): QR-Seite ohne andere Fokusziele; „Fertig“ schließt sie (Abfrage endet mit der Seite).
            FocusAnchor()
        }
        .padding(theme.space.edge)
        .task { await run() }
    }

    private func run() async {
        do {
            let c = try await model.startLogin(service)
            code = c
            status = "Warte auf Bestätigung am Handy …"
            var wait = max(c.interval, 2)
            let end = Date().addingTimeInterval(TimeInterval(c.expiresIn))
            while Date() < end && !Task.isCancelled {
                try await Task.sleep(for: .seconds(wait))
                switch await model.pollLogin(service, c) {
                case .success:
                    done = true; status = "Verbunden ✓"
                    try? await Task.sleep(for: .seconds(2)); dismiss(); return
                case .slowDown: wait += 2
                // Build 2 (2.5): server trouble is no answer; keep waiting until the code expires.
                case .failed(let s) where s == 408 || s >= 500: break
                case .expired: status = "Code abgelaufen – bitte neu öffnen."; return
                case .denied: status = "Abgelehnt."; return
                case .failed(let s): status = "Fehler \(s) – Client ID/Secret prüfen."; return
                case .pending: break
                }
            }
            if !done { status = "Code abgelaufen – bitte neu öffnen." }
        } catch { status = "\(name) nicht erreichbar: \(error)" }
    }
}

/// The two steps next to the QR code: link and the code to type. Task 5.5: theme fonts; VoiceOver spells the code.
private struct SyncLoginSteps: View {
    let link: String
    let userCode: String
    @Environment(\.theme) private var theme

    var body: some View {
        // Today's title3 regular: the steps read as instructions, not as headings.
        let step: Font = theme.type.font(.sectionTitle).weight(.regular)
        VStack(alignment: .leading, spacing: theme.space.m) {
            Text("1. QR-Code scannen oder öffnen:").font(step).foregroundStyle(theme.color.primary)
            Text(link).font(step.monospaced()).foregroundStyle(theme.color.secondary)
            Text("2. Diesen Code eingeben:").font(step).foregroundStyle(theme.color.primary)
            Text(userCode).font(theme.type.glyph(.code))
                .foregroundStyle(theme.color.primary)
                .accessibilityLabel(userCode.map { String($0) }.joined(separator: " "))
        }
    }
}
