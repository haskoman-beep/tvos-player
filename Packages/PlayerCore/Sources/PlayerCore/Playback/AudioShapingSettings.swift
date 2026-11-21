import Foundation

/// Ton-Einstellungen des Profils für die Engine (ohne Engine-Typ, damit testbar). Standard: alles aus,
/// dann lädt die Engine genau wie ohne diese Einstellungen (Durchreichen von 5.1/Atmos unverändert).
///
/// Formung (Nachtmodus, Dialog, Lautheit) braucht dekodierten Ton: solange sie an ist, wird eine
/// durchgereichte Spur (Dolby Digital, Atmos, DTS) dekodiert und neu kodiert. Der Ton-Versatz ändert
/// den Weg nicht.
public struct AudioShapingSettings: Codable, Sendable, Equatable {
    /// Brücke für Formate, die nicht durchgereicht werden können (TrueHD, DTS-HD, Opus …).
    public enum Bridge: String, Codable, Sendable, CaseIterable {
        /// E-AC-3 (Dolby Digital Plus): Surround auch über optisch/ARC. Standard der Engine.
        case surroundCompat
        /// FLAC bis 7.1 als PCM: nur über HDMI an einen AV-Receiver oder eARC.
        case lossless
    }

    /// Nachtmodus: leise Stellen lauter, laute leiser (Kompressor der Engine).
    public var nightMode: Bool
    /// Dialog-Anhebung in dB (0 = aus).
    public var dialogueBoostDB: Int
    /// Lautheitsziel in LUFS (0 = aus), hebt leise Quellen an.
    public var loudnessTargetLUFS: Int
    /// Ton-Versatz in Millisekunden (positiv = Ton später).
    public var audioDelayMs: Int
    public var bridge: Bridge
    /// „Stereo (sicher)“: jede Spur als Stereo (Engine-Kanalgrenze 2). Für Lautsprecher, die Surround falsch
    /// oder gar nicht wiedergeben; dekodiert wie die Formung jede durchgereichte Spur.
    public var safeStereo: Bool

    public static let dialogueChoices = [0, 3, 6, 9]
    public static let loudnessChoices = [0, -24, -20, -16]
    /// Versatz-Stufen; die Engine nimmt höchstens ±2 s.
    public static let delayChoices = [-500, -400, -300, -250, -200, -150, -100, -75, -50, -25, 0,
                                      25, 50, 75, 100, 150, 200, 250, 300, 400, 500]
    public static let maxDelayMs = 2000
    /// Obergrenze der Engine für die Dialog-Anhebung.
    public static let maxDialogueDB = 12

    public init(nightMode: Bool = false, dialogueBoostDB: Int = 0, loudnessTargetLUFS: Int = 0,
                audioDelayMs: Int = 0, bridge: Bridge = .surroundCompat, safeStereo: Bool = false) {
        self.nightMode = nightMode; self.dialogueBoostDB = dialogueBoostDB
        self.loudnessTargetLUFS = loudnessTargetLUFS; self.audioDelayMs = audioDelayMs; self.bridge = bridge
        self.safeStereo = safeStereo
    }

    enum CodingKeys: String, CodingKey { case nightMode, dialogueBoostDB, loudnessTargetLUFS, audioDelayMs, bridge, safeStereo }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AudioShapingSettings()
        nightMode = try c.decodeIfPresent(Bool.self, forKey: .nightMode) ?? d.nightMode
        dialogueBoostDB = try c.decodeIfPresent(Int.self, forKey: .dialogueBoostDB) ?? d.dialogueBoostDB
        loudnessTargetLUFS = try c.decodeIfPresent(Int.self, forKey: .loudnessTargetLUFS) ?? d.loudnessTargetLUFS
        audioDelayMs = try c.decodeIfPresent(Int.self, forKey: .audioDelayMs) ?? d.audioDelayMs
        // Unbekannter Wert (neuere Version) → Standard statt Profil verwerfen.
        bridge = (try? c.decodeIfPresent(Bridge.self, forKey: .bridge)) ?? d.bridge
        safeStereo = try c.decodeIfPresent(Bool.self, forKey: .safeStereo) ?? d.safeStereo
    }

    /// Dialog-Anhebung in dB, auf 0…12 begrenzt.
    public var dialogueGain: Double { Double(min(max(dialogueBoostDB, 0), Self.maxDialogueDB)) }
    /// Lautheitsziel oder nil (aus); nur −36…−12 LUFS gelten.
    public var loudnessTarget: Double? {
        (-36 ... -12).contains(loudnessTargetLUFS) ? Double(loudnessTargetLUFS) : nil
    }
    /// Versatz in Sekunden, auf ±2 s begrenzt.
    public var audioDelaySeconds: Double {
        Double(min(max(audioDelayMs, -Self.maxDelayMs), Self.maxDelayMs)) / 1000
    }

    /// „eARC/AVR vorhanden“: Empfänger nimmt Mehrkanal-PCM, die Brücke liefert verlustfrei.
    public var hasEARCReceiver: Bool {
        get { bridge == .lossless }
        set { bridge = newValue ? .lossless : .surroundCompat }
    }

    /// Kanalgrenze für die Engine (nil = Quelle unverändert).
    public var maxChannels: Int? { safeStereo ? 2 : nil }

    /// true = die Engine formt den Ton (dekodiert dann jede durchgereichte Spur).
    public var shapesAudio: Bool { nightMode || dialogueGain > 0 || loudnessTarget != nil || safeStereo }

    /// Kurztext fürs Log.
    public var logText: String {
        var parts: [String] = []
        if nightMode { parts.append("Nacht") }
        if dialogueGain > 0 { parts.append("Dialog +\(Int(dialogueGain)) dB") }
        if let l = loudnessTarget { parts.append("Lautheit \(Int(l)) LUFS") }
        if audioDelayMs != 0 { parts.append("Versatz \(Int(audioDelaySeconds * 1000)) ms") }
        if bridge != .surroundCompat { parts.append("Brücke \(bridge.rawValue)") }
        if safeStereo { parts.append("Stereo (sicher)") }
        return parts.isEmpty ? "aus" : parts.joined(separator: ", ")
    }
}
