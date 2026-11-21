import SwiftUI
import PlayerCore

/// Welle C-d: „Meine TorBox-Dateien“ in der Bibliothek. Nur mit TorBox-Schlüssel (Handy-Seite → Schlüssel).
/// Abspielen über einen frischen `requestdl`-Link; wie ein Trailer ohne Fortschritt/Scrobble (keine IMDb-ID).
struct TorBoxFilesRow: View {
    @EnvironmentObject var model: AppModel
    @State private var files: [TorBoxFile]?
    @State private var failed = false
    @State private var playing: TorBoxPlay?
    @State private var resolving: String?

    /// Liste 5 min im Speicher: Öffnen der Bibliothek fragt TorBox nicht jedes Mal.
    @MainActor enum ListCache {
        static var key: String?
        static var at = Date.distantPast
        static var files: [TorBoxFile] = []
    }
    static let maxShown = 100

    struct TorBoxPlay: Identifiable { let file: TorBoxFile; let url: URL; var id: String { file.id } }

    private var key: String? { model.profile.apiKeys["torbox"].flatMap { $0.isEmpty ? nil : $0 } }

    var body: some View {
        if let key {
            VStack(alignment: .leading, spacing: 18) {
                Text("Meine TorBox-Dateien").font(.title3.bold()).padding(.leading, 60)
                if let files, !files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 40) {
                            ForEach(files.prefix(Self.maxShown)) { f in
                                Button { Task { await play(f, key: key) } } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(f.name).font(.headline).lineLimit(2)
                                        Text([f.folder == f.name ? nil : f.folder, f.sizeLabel].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        if resolving == f.id { ProgressView() }
                                    }
                                    .frame(width: 480, height: 150, alignment: .topLeading)
                                    .padding(16)
                                }
                                .buttonStyle(.card)
                            }
                            Button { Task { await load(key: key, fresh: true) } } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                    Text(files.count > Self.maxShown ? "Neu laden · \(files.count - Self.maxShown) weitere nicht gezeigt" : "Neu laden")
                                        .font(.caption).multilineTextAlignment(.center)
                                }
                                .frame(width: 240, height: 150).padding(16)
                            }
                            .buttonStyle(.card)
                        }
                        .padding(.horizontal, 60).padding(.vertical, 20)
                    }
                } else {
                    Text(files == nil ? (failed ? "TorBox nicht erreichbar." : "Lädt …") : "Keine fertigen Video-Dateien im Konto.")
                        .quietHintStyle().frame(height: 120).padding(.leading, 60)
                }
            }
            .task(id: key) { await load(key: key, fresh: false) }
            .fullScreenCover(item: $playing) { p in
                PlayerScreen(url: p.url,
                             request: PlayRequest(type: "movie", id: "torbox:\(p.file.id)", title: p.file.name,
                                                  item: MetaPreview(id: "torbox:\(p.file.id)", type: "movie", name: p.file.name)),
                             onEnded: { _ in playing = nil },
                             onFallback: { reason in
                                 playing = nil
                                 RemoteLog.info("torbox", "Wiedergabe fehlgeschlagen: \(reason)")
                             },
                             isTrailer: true)
                    .environmentObject(model)
            }
        }
    }

    private func load(key: String, fresh: Bool) async {
        if !fresh, ListCache.key == key, Date().timeIntervalSince(ListCache.at) < 300 { files = ListCache.files; return }
        do {
            let list = try await TorBoxClient(apiKey: key).files(fresh: fresh)
            files = list; failed = false
            ListCache.key = key; ListCache.at = Date(); ListCache.files = list
            RemoteLog.info("torbox", "\(list.count) Video-Dateien im Konto")
        } catch {
            failed = true
            RemoteLog.error("torbox", "Liste: \(LogRedact.text("\(error)"))")
        }
    }

    private func play(_ f: TorBoxFile, key: String) async {
        guard resolving == nil else { return }
        resolving = f.id
        defer { resolving = nil }
        do {
            let url = try await TorBoxClient(apiKey: key).link(for: f)
            playing = TorBoxPlay(file: f, url: url)
        } catch {
            model.lastError = "TorBox-Link nicht erhalten: \(TorBoxClient.userMessage(error))"
            RemoteLog.error("torbox", "Link: \(LogRedact.text("\(error)"))")
        }
    }
}
