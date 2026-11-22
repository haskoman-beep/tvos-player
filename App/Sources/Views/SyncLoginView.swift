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

    var name: String { service == "trakt" ? "Trakt" : "Simkl" }
    var link: String? {
        guard let code else { return nil }
        return service == "simkl" ? "\(code.verificationURL)/\(code.userCode)" : code.verificationURL
    }

    var body: some View {
        VStack(spacing: 40) {
            Text("Mit \(name) verbinden").font(.largeTitle.bold())
            if let code, let link {
                HStack(spacing: 80) {
                    if let img = qr(link) {
                        Image(uiImage: img).interpolation(.none).resizable().frame(width: 360, height: 360)
                            .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        Text("1. QR-Code scannen oder öffnen:").font(.title3)
                        Text(link).font(.title3.monospaced()).foregroundStyle(.secondary)
                        Text("2. Diesen Code eingeben:").font(.title3)
                        Text(code.userCode).font(.system(size: 90, weight: .bold, design: .monospaced))
                    }
                }
            }
            Text(status).font(.title3).foregroundStyle(done ? .green : .secondary)
            // N6 (Welle F-c): QR-Seite ohne andere Fokusziele; „Fertig“ schließt sie (Abfrage endet mit der Seite).
            FocusAnchor()
        }
        .padding(80)
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
