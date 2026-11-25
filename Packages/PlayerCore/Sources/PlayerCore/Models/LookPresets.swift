import Foundation

/// Task 4.2: the values of each preset. "Mein Look" (`.appleTV`) is exactly `docs/design/konfigurator/export.json`
/// (configurator preset "appletv"); `configuratorExportMatchesAppleTVPreset` keeps code and file equal.
public enum LookPreset {
    public static func values(_ id: LookPresetID) -> LookValues {
        switch id {
        case .appleTV: appleTV
        }
    }

    /// Task 4.5-base (user decision 25.11.): the values an untouched profile shows, and what "changed" and "back to
    /// the default" mean on the settings page. The old default values are the baseline: "Mein Look" (`.appleTV`)
    /// plus the keys the old fields (`Appearance()`, `PlayerComfortSettings()`) set, exactly what
    /// `Look.migrated` resolves to for them. So a new profile, or a Build 3 profile nobody edited, shows "Standard"
    /// (no deviation), and only real changes by the user count. The stored format does not change: `look.overrides`
    /// stays relative to `.appleTV`, and a configurator import still writes its exact values.
    public static let baseline: LookValues =
        Look.migrated(from: Appearance(), player: PlayerComfortSettings(), sources: SourceSettings()).resolved()

    /// Task 4.5-base fix round 1 (I1): how many of the 35 options of `look` differ from `baseline`. The one count
    /// behind "angepasst · n" and the import notices ("Aussehen übernommen · n Abweichungen") on phone and TV.
    public static func baselineDeviationCount(_ look: Look) -> Int {
        LookOverrides.difference(look.resolved(), from: baseline).count
    }

    static let appleTV = LookValues(
        global: LookGlobal(navigation: .oben, clock: false, settingsLayout: .spalten, accent: .weiss,
                           background: .schwarz, typeScale: .standard, typeCharacter: .neutral, motion: .standard),
        home: LookHome(heroStyle: .vollbild, heroInfo: .minimal, heroTitle: .logo, backdropFollowsFocus: false,
                       cardShape: .querformat, cardSize: .gross, corners: .rund, rowSpacing: .luftig,
                       rowTitle: .standard, cardTitles: .immer, expandPosters: false, focusScale: .kraeftig,
                       focusBorder: .keiner, focusShadow: .tief, focusGlow: true),
        detail: LookDetail(layout: .kino, descriptionLines: .two, cast: .kreise, badgeStyle: .text,
                           ratingStyle: .text, sourceList: .kompakt),
        player: LookPlayer(controlBar: .minimal, badges: .aus, timeDisplay: .rest, trackPanel: .unten,
                           upNext: .karte, stillWatching: .dialog))
}
