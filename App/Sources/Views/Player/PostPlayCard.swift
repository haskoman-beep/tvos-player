import SwiftUI
import PlayerCore

/// Wave P-a: card once a movie's end credits start (window: PlayerCore `SkipPolicy.postPlayWindow`, never over a
/// scene after the credits). Two or three recommendations from TMDB (the „Ähnliche Titel“ source of the detail page),
/// „Abspann weiterschauen“ (closes the card, the movie runs on) and „Zurück“ (leaves the player).
/// A recommendation leaves the player and opens its detail page once the player is gone (`PostPlayRoute`).
/// Holds the focus while it is up (PlayerControls gives up the surface via `SkipSegmentController.holdsFocus`);
/// Menu closes it like „Abspann weiterschauen“ (`dismissPrompt`).
struct PostPlayCard: View {
    let item: MetaPreview
    /// A scene follows the credits: the card says so (it goes away when the scene starts).
    let sceneFollows: Bool
    let onKeepWatching: () -> Void
    let onLeave: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    @State private var recs: [MetaPreview] = []
    @State private var loaded = false
    @FocusState private var focus: Target?

    private enum Target: Hashable { case rec(String), keepWatching, back }

    /// Shown recommendations at most.
    static let maxRecommendations = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(recs.isEmpty ? "Film zu Ende" : "Als Nächstes ansehen").font(.title3.bold())
                Spacer()
                if sceneFollows {
                    Label("Szene nach dem Abspann folgt", systemImage: "sparkles")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 30) {
                ForEach(recs) { m in
                    Button { open(m) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            TilePosterImage(item: m)
                                .frame(width: 170, height: 255)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(m.name).font(.caption).lineLimit(1).frame(width: 170, alignment: .leading)
                        }
                    }
                    .buttonStyle(.card)
                    .focused($focus, equals: .rec(m.id))
                }
                if !loaded {
                    ProgressView().frame(width: 170, height: 255)
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 20) {
                    Button { onKeepWatching() } label: {
                        Label("Abspann weiterschauen", systemImage: "play.fill").frame(minWidth: 380)
                    }
                    .focused($focus, equals: .keepWatching)
                    Button { RemoteLog.info("skip", "Karte nach dem Film: Zurück"); onLeave() } label: {
                        Label("Zurück", systemImage: "chevron.backward").frame(minWidth: 380)
                    }
                    .focused($focus, equals: .back)
                }
                // Build 4 follow-up: token buttons instead of system buttons (root tint as focused platter and label).
                .buttonStyle(ThemeActionButtonStyle())
            }
        }
        .padding(36)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 80).padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear { if focus == nil { focus = .keepWatching } }
        .task {
            // Focus at once (the surface is no longer focusable), again one round later in case the tree was not ready.
            focus = .keepWatching
            try? await Task.sleep(for: .milliseconds(50))
            if focus == nil { focus = .keepWatching }
        }
        .task(id: item.id) { await load() }
    }

    /// Recommendations from TMDB (cached after the detail page); nothing without a TMDB key or IMDb ID.
    private func load() async {
        defer { loaded = true }
        guard let imdb = await model.imdbID(for: item),
              let info = await model.localized(imdb: imdb, series: false) else {
            RemoteLog.info("skip", "Karte nach dem Film: keine Empfehlungen (ohne TMDB/IMDb)")
            return
        }
        guard !Task.isCancelled else { return }
        let list = PostPlayPicks.choose(info.recommendations, excluding: item.id, imdb: imdb, limit: Self.maxRecommendations)
        RemoteLog.info("skip", "Karte nach dem Film: \(list.count) Empfehlungen")
        withAnimation { recs = list }
    }

    private func open(_ m: MetaPreview) {
        RemoteLog.info("skip", "Karte nach dem Film: Empfehlung \(m.name) → Detailseite")
        let go = navigate
        PostPlayRoute.pending = { go(.detail(m)) }
        onLeave()
    }
}

/// Wave P-a: detail page to open once the player is gone. Set by the card; run from the stream list's
/// `playerDismissed` (end of the cover dismissal, before its focus move). PlayerScreen.onDisappear only arms a
/// late fallback in case no dismissal callback comes.
@MainActor
enum PostPlayRoute {
    static var pending: (() -> Void)?

    /// Run the pending route now. true = there was one (the caller then skips its own focus move).
    @discardableResult
    static func flushNow() -> Bool {
        guard let go = pending else { return false }
        pending = nil
        RemoteLog.info("skip", "Karte nach dem Film: Detailseite öffnen (Player geschlossen)")
        go()
        return true
    }

    /// Fallback: still pending 1.5 s after the player disappeared (no dismissal callback) → run it then.
    static func flushLater() {
        guard pending != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if pending != nil { RemoteLog.info("skip", "Karte nach dem Film: Ersatzweg nach onDisappear"); flushNow() }
        }
    }
}
