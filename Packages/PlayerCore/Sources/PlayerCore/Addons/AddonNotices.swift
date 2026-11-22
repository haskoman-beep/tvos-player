import Foundation

/// Wave W-a: error entries addons put into catalogs, metas and subtitle lists instead of an HTTP error.
/// They are dropped (catalog tiles, subtitle tracks) and only logged.
public enum AddonNotices {
    /// ID prefixes of error items in catalogs and metas: AIOStreams `aiostreamserror.{…}`, AIOMetadata `aiom.error.…`.
    public static let errorItemPrefixes = ["aiostreamserror.", "aiom.error."]

    public static func isErrorItem(id: String) -> Bool {
        let low = id.lowercased()
        return errorItemPrefixes.contains { low.hasPrefix($0) }
    }

    /// Error entry in a subtitle list (AIOStreams: `id` „error.…“, `lang` „[❌] Addon - …“, `url` to the project page).
    /// Picking it would load an HTML page as subtitles.
    public static func isErrorSubtitle(id: String?, lang: String?, url: String?) -> Bool {
        if let id, id.lowercased().hasPrefix("error.") { return true }
        if AddonStreamKind.firstLine(lang).hasPrefix(AddonStreamKind.errorMark) { return true }
        return AddonStreamKind.isProjectPage(url)
    }

    /// „1 unlesbarer Eintrag übersprungen“ / „3 unlesbare Einträge übersprungen“.
    public static func skippedText(_ n: Int) -> String {
        n == 1 ? "1 unlesbarer Eintrag übersprungen" : "\(n) unlesbare Einträge übersprungen"
    }

    /// Short text of an error item for the log: name and description on one line, else the ID.
    public static func text(name: String?, description: String?, id: String) -> String {
        let parts = [name, description].compactMap { AddonStreamNotices.oneLine($0) }
        let raw = parts.isEmpty ? id : parts.joined(separator: " – ")
        return AddonStreamNotices.shorten(raw, AddonStreamNotices.maxText)
    }
}

/// Wave W-a: addons the app treats specially by manifest ID (or name, for renamed instances).
public enum KnownAddon {
    public static let aioMetadataID = "com.aio.metadata"

    /// AIOMetadata, by manifest ID or by name („AIO Metadata“, „AIOMetadata“ for renamed instances).
    public static func isAIOMetadata(_ m: AddonManifest) -> Bool {
        m.id == aioMetadataID || folded(m.name).contains("aiometadata")
    }

    /// An addon whose `subtitles` route is a watch tracker: AIOMetadata offers `subtitles` when its watch tracking is
    /// on, and a subtitle request there marks the title as watched and scrobbles it to the user's tracking services.
    /// The app does its own tracking (user decision), so it never asks such an addon for subtitles.
    public static func isWatchTracker(_ m: AddonManifest) -> Bool { isAIOMetadata(m) }

    /// Lower case without blanks, dashes and underscores („AIO Metadata“ → „aiometadata“).
    static func folded(_ s: String) -> String {
        String(s.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" })
    }
}

/// Wave W-a: error item instead of a meta (AIOStreams/AIOMetadata send one with an error ID instead of an HTTP error).
public struct AddonNoticeError: Error, Equatable, Sendable {
    public var text: String
    public init(_ text: String) { self.text = text }
}

/// Wave W-a: one catalog answer after cleaning: readable items, how many were skipped, error items as text.
public struct AddonCatalogPage: Equatable, Sendable {
    public var items: [MetaPreview]
    /// Entries that could not be read (no `id`, not an object, …).
    public var skipped: Int
    /// Error items (`AddonNotices.isErrorItem`), as short text; they are not in `items`.
    public var notices: [String]

    public init(items: [MetaPreview], skipped: Int = 0, notices: [String] = []) {
        self.items = items; self.skipped = skipped; self.notices = notices
    }

    /// Readable items of a catalog of `type`: a missing item type becomes the catalog's type, error items move to
    /// `notices`.
    public init(decoded: [MetaPreview], skipped: Int, catalogType: String) {
        var items: [MetaPreview] = [], notices: [String] = []
        for var m in decoded {
            if AddonNotices.isErrorItem(id: m.id) {
                notices.append(AddonNotices.text(name: m.name, description: m.description, id: m.id))
                continue
            }
            if m.type.isEmpty { m.type = catalogType }
            items.append(m)
        }
        self.init(items: items, skipped: skipped, notices: notices)
    }

    /// „2 unlesbare Einträge übersprungen · 1 Fehlereintrag: …“; nil when nothing was dropped.
    public var logNote: String? {
        var parts: [String] = []
        if skipped > 0 { parts.append(AddonNotices.skippedText(skipped)) }
        if !notices.isEmpty {
            let head = notices.count == 1 ? "1 Fehlereintrag" : "\(notices.count) Fehlereinträge"
            parts.append(head + ": " + notices.prefix(3).joined(separator: " · ") + (notices.count > 3 ? " · …" : ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
