import SwiftUI
import Network
import CoreImage.CIFilterBuiltins
import PlayerCore

/// Kleiner Web-Server im Heimnetz, solange die Seite offen ist (Spec §5, Handy-Eingabe).
@MainActor
final class PhoneServer: ObservableObject {
    @Published var address: String?
    @Published var failure: String?
    let page = PhoneInputPage(token: PhoneInputPage.randomToken())
    private var listener: NWListener?
    weak var model: AppModel?
    static let port: UInt16 = 8765

    func start(model: AppModel) {
        self.model = model
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.serve(c) } }
            l.stateUpdateHandler = { [weak self] s in
                Task { @MainActor in if case .failed(let e) = s { self?.failure = "Server-Fehler: \(e)" } }
            }
            l.start(queue: .main)
            listener = l
            if let ip = Self.localIPv4() { address = "http://\(ip):\(Self.port)/?t=\(page.token)" } else { failure = "Keine WLAN/LAN-Adresse gefunden." }
        } catch { failure = "Server startet nicht: \(error)" }
    }

    func stop() { listener?.cancel(); listener = nil }

    private func serve(_ c: NWConnection) {
        c.start(queue: .main)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer; if let data { buf.append(data) }
                switch HTTPRequest.parse(buf) {
                case .incomplete where !done && err == nil:
                    self.receive(c, buffer: buf)
                case .complete(let r):
                    let (resp, cmds) = self.page.handle(r, profileName: self.model?.profile.name ?? "") { self.model?.backupData() ?? Data() }
                    self.send(c, resp)
                    if !cmds.isEmpty, let m = self.model { await m.apply(cmds) }
                case .tooLarge:
                    self.send(c, HTTPResponse(status: 413, body: Data("Zu groß".utf8)))
                default:
                    self.send(c, HTTPResponse(status: 400, body: Data("Ungültig".utf8)))
                }
            }
        }
    }

    private func send(_ c: NWConnection, _ r: HTTPResponse) {
        c.send(content: r.serialized, completion: .contentProcessed { _ in c.cancel() })
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
    @EnvironmentObject var model: AppModel
    @StateObject private var server = PhoneServer()

    var body: some View {
        HStack(spacing: 80) {
            if let a = server.address, let img = qr(a) {
                Image(uiImage: img).interpolation(.none).resizable().frame(width: 480, height: 480)
                    .padding(24).background(.white, in: RoundedRectangle(cornerRadius: 24))
            }
            VStack(alignment: .leading, spacing: 24) {
                Text("Am Handy eingeben").font(.title2.bold())
                Text("QR-Code mit der iPhone-Kamera scannen. Auf der Seite Addon-URLs, Schlüssel, Nuvio-Export oder TMDB-Links einfügen und senden. Dort kannst du auch alle Profile sichern.")
                    .frame(maxWidth: 900, alignment: .leading)
                if let a = server.address { Text(a).font(.caption.monospaced()).foregroundStyle(.secondary) }
                if let f = server.failure { Text(f).foregroundStyle(.red) }
                if let n = model.notice { Text("✓ " + n).foregroundStyle(.green) }
                Text("Das Handy muss im selben WLAN sein. Die Seite ist nur erreichbar, solange diese Ansicht offen ist.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Fertig") {}.hidden()
            }
        }
        .padding(80)
        .onAppear { model.notice = nil; server.start(model: model) }
        .onDisappear { server.stop() }
    }

    private func qr(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
