import Foundation

/// Wave W-a: what a stream entry of an addon is. Aggregators such as AIOStreams put notices into the stream list
/// next to the real sources:
/// - error entries: name „[❌] Addon“, the error text in `description`, only an `externalUrl` to the project page;
/// - statistics entries: like errors (same `externalUrl`, no `url`), name = title, `description` = the numbers;
/// - info entries: they carry an http(s) `url`, but it is an action link, not a video, e.g. „🔄 …“ library entries or
///   „Sync debrid account library now“. Opening one starts the action on the server instead of playing.
/// When the aggregator sends `streamData.type` ("error", "statistic", "info"), that decides first.
/// Notices are never playable, never picked automatically and never listed as a source; the app only logs them
/// (`AddonStreamNotices.logLine`).
public enum AddonStreamKind: String, Sendable, Equatable {
    /// A real source (it may still be unplayable for the app, e.g. P2P without `url`).
    case stream
    case error
    case statistic
    /// Action link with an http(s) `url` (library sync and the like).
    case action

    public var isNotice: Bool { self != .stream }

    public static func classify(_ s: StreamItem) -> AddonStreamKind {
        switch s.streamData?.type?.lowercased() {
        case "error": return .error
        case "statistic", "statistics", "stats": return .statistic
        case "info": return .action
        default: break
        }
        let name = firstLine(s.name), title = firstLine(s.title)
        guard hasWebURL(s) else {
            if name.hasPrefix(errorMark) || title.hasPrefix(errorMark) { return .error }
            if isProjectPage(s.externalUrl) { return .statistic }
            return .stream
        }
        if name.hasPrefix(actionMark) || title.hasPrefix(actionMark) { return .action }
        let lines = [s.name, s.title, s.description].compactMap { $0 }.flatMap { $0.components(separatedBy: .newlines) }
        if lines.contains(where: isLibrarySyncLine) { return .action }
        return .stream
    }

    static let errorMark = "[❌]"
    static let actionMark = "🔄"

    /// http(s) address (the only kind the player opens).
    static func hasWebURL(_ s: StreamItem) -> Bool {
        guard let u = s.url, let scheme = URL(string: u)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The aggregator's project page (`github.com/<owner>/AIOStreams…`), which error and statistics entries link to
    /// instead of a video.
    static func isProjectPage(_ raw: String?) -> Bool {
        guard let raw, let u = URL(string: raw), u.host?.lowercased() == "github.com" else { return false }
        let parts = u.path.split(separator: "/")
        return parts.count >= 2 && parts[1].lowercased() == "aiostreams"
    }

    /// „Sync debrid account library now“, „🔄 Sync library“: after leading symbols the line starts with „sync “
    /// and names a library. Release names („Sync.Library.2020…“) do not count.
    static func isLibrarySyncLine(_ line: String) -> Bool {
        let core = String(line.drop { !$0.isLetter }).lowercased()
        return core.hasPrefix("sync ") && core.contains(" library")
    }

    /// First line without surrounding blanks and without emoji variation selectors (U+FE0E/U+FE0F), so „🔄“ and
    /// „❌“ match whether or not the addon sends the selector.
    static func firstLine(_ s: String?) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: (s ?? "").unicodeScalars.filter { $0.value != 0xFE0E && $0.value != 0xFE0F })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
    }
}

extension StreamItem {
    /// Wave W-a: what this entry is (`AddonStreamKind.classify`).
    public var addonKind: AddonStreamKind { AddonStreamKind.classify(self) }

    /// Wave W-a: an http(s) address that is a real source, not an addon notice. The one rule for the source list,
    /// „Sofort abspielen“ and every automatic pick.
    public var isPlayableVideo: Bool { AddonStreamKind.hasWebURL(self) && !addonKind.isNotice }
}

/// Wave W-a: notices of a stream answer, for the log only (user decision: they never appear in the source list).
public enum AddonStreamNotices {
    public struct Notice: Equatable, Sendable {
        public var kind: AddonStreamKind
        /// First line of the entry's name (or title).
        public var title: String
        /// The entry's text on one line (`description`, else `title`); for errors this is the error message.
        public var text: String?
    }

    /// Longest title and text in the log line.
    static let maxTitle = 60
    static let maxText = 160
    /// Notices named in the log line; the rest only counts.
    static let maxListed = 5

    public static func notices(_ streams: [StreamItem]) -> [Notice] {
        streams.compactMap { s in
            let kind = s.addonKind
            guard kind.isNotice else { return nil }
            let name = AddonStreamKind.firstLine(s.name)
            let title = name.isEmpty ? AddonStreamKind.firstLine(s.title) : name
            let body = s.description ?? (name.isEmpty ? nil : s.title)
            return Notice(kind: kind, title: shorten(title, maxTitle), text: oneLine(body).map { shorten($0, maxText) })
        }
    }

    /// „AIOStreams Hinweise: 2 (Fehler „[❌] Comet“: Invalid API key · Aktion „🔄 Sync library“)“; nil without
    /// notices. Errors carry their text, statistics and actions only their title. One line per stream load.
    public static func logLine(_ streams: [StreamItem]) -> String? {
        let all = notices(streams)
        guard !all.isEmpty else { return nil }
        var parts = all.prefix(maxListed).map { n -> String in
            let head = "\(label(n.kind)) „\(n.title)“"
            guard n.kind == .error, let t = n.text, !t.isEmpty else { return head }
            return head + ": " + t
        }
        if all.count > maxListed { parts.append("+\(all.count - maxListed) weitere") }
        return "AIOStreams Hinweise: \(all.count) (\(parts.joined(separator: " · ")))"
    }

    static func label(_ k: AddonStreamKind) -> String {
        switch k {
        case .error: "Fehler"
        case .statistic: "Statistik"
        case .action: "Aktion"
        case .stream: "Quelle"
        }
    }

    /// Lines joined with „ / “, blanks collapsed; nil when nothing is left.
    static func oneLine(_ s: String?) -> String? {
        guard let s else { return nil }
        let lines = s.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: " / ")
    }

    static func shorten(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
}
