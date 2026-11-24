import SwiftUI
import PlayerCore

/// Welle C-d: „Meine TorBox-Dateien“ in der Bibliothek. Nur mit TorBox-Schlüssel (Handy-Seite → Schlüssel).
/// Abspielen über einen frischen `requestdl`-Link; ohne Weiterschauen/Scrobble (keine IMDb-ID). Welle D-a: eigener
/// Fortschritt je TorBox-Datei (PlayerMemory), „Fortsetzen ab …“ auf der Kachel, Kontextmenü „Von vorn abspielen“.
struct TorBoxFilesRow: View {
    @EnvironmentObject var model: AppModel
    @State private var files: [TorBoxFile]?
    @State private var failed = false
    @State private var playing: TorBoxPlay?
    @State private var resolving: String?
    @ObservedObject private var memory = PlayerMemory.shared

    /// Liste 5 min im Speicher: Öffnen der Bibliothek fragt TorBox nicht jedes Mal.
    @MainActor enum ListCache {
        static var key: String?
        static var at = Date.distantPast
        static var files: [TorBoxFile] = []
    }
    static let maxShown = 100

    struct TorBoxPlay: Identifiable { let file: TorBoxFile; let url: URL; let start: Double?; var id: String { file.id } }

    /// Fortschritts-Schlüssel: TorBox-Datei-ID (wie die Wiedergabe-ID).
    static func progressKey(_ f: TorBoxFile) -> String { "torbox:\(f.id)" }

    private var key: String? { model.profile.apiKeys["torbox"].flatMap { $0.isEmpty ? nil : $0 } }

    var body: some View {
        if let key {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Meine TorBox-Dateien").textRole(.sectionTitle).padding(.leading, Theme.Space.edge)
                if let files, !files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: Theme.Space.m) {
                            ForEach(files.prefix(Self.maxShown)) { f in
                                let resume = memory.fileResume(profile: model.profile.id, key: Self.progressKey(f))
                                Button { Task { await play(f, key: key, fromStart: false) } } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(f.name).font(.headline).lineLimit(2)
                                        Text([f.folder == f.name ? nil : f.folder, f.sizeLabel].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        progressLine(f, resume: resume)
                                        if resolving == f.id { ProgressView() }
                                    }
                                    .frame(width: 480, height: 150, alignment: .topLeading)
                                    .padding(16)
                                }
                                .buttonStyle(.card)
                                .contextMenu {
                                    if resume != nil {
                                        Button("Von vorn abspielen") { Task { await play(f, key: key, fromStart: true) } }
                                    }
                                }
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
                        .padding(.horizontal, Theme.Space.edge).padding(.vertical, Theme.Space.m)
                    }
                } else {
                    Text(files == nil ? (failed ? "TorBox nicht erreichbar." : "Lädt …") : "Keine fertigen Video-Dateien im Konto.")
                        .quietHintStyle().frame(height: 120).padding(.leading, Theme.Space.edge)
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
                             isTrailer: true,
                             ownProgress: OwnProgress(start: p.start) { [profile = model.profile.id] pos, dur in
                                 PlayerMemory.shared.recordFile(profile: profile, key: Self.progressKey(p.file), position: pos, duration: dur)
                             })
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

    /// „Fortsetzen ab …“ mit Balken bzw. „Gesehen“.
    @ViewBuilder private func progressLine(_ f: TorBoxFile, resume: Double?) -> some View {
        let k = Self.progressKey(f)
        if let resume {
            HStack(spacing: 12) {
                Text("Fortsetzen ab \(timeText(resume))").font(.caption)
                if let fr = memory.fileFraction(profile: model.profile.id, key: k) {
                    ProgressView(value: fr).frame(width: 160)
                }
            }
        } else if memory.fileWatched(profile: model.profile.id, key: k) {
            Label("Gesehen", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func play(_ f: TorBoxFile, key: String, fromStart: Bool) async {
        guard resolving == nil else { return }
        resolving = f.id
        defer { resolving = nil }
        let startedAt = VisiblePage.stamp
        do {
            let url = try await TorBoxClient(apiKey: key).link(for: f)
            // F-A-1: Menu to the Start tab (or another page) while waiting → do not open the player there.
            guard VisiblePage.mayNavigate(from: startedAt, "torbox Datei") else { return }
            let start = fromStart ? nil : PlayerMemory.shared.fileResume(profile: model.profile.id, key: Self.progressKey(f))
            RemoteLog.info("torbox", "Start \(start.map { "ab \(Int($0)) s" } ?? "von vorn")")
            playing = TorBoxPlay(file: f, url: url, start: start)
        } catch {
            model.lastError = "TorBox-Link nicht erhalten: \(TorBoxClient.userMessage(error))"
            RemoteLog.error("torbox", "Link: \(LogRedact.text("\(error)"))")
        }
    }
}
