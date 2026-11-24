import Foundation

/// Task 4.2: the values of each preset. "Mein Look" (`.appleTV`) is exactly `docs/design/konfigurator/export.json`
/// (configurator preset "appletv"); `configuratorExportMatchesAppleTVPreset` keeps code and file equal.
public enum LookPreset {
    public static func values(_ id: LookPresetID) -> LookValues {
        switch id {
        case .appleTV: appleTV
        }
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
