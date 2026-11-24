import Foundation

/// Task 4.2: how a `Look` comes into being for a profile from before Build 4, and schema upgrades.
public enum LookMigration {
    /// Upgrades a look read with schema `version` to `LookSchema.current`. Schema 1 is the only one so far; a higher
    /// version is read like a known one (unknown fields were already ignored while decoding), so this is the
    /// identity. A future rename adds one step here, with a test.
    public static func upgrade(_ look: Look, from version: Int) -> Look { look }
}

extension Look {
    /// Builds the look of an old profile (no `look` field yet) from its existing fields, as overrides against
    /// "Mein Look" (`.appleTV`). Mapping (04-system-design §8.2.4):
    /// navigation sidebar/top → seitenleiste/oben; accent blue/purple/pink/orange/green/white →
    /// blau/violett/koralle/koralle/salbei/weiss; cardSize small/medium/large → klein/mittel/gross;
    /// heroEnabled false → heroStyle aus; expandPosters as is; badges.style text/logo → text/logos;
    /// trackPanelStyle topBar/bottomBar/menu → seite/unten/mitte. `sources` holds content settings only
    /// (`appBadges` stays its own field), so nothing of it moves into the look.
    /// Changing this table changes every profile without a written look (those are rebuilt from it on every read).
    public static func migrated(from appearance: Appearance, player: PlayerComfortSettings,
                                sources: SourceSettings) -> Look {
        var v = LookPreset.values(.appleTV)
        v.global.navigation = switch appearance.navigation {
        case .sidebar: .seitenleiste
        case .top: .oben
        }
        v.global.accent = switch appearance.accent {
        case .blue: .blau
        case .purple: .violett
        case .pink, .orange: .koralle
        case .green: .salbei
        case .white: .weiss
        }
        v.home.cardSize = switch appearance.cardSize {
        case .small: .klein
        case .medium: .mittel
        case .large: .gross
        }
        if !appearance.heroEnabled { v.home.heroStyle = .aus }
        v.home.expandPosters = appearance.expandPosters
        v.detail.badgeStyle = switch appearance.badges.style {
        case .text: .text
        case .logo: .logos
        }
        v.player.trackPanel = switch player.trackPanelStyle {
        case .topBar: .seite
        case .bottomBar: .unten
        case .menu: .mitte
        }
        let base = LookPreset.values(.appleTV)
        return Look(preset: .appleTV, overrides: LookOverrides.difference(v, from: base))
    }
}
