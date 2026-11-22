import SwiftUI
import PlayerCore

/// Kategorie 6 „Ton & Untertitel“ (§2.2): Sprache (Presets, E5), Anlage, Klang, Ton-Versatz.
struct AudioSettings: View {
    @EnvironmentObject var model: AppModel

    private let tint = SettingsCategory.audio.tint

    var body: some View {
        let p = model.profile
        let custom = AudioLanguageChoice.of(p.audioPriority) == .custom
        CategoryPage(.audio, summary: SettingsSummary.audio(audioPriority: p.audioPriority, subtitles: p.subtitleMode)) {
            SettingsSection("Sprache") {
                // E5: Voreinstellungen; ein alter, eigener Vorrang bleibt unverändert, bis eine Voreinstellung gewählt wird.
                SettingsChoiceRow(symbol: "waveform", tint: tint, title: "Tonsprache",
                                  detail: custom
                                      ? "Gespeichert: \(AudioLanguagePreset.describe(p.audioPriority)). Bleibt so, bis du eine andere Reihenfolge wählst."
                                      : "Welche Tonspur zuerst gewählt wird; bei „Quellen sortieren: Smart“ auch die Reihenfolge der Quellen.",
                                  detailAlwaysVisible: custom,
                                  options: AudioLanguageChoice.choices(for: p.audioPriority),
                                  selection: Binding(get: { AudioLanguageChoice.of(model.profile.audioPriority) },
                                                     set: { c in model.update { $0.audioPriority = c.apply(to: $0.audioPriority) } }),
                                  label: { $0.title })
                SettingsChoiceRow(symbol: "captions.bubble", tint: tint, title: "Untertitel",
                                  detail: "„Nur erzwungene“ zeigt Untertitel nur für fremdsprachige Stellen.",
                                  options: SubtitleMode.allCases, selection: model.binding(\.subtitleMode),
                                  label: SettingsSummary.subtitleModeName)
                SettingsChoiceRow(symbol: "character.bubble", tint: tint, title: "Untertitelsprache",
                                  detail: "Bevorzugte Sprache der Untertitel.",
                                  options: SubtitleLanguageChoice.codes(for: p.subtitleLanguage),
                                  selection: Binding(get: { model.profile.subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() },
                                                     set: { v in model.update { $0.subtitleLanguage = SubtitleLanguageChoice.apply(v, to: $0.subtitleLanguage) } }),
                                  label: SubtitleLanguageChoice.name)
            }
            SubtitleStyleSettingsRows()
            AudioShapingSettingsRows()
            SettingsFootnote("Ton-Einstellungen gelten ab dem nächsten Start der Wiedergabe.")
        }
    }
}

/// Anlage, Klang und Ton-Versatz (Welle C-c, F-a neu gegliedert). Gilt ab dem nächsten Start.
struct AudioShapingSettingsRows: View {
    @EnvironmentObject var model: AppModel

    private let tint = SettingsCategory.audio.tint

    var body: some View {
        let s = model.profile.audioShaping
        SettingsSection("Anlage") {
            SettingsChoiceRow(symbol: "hifispeaker", tint: tint, title: "Ton-Anlage",
                              detail: s.hasEARCReceiver
                                  ? "TrueHD/DTS-HD verlustfrei als Mehrkanal-PCM. Nur mit eARC oder HDMI-Receiver; über optisch oder einfaches ARC wird daraus Stereo."
                                  : "TrueHD/DTS-HD als Dolby Digital Plus 5.1: Surround auch über optisch und einfaches ARC.",
                              detailAlwaysVisible: true,
                              options: [false, true], selection: model.binding(\.audioShaping.hasEARCReceiver),
                              label: SettingsSummary.soundSystemName)
            SettingsToggleRow(symbol: "speaker.wave.2", tint: tint, title: "Immer Stereo",
                              detail: "Jede Tonspur als Stereo, auch Dolby Digital und Atmos. Für Lautsprecher, die Surround nicht richtig wiedergeben.",
                              reserveDetailSpace: false, isOn: model.binding(\.audioShaping.safeStereo))
        }
        SettingsSection("Klang") {
            SettingsToggleRow(symbol: "moon", tint: tint, title: "Nachtmodus",
                              detail: "Leise Stellen lauter, laute leiser.",
                              reserveDetailSpace: false, isOn: model.binding(\.audioShaping.nightMode))
            SettingsChoiceRow(symbol: "person.wave.2", tint: tint, title: "Dialog anheben",
                              detail: "Stimmen lauter gegenüber Musik und Effekten.",
                              options: AudioShapingSettings.dialogueChoices, selection: model.binding(\.audioShaping.dialogueBoostDB),
                              label: SettingsSummary.dialogueName)
            SettingsChoiceRow(symbol: "dial.medium", tint: tint, title: "Lautstärke angleichen",
                              detail: SettingsSummary.loudnessDetail(s.loudnessTargetLUFS),
                              options: AudioShapingSettings.loudnessChoices, selection: model.binding(\.audioShaping.loudnessTargetLUFS),
                              label: SettingsSummary.loudnessName)
            if s.shapesAudio {
                SettingsFootnote("Ton-Formung an: Dolby Digital, Atmos und DTS werden dekodiert und neu kodiert statt durchgereicht.")
            }
        }
        SettingsSection("Versatz") {
            SettingsChoiceRow(symbol: "timer", tint: tint, title: "Ton-Versatz",
                              detail: "Gleicht Ton und Bild an, wenn der Ton vor- oder nachläuft.",
                              options: AudioShapingSettings.delayChoices, selection: model.binding(\.audioShaping.audioDelayMs),
                              label: SettingsSummary.delayName)
        }
    }
}

/// „Bild“ (Welle C-c): HDMI-Modus halten (Wiedergabe & Bild) und Dolby Vision fest / FEL (System › Erweitert).
struct DisplayModeSettingsRows: View {
    enum Part { case basic, advanced }

    var part: Part
    var tint: Color
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch part {
        case .basic:
            SettingsToggleRow(symbol: "tv", tint: tint, title: "HDMI-Modus zwischen Folgen halten",
                              detail: "Bei der nächsten Folge im gleichen Format schaltet der Fernseher nicht erst um (kein langes Schwarzbild).",
                              reserveDetailSpace: false, isOn: model.binding(\.displayMode.keepModeBetweenEpisodes))
        case .advanced:
            SettingsToggleRow(symbol: "sparkles.tv", tint: tint, title: "Fernseher kann Dolby Vision (fest)",
                              detail: "Nur einschalten, wenn Dolby Vision trotz passendem Fernseher nicht erkannt wird. Normalerweise meldet tvOS das selbst.",
                              reserveDetailSpace: false, isOn: model.binding(\.displayMode.panelPresentsDolbyVision))
            SettingsToggleRow(symbol: "square.3.layers.3d", tint: tint, title: "Dolby Vision FEL einrechnen",
                              detail: "Wirkt erst, wenn die Engine mit der FEL-Erweiterung gebaut ist; sonst ohne Wirkung.",
                              reserveDetailSpace: false, isOn: model.binding(\.displayMode.foldsDolbyVisionFEL))
        }
    }
}
