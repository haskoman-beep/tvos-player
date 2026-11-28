import Foundation

/// Task 4.2: one option of the look. The raw values are exactly those of the configurator
/// (schema `player.appearance.preset` version 1, plan appendix A). A raw value this build does not know never throws
/// out of a profile: `LookOverrides` reads it as `nil` (the preset applies) and notes the path in the `DecodeReport`.
public protocol LookOption: RawRepresentable, Codable, Sendable, Hashable, CaseIterable {}

// MARK: global

public enum LookNavigation: String, LookOption { case seitenleiste, oben }
public enum LookSettingsLayout: String, LookOption { case spalten, kacheln, liste }
public enum LookAccent: String, LookOption { case champagner, weiss, eisblau, blau, rot, koralle, salbei, violett }
public enum LookBackground: String, LookOption { case schwarz, graphit, tinte, warm }
public enum LookTypeScale: String, LookOption { case kompakt, standard, gross }
public enum LookTypeCharacter: String, LookOption { case neutral, editorial, technisch }
public enum LookMotion: String, LookOption { case aus, dezent, standard }

// MARK: home

public enum LookHeroStyle: String, LookOption { case vollbild, banner, karussell, aus }
public enum LookHeroInfo: String, LookOption { case minimal, standard, ausfuehrlich }
public enum LookHeroTitle: String, LookOption { case logo, text }
public enum LookCardShape: String, LookOption { case poster, querformat, mischung }
public enum LookCardSize: String, LookOption { case klein, mittel, gross }
public enum LookCorners: String, LookOption { case eckig, leicht, weich, rund }
public enum LookRowSpacing: String, LookOption { case eng, normal, luftig }
public enum LookRowTitle: String, LookOption { case dezent, standard, gross }
public enum LookCardTitles: String, LookOption { case immer, fokus, aus }
public enum LookFocusScale: String, LookOption { case keine, dezent, kraeftig }
public enum LookFocusBorder: String, LookOption { case keiner, weiss, akzent }
public enum LookFocusShadow: String, LookOption { case keiner, weich, tief }

// MARK: detail

public enum LookDetailLayout: String, LookOption { case links, zentriert, kino }
/// The configurator writes this one as a number (`"descriptionLines": 2`).
public enum LookDescriptionLines: Int, LookOption { case two = 2, three = 3, five = 5 }
public enum LookCast: String, LookOption { case kreise, karten, text, aus }
public enum LookBadgeStyle: String, LookOption { case umriss, gefuellt, text, logos }
public enum LookRatingStyle: String, LookOption { case symbole, text, kacheln }
public enum LookSourceList: String, LookOption { case klassisch, kompakt, ausfuehrlich, karten }

// MARK: player

public enum LookControlBar: String, LookOption { case minimal, standard, ausfuehrlich }
public enum LookPlayerBadges: String, LookOption { case aus, kompakt, voll }
public enum LookTimeDisplay: String, LookOption { case rest, gesamt, ende }
public enum LookTrackPanel: String, LookOption { case seite, unten, mitte }
public enum LookUpNext: String, LookOption { case karte, leiste, vollbild }
public enum LookStillWatching: String, LookOption { case dialog, karte }
