import Foundation

/// Wave Q: filter chips above the source list. A chip appears only for a quality or feature that some but not all
/// sources have (a chip that keeps or drops every row filters nothing); a selected chip always stays. The filter
/// is a view over the list: ranking, autostart, fallback and the next episode keep working on the full list.
public enum SourceFilterChip: Hashable, Sendable, Identifiable {
    /// Resolution as `StreamTraits.resolution` names it ("2160p", "1080p", …).
    case resolution(String)
    case dolbyVision
    /// HDR10, HDR10+, HDR or HLG (a DV-only source does not count).
    case hdr
    case atmos
    case remux
    case german
    case cached
    case size(SourceSizeBucket)

    public var id: String {
        switch self {
        case .resolution(let r): "res.\(r)"
        case .dolbyVision: "dv"
        case .hdr: "hdr"
        case .atmos: "atmos"
        case .remux: "remux"
        case .german: "de"
        case .cached: "cached"
        case .size(let b): "size.\(b.rawValue)"
        }
    }

    /// German UI label.
    public var label: String {
        switch self {
        case .resolution(let r): r == "2160p" ? "4K" : r
        case .dolbyVision: "Dolby Vision"
        case .hdr: "HDR"
        case .atmos: "Atmos"
        case .remux: "REMUX"
        case .german: "Deutsch"
        case .cached: "Sofort bereit"
        case .size(let b): b.label
        }
    }

    /// Chips of one group exclude each other (one resolution, one size range); the others combine.
    public var group: String {
        switch self {
        case .resolution: "res"
        case .size: "size"
        default: id
        }
    }

    public func matches(_ t: StreamTraits) -> Bool {
        switch self {
        case .resolution(let r): t.resolution == r
        case .dolbyVision: t.hdr.contains("DV")
        case .hdr: t.hdr.contains { $0 != "DV" }
        case .atmos: t.audio.contains("Atmos")
        case .remux: t.source == "REMUX"
        case .german: t.languages.contains("de")
        case .cached: t.cached == true
        case .size(let b): t.sizeBytes.map(b.contains) ?? false
        }
    }
}

public enum SourceSizeBucket: String, CaseIterable, Sendable {
    case small, medium, large

    static let gb: Int64 = 1_000_000_000

    public var label: String {
        switch self {
        case .small: "unter 5 GB"
        case .medium: "5–20 GB"
        case .large: "über 20 GB"
        }
    }

    public func contains(_ bytes: Int64) -> Bool {
        guard bytes > 0 else { return false }
        switch self {
        case .small: return bytes < 5 * Self.gb
        case .medium: return bytes >= 5 * Self.gb && bytes <= 20 * Self.gb
        case .large: return bytes > 20 * Self.gb
        }
    }
}

public struct SourceFilterOption: Hashable, Sendable, Identifiable {
    public let chip: SourceFilterChip
    /// Sources with this trait in the whole list (not narrowed by the other chips).
    public let count: Int
    public var id: String { chip.id }
}

public enum SourceFilter {
    static let resolutionOrder = ["2160p", "1440p", "1080p", "720p", "480p"]

    /// Chips in a fixed order: resolutions high to low, picture, sound, source, language, cache, size small to large.
    public static func options(_ traits: [StreamTraits], selected: Set<SourceFilterChip> = []) -> [SourceFilterOption] {
        let all: [SourceFilterChip] = resolutionOrder.map { .resolution($0) }
            + [.dolbyVision, .hdr, .atmos, .remux, .german, .cached]
            + SourceSizeBucket.allCases.map { .size($0) }
        return all.compactMap { chip in
            let n = traits.reduce(0) { $0 + (chip.matches($1) ? 1 : 0) }
            let useful = n > 0 && n < traits.count
            return useful || selected.contains(chip) ? SourceFilterOption(chip: chip, count: n) : nil
        }
    }

    /// Select or clear a chip; selecting replaces another chip of the same group.
    public static func toggle(_ chip: SourceFilterChip, in selected: Set<SourceFilterChip>) -> Set<SourceFilterChip> {
        if selected.contains(chip) { return selected.subtracting([chip]) }
        return selected.filter { $0.group != chip.group }.union([chip])
    }

    /// Selected chips that the current list still offers (a new episode may lack one).
    public static func effective(_ selected: Set<SourceFilterChip>, options: [SourceFilterOption]) -> Set<SourceFilterChip> {
        selected.intersection(options.map(\.chip))
    }

    /// True if the source passes every selected chip.
    public static func passes(_ t: StreamTraits, _ selected: Set<SourceFilterChip>) -> Bool {
        selected.allSatisfy { $0.matches(t) }
    }
}

extension SourceFocus {
    /// Wave Q: while results arrive the focus keeps its row position instead of following its source to a new
    /// place (new sources sort in above it). Returns the id now at the old position, or nil when nothing needs
    /// to change (no focus, same place, focus not in the old list). A list that got shorter puts it on the last row.
    public static func keepPosition(focused: String?, old: [String], new: [String]) -> String? {
        guard let focused, let i = old.firstIndex(of: focused), !new.isEmpty else { return nil }
        if new.firstIndex(of: focused) == i { return nil }
        let id = new[min(i, new.count - 1)]
        return id == focused ? nil : id
    }
}
