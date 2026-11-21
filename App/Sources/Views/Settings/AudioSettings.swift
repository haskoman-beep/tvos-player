import SwiftUI
import PlayerCore

/// „Ton“: Nachtmodus, Dialog-Anhebung, Lautheit, Ton-Versatz, Brücke (Welle C-c). Gilt ab dem nächsten Start.
struct AudioShapingSettingsRows: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Nachtmodus (leise Stellen lauter, laute leiser)", isOn: model.binding(\.audioShaping.nightMode))
        Picker("Dialog anheben", selection: model.binding(\.audioShaping.dialogueBoostDB)) {
            ForEach(AudioShapingSettings.dialogueChoices, id: \.self) { Text($0 == 0 ? "Aus" : "+\($0) dB").tag($0) }
        }
        Picker("Lautheit angleichen", selection: model.binding(\.audioShaping.loudnessTargetLUFS)) {
            ForEach(AudioShapingSettings.loudnessChoices, id: \.self) { v in
                Text(v == 0 ? "Aus" : "\(v) LUFS\(v == -24 ? " (Fernsehen)" : v == -16 ? " (laut)" : "")").tag(v)
            }
        }
        if model.profile.audioShaping.shapesAudio {
            Text("Ton-Formung an: Dolby Digital, Atmos und DTS werden dekodiert und neu kodiert statt durchgereicht.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Picker("Ton-Versatz", selection: model.binding(\.audioShaping.audioDelayMs)) {
            ForEach(AudioShapingSettings.delayChoices, id: \.self) { v in
                Text(v == 0 ? "0 ms" : v > 0 ? "+\(v) ms (Ton später)" : "\(v) ms (Ton früher)").tag(v)
            }
        }
        Toggle("eARC/AV-Receiver vorhanden", isOn: model.binding(\.audioShaping.hasEARCReceiver))
        Text(model.profile.audioShaping.hasEARCReceiver
             ? "TrueHD/DTS-HD verlustfrei als Mehrkanal-PCM. Nur mit eARC oder HDMI-Receiver; über optisch oder einfaches ARC wird daraus Stereo."
             : "TrueHD/DTS-HD als Dolby Digital Plus 5.1: Surround auch über optisch und einfaches ARC (bisheriges Verhalten).")
            .font(.caption).foregroundStyle(.secondary)
        Toggle("Stereo (sicher)", isOn: model.binding(\.audioShaping.safeStereo))
        if model.profile.audioShaping.safeStereo {
            Text("Jede Tonspur wird als Stereo ausgegeben, auch Dolby Digital und Atmos. Für Lautsprecher, die Surround nicht richtig wiedergeben.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// „Bild“: Dolby-Vision-Angabe, FEL, HDMI-Modus zwischen Folgen halten (Welle C-c). Gilt ab dem nächsten Start.
struct DisplayModeSettingsRows: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Fernseher kann Dolby Vision (fest angeben)", isOn: model.binding(\.displayMode.panelPresentsDolbyVision))
        Text("Nur einschalten, wenn Dolby Vision trotz passendem Fernseher nicht erkannt wird. Normalerweise meldet tvOS das selbst.")
            .font(.caption).foregroundStyle(.secondary)
        Toggle("Dolby Vision FEL einrechnen", isOn: model.binding(\.displayMode.foldsDolbyVisionFEL))
        Text("Wirkt erst, wenn die Engine mit der FEL-Erweiterung gebaut ist; sonst ohne Wirkung.")
            .font(.caption).foregroundStyle(.secondary)
        Toggle("HDMI-Modus zwischen Folgen halten", isOn: model.binding(\.displayMode.keepModeBetweenEpisodes))
        Text("Bei der nächsten Folge im gleichen Format schaltet der Fernseher nicht erst um (kein langes Schwarzbild).")
            .font(.caption).foregroundStyle(.secondary)
    }
}
