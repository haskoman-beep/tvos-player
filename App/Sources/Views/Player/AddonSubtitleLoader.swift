import SwiftUI
import PlayerCore

/// Player-4: Untertitel aus Stremio-Addons (Ressource `subtitles`, z. B. OpenSubtitles v3).
/// Die Addons kommen vom Nutzer; ist keines mit Untertiteln installiert, passiert nichts.
@MainActor
enum AddonSubtitleLog {
    static var reportedNoAddon = false
}

extension AppModel {
    /// Untertitel aller passenden Addons für den Titel; nil, wenn `enabled` false ist (Trailer)
    /// oder kein Untertitel-Addon installiert ist (einmal geloggt).
    func addonSubtitles(for request: PlayRequest, enabled: Bool = true) async -> [AddonSubtitle]? {
        guard enabled else { return nil }
        guard AddonClient.hasSubtitleAddon(profile.addons) else {
            if !AddonSubtitleLog.reportedNoAddon {
                AddonSubtitleLog.reportedNoAddon = true
                RemoteLog.info("player", "Addon-UT: kein Untertitel-Addon installiert")
            }
            return nil
        }
        return await addons.subtitles(from: profile.addons, type: request.type, id: request.id)
    }
}

extension PlayerControls {
    /// Nach dem Laden im Hintergrund: Addon-Untertitel in UT-Sprache, Tonsprache und Englisch (je höchstens 3) anhängen.
    /// Fehlt eine eingebettete Spur in der Wunschsprache und sind Untertitel gewünscht, die erste passende Addon-Spur wählen.
    func loadAddonSubtitles() async {
        guard let addonSubtitles else { return }
        let selectedBefore = engine.activeSubtitleID
        let embedded = engine.subtitleTracks
        guard let found = await addonSubtitles() else { return }
        let audioLanguage = engine.audioTracks.first { $0.id == engine.activeAudioID }?.language
        let languages = AddonSubtitlePlan.languages(subtitleLanguage: profile.subtitleLanguage, audioLanguage: audioLanguage)
        let picked = AddonSubtitlePlan.select(found, languages: languages)
        var added: [(sub: AddonSubtitle, id: Int)] = []
        for (sub, name) in zip(picked, AddonSubtitlePlan.trackNames(picked)) {
            guard let url = URL(string: sub.url),
                  let id = engine.addExternalSubtitle(url: url, name: name, language: sub.languageCode, formatHint: sub.formatHint)
            else { continue }
            added.append((sub, id))
        }
        var addedLanguages: [String] = []
        for a in added { if let c = a.sub.languageCode, !addedLanguages.contains(c) { addedLanguages.append(c) } }
        RemoteLog.info("player", "Addon-UT: \(found.count) gefunden, \(added.count) hinzugefügt (Sprachen " +
            "\(addedLanguages.isEmpty ? "-" : addedLanguages.joined(separator: ", ")); gesucht \(languages.joined(separator: ", ")))")
        // CONTROLLER (Player-1): `profile.subtitlesEnabled` durch „SubtitleMode == immer“ ersetzen.
        guard let first = AddonSubtitlePlan.autoSelect(added.map(\.sub), subtitlesWanted: profile.subtitlesEnabled,
                                                       wishLanguage: profile.subtitleLanguage, embedded: embedded),
              let id = added.first(where: { $0.sub == first })?.id else { return }
        // Inzwischen von Hand (oder von der Engine) gewählt: nicht überschreiben.
        guard engine.activeSubtitleID == selectedBefore else { return }
        engine.selectSubtitle(id)
        RemoteLog.info("player", "Addon-UT gewählt: \(id) · \(first.addonName) · \(first.languageCode ?? "?")")
    }
}
