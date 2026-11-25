import Foundation

// Task 5.3 (Build 5b): the detail page options as pure rules. The app only draws what these return.

// MARK: - Profile-owned extras (ruling 24.11.)

/// „Folgen“: episodes as a horizontal row of cards (default) or as today's list.
public enum LookEpisodes: String, LookOption { case reihe, liste }

/// „Titel oben“: the title logo replaces the poster (default), or always the poster (today).
public enum LookTitleArt: String, LookOption { case logo, poster }

/// Task 5.3: the two detail options of the user's device test (23.11.) that the configurator does not have. Ruling
/// 24.11.: they belong to the profile (`Profile.detailExtras`), outside `LookValues`, so `export.json`, the preset
/// "Mein Look" and the import stay unchanged. Missing in older profiles → defaults; an unknown value falls back
/// alone and is noted. Written only when it differs from the defaults (an untouched profile keeps its bytes).
public struct LookDetailExtras: Codable, Sendable, Hashable {
    public var episodes: LookEpisodes
    public var titleArt: LookTitleArt

    public init(episodes: LookEpisodes = .reihe, titleArt: LookTitleArt = .logo) {
        self.episodes = episodes; self.titleArt = titleArt
    }

    enum CodingKeys: String, CodingKey { case episodes, titleArt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = DecodeReportBox.of(decoder)
        let d = LookDetailExtras()
        episodes = c.decodeLenient(LookEpisodes.self, forKey: .episodes, default: d.episodes, report: r)
        titleArt = c.decodeLenient(LookTitleArt.self, forKey: .titleArt, default: d.titleArt, report: r)
    }

    /// Raw value of a row key (`episodes`, `titleArt`), `nil` for other keys.
    public func rawValue(_ key: String) -> String? {
        switch key {
        case "episodes": episodes.rawValue
        case "titleArt": titleArt.rawValue
        default: nil
        }
    }

    /// Sets a row key from its raw value (`nil` = default). False for an unknown key or value (nothing changes).
    @discardableResult
    public mutating func set(_ key: String, to raw: String?) -> Bool {
        let d = LookDetailExtras()
        switch key {
        case "episodes":
            guard let v = raw.map({ LookEpisodes(rawValue: $0) }) ?? d.episodes else { return false }
            episodes = v
        case "titleArt":
            guard let v = raw.map({ LookTitleArt(rawValue: $0) }) ?? d.titleArt else { return false }
            titleArt = v
        default:
            return false
        }
        return true
    }
}

// MARK: - Layout

/// One stop of a picture shade: `location` 0…1 from the edge the shade starts at, `opacity` of `bg.base`.
public struct DetailShadeStop: Sendable, Hashable {
    public var location: Double
    public var opacity: Double
    public init(_ location: Double, _ opacity: Double) { self.location = location; self.opacity = opacity }
}

/// A shade over the backdrop, always in the background tone (never pure black, 07 §3.1).
public enum DetailShade: Sendable, Hashable {
    /// From the bottom edge upwards.
    case fromBottom([DetailShadeStop])
    /// From the leading edge to the right.
    case fromLeading([DetailShadeStop])

    /// `image.gradient.leading`: 92 % → 55 % → 0 % at 0 → 38 % → 70 % of the width.
    public static let leading = DetailShade.fromLeading([.init(0, 0.92), .init(0.38, 0.55), .init(0.70, 0)])
    /// `image.gradient.bottom`: 0 % → 75 % → 100 % at 55 % → 78 % → 100 % of the height (here from the bottom).
    public static let bottom = DetailShade.fromBottom([.init(0, 1.0), .init(0.22, 0.75), .init(0.45, 0)])
}

/// Horizontal placement of the head block.
public enum DetailAlignment: String, Sendable, Hashable { case leading, center }

/// Measures of one `detail.layout` value (plan Task 5.3, configurator scene "Detailseite").
public struct DetailLayoutSpec: Sendable, Hashable {
    public var variant: LookDetailLayout
    public var alignment: DetailAlignment
    public var leadingInset: Double
    public var trailingInset: Double
    /// Width of the info block (title, meta, ratings, badges, description, buttons).
    public var infoWidth: Double
    /// Distance of the info block from the bottom edge when it is anchored there (`anchorsBottom`).
    public var bottomInset: Double
    /// Kino: the head fills the first screen and its info sits at the bottom over the picture.
    public var anchorsBottom: Bool
    /// Width of the cast row (`nil` = the page width).
    public var castWidth: Double?
    public var shades: [DetailShade]
}

public enum DetailLook {
    /// The layout of a `detail.layout` value. `contentLeading` = `LookMetrics.contentLeading(navigation)`.
    public static func layout(_ l: LookDetailLayout, contentLeading: Double) -> DetailLayoutSpec {
        switch l {
        case .links:
            DetailLayoutSpec(variant: .links, alignment: .leading, leadingInset: contentLeading, trailingInset: 80,
                             infoWidth: 1100, bottomInset: 0, anchorsBottom: false, castWidth: nil,
                             shades: [DetailShade.leading, DetailShade.bottom])
        case .zentriert:
            DetailLayoutSpec(variant: .zentriert, alignment: .center, leadingInset: 260, trailingInset: 260,
                             infoWidth: 1100, bottomInset: 0, anchorsBottom: false, castWidth: 860,
                             shades: [.fromBottom([.init(0, 1.0), .init(0.45, 0.8), .init(1.0, 0.25)])])
        case .kino:
            DetailLayoutSpec(variant: .kino, alignment: .leading, leadingInset: contentLeading, trailingInset: 80,
                             infoWidth: 900, bottomInset: 70, anchorsBottom: true, castWidth: nil,
                             shades: [.fromBottom([.init(0, 0.96), .init(0.30, 0.5), .init(0.55, 0)])])
        }
    }

    /// Lines of the description shown at once; the cinema layout keeps it at most 3 over the picture.
    public static func descriptionLineLimit(_ lines: LookDescriptionLines, layout: LookDetailLayout) -> Int {
        let n = LookMetrics.descriptionLines(lines)
        return layout == .kino ? min(n, 3) : n
    }

    /// `cast = text`: „Mit A, B, C“ (at most `limit` names, one line); `nil` without names.
    public static func castLine(_ names: [String], limit: Int = 5) -> String? {
        let shown = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(limit)
        return shown.isEmpty ? nil : "Mit " + shown.joined(separator: ", ")
    }

    /// The badge style drawn: the player shows `logos` as `gefuellt` (plan Task 5.3).
    public static func badgeStyle(_ style: LookBadgeStyle, inPlayer: Bool) -> LookBadgeStyle {
        inPlayer && style == .logos ? .gefuellt : style
    }

    /// The rating style drawn: the cinema layout shows tiles as symbols (configurator), the info block stays low.
    public static func ratingStyle(_ style: LookRatingStyle, layout: LookDetailLayout) -> LookRatingStyle {
        layout == .kino && style == .kacheln ? .symbole : style
    }

    /// Name of a rating source written out (`ratingStyle` text and tiles): „Tomatometer“ instead of „🍅“.
    public static func ratingName(_ r: RatingBadge) -> String {
        switch r.source {
        case "tomatoes": "Tomatometer"
        case "popcorn": "Popcornmeter"
        default: r.label
        }
    }

    /// `ratingStyle = text`: „IMDb 7,9   Tomatometer 92 %   Trakt 81 %“; `nil` without ratings.
    public static func ratingLine(_ ratings: [RatingBadge]) -> String? {
        let parts = ratings.map { ratingName($0) + " " + $0.displayValue }
        return parts.isEmpty ? nil : parts.joined(separator: "   ")
    }

    /// `episodes = reihe`: the episode the row of a season starts at (scrolled to on entry and on a season change):
    /// the first unwatched one, else the first. `episodes` are the season's episodes in order.
    public static func episodeRowStart(_ episodes: [EpisodeRef], isWatched: (EpisodeRef) -> Bool) -> EpisodeRef? {
        episodes.first { !isWatched($0) } ?? episodes.first
    }

    /// `titleArt`: what the head shows (see `DetailTitleArt`).
    public static func titleArt(_ choice: LookTitleArt, logo: String?) -> DetailTitleArt {
        let logo = logo.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        switch choice {
        case .logo: return DetailTitleArt(logo: logo, showsPoster: logo == nil)
        case .poster: return DetailTitleArt(logo: logo, showsPoster: true)
        }
    }
}

/// What the head of the detail page shows: the title logo (else the title as text) and whether the poster stands
/// next to the info block. `logo`: the logo takes the poster's place; without a logo the poster comes back.
/// `poster`: always the poster (today's page, a logo still replaces the text title).
public struct DetailTitleArt: Sendable, Hashable {
    public var logo: String?
    public var showsPoster: Bool
    public init(logo: String?, showsPoster: Bool) { self.logo = logo; self.showsPoster = showsPoster }
}
