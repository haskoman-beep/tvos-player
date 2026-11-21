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
    /// Mit `media` wird vorher der OpenSubtitles-Datei-Hash geholt (zwei 64-KiB-Range-Abrufe) und als Extra mitgeschickt.
    func addonSubtitles(for request: PlayRequest, media: URL? = nil, headers: [String: String] = [:],
                        enabled: Bool = true) async -> [AddonSubtitle]? {
        guard enabled else { return nil }
        guard AddonClient.hasSubtitleAddon(profile.addons) else {
            if !AddonSubtitleLog.reportedNoAddon {
                AddonSubtitleLog.reportedNoAddon = true
                RemoteLog.info("player", "Addon-UT: kein Untertitel-Addon installiert")
            }
            return nil
        }
        // Hash nur, wenn ein Addon genau diesen Titel bedient (sonst keine Range-Abrufe an die Quelle).
        guard profile.addons.contains(where: { $0.manifest.supports("subtitles", type: request.type, id: request.id) })
        else { return [] }
        var extra: [String: String] = [:]
        // Höchstens 4 s für den Hash, dann ohne fragen.
        // `try?` glättet das doppelte Optional: nil bei Zeitablauf oder ohne Hash.
        if let media, let h = try? await AddonClient.withTimeout(4, { await VideoHash.fetch(media, headers: headers) }) {
            extra = OpenSubtitlesHash.extras(hash: h.hash, size: h.size)
            RemoteLog.info("player", "Addon-UT: Datei-Hash \(h.hash) · \(h.size) B")
        }
        // Player verlassen oder neu geladen, während der Hash lief: keine Addon-Abfrage mehr.
        guard !Task.isCancelled else { return [] }
        return await addons.subtitles(from: profile.addons, type: request.type, id: request.id, extra: extra)
    }
}

/// OpenSubtitles-Hash der laufenden Datei über zwei Range-Abrufe (Anfang, Ende). Nur bei Antwort 206 mit
/// `Content-Range`; bei jeder Auffälligkeit nil (dann ohne Hash fragen). Es werden höchstens 2 × 64 KiB gelesen.
enum VideoHash {
    static func fetch(_ url: URL, headers: [String: String]) async -> (hash: String, size: Int64)? {
        guard OpenSubtitlesHash.isHashable(url) else { return nil }
        let n = Int64(OpenSubtitlesHash.chunkSize)
        guard let head = await range(url, headers, from: 0, to: n - 1),
              let size = OpenSubtitlesHash.totalSize(contentRange: head.contentRange), size >= n,
              let tail = await range(url, headers, from: size - n, to: size - 1),
              OpenSubtitlesHash.rangeStart(contentRange: tail.contentRange) == size - n,
              OpenSubtitlesHash.totalSize(contentRange: tail.contentRange) == size,
              let hash = OpenSubtitlesHash.compute(size: size, head: head.data, tail: tail.data) else { return nil }
        return (hash, size)
    }

    private static func range(_ url: URL, _ headers: [String: String], from: Int64, to: Int64) async -> (data: Data, contentRange: String?)? {
        var r = URLRequest(url: url, timeoutInterval: 8)
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        guard let res = try? await URLSession.shared.bytes(for: r) else { return nil }
        let (bytes, resp) = res
        defer { bytes.task.cancel() }   // Server ohne Range-Unterstützung: nie die ganze Datei laden
        guard let http = resp as? HTTPURLResponse, http.statusCode == 206 else { return nil }
        let want = Int(to - from + 1)
        var data = Data(); data.reserveCapacity(want)
        do {
            for try await b in bytes {
                data.append(b)
                if data.count >= want { break }
            }
        } catch { return nil }
        guard data.count == want else { return nil }
        return (data, http.value(forHTTPHeaderField: "Content-Range"))
    }
}

/// Vor einem Neuladen gemerkte externe (Addon-)UT-Spur. Die Spur-ID wird beim Neuanlegen neu vergeben,
/// darum zählen Name und Sprache (die Addon-Spur trägt keine URL in `AudioTrackInfo`).
struct ExternalSubtitleRestore {
    let name: String?
    let language: String?
    let byUser: Bool

    /// nil, wenn keine oder keine externe Spur aktiv war.
    init?(track: AudioTrackInfo?, byUser: Bool) {
        guard let track, track.isExternal else { return nil }
        name = track.name; language = track.language; self.byUser = byUser
    }

    func matches(name: String, language: String?) -> Bool {
        self.name == name && MediaLabels.languageCode(self.language) == MediaLabels.languageCode(language)
    }
}

extension PlayerControls {
    /// Nach dem Laden im Hintergrund: Addon-Untertitel in UT-Sprache, Tonsprache und Englisch (je höchstens 3) anhängen.
    /// Außer bei „Aus“ und ohne volle eingebettete Spur in der Wunschsprache wird die Wahl danach nach den
    /// Player-1-Regeln (`reconsiderSubtitles`, also `SubtitlePicker`) über alle Spuren neu bewertet; nach einer
    /// Nutzerwahl werden Spuren nur hinzugefügt. `audioLanguage` ist die Sprache der Start-Tonspur (die Tonwahl
    /// läuft asynchron). Mit `restore` (nach einem Neuladen) wird die zuvor aktive Addon-Spur wieder gewählt.
    func loadAddonSubtitles(audioLanguage: String?, restore: ExternalSubtitleRestore? = nil) async {
        guard let addonSubtitles else { return }
        let embedded = engine.subtitleTracks
        guard let found = await addonSubtitles(), !Task.isCancelled else { return }
        let languages = AddonSubtitlePlan.languages(subtitleLanguage: profile.subtitleLanguage, audioLanguage: audioLanguage)
        let picked = AddonSubtitlePlan.select(found, languages: languages)
        var added: [(sub: AddonSubtitle, id: Int)] = []
        var restoredID: Int?
        for (sub, name) in zip(picked, AddonSubtitlePlan.trackNames(picked)) {
            guard !Task.isCancelled else { return }
            guard let url = URL(string: sub.url),
                  let id = engine.addExternalSubtitle(url: url, name: name, language: sub.languageCode, formatHint: sub.formatHint)
            else { continue }
            added.append((sub, id))
            if restoredID == nil, restore?.matches(name: name, language: sub.languageCode) == true { restoredID = id }
        }
        var addedLanguages: [String] = []
        for a in added { if let c = a.sub.languageCode, !addedLanguages.contains(c) { addedLanguages.append(c) } }
        RemoteLog.info("player", "Addon-UT: \(found.count) gefunden, \(added.count) hinzugefügt (Sprachen " +
            "\(addedLanguages.isEmpty ? "-" : addedLanguages.joined(separator: ", ")); gesucht \(languages.joined(separator: ", ")))")
        // Nach dem Neuladen: die vorher aktive Addon-Spur wieder setzen (Nutzerwahl bleibt Nutzerwahl).
        if let restore, !Task.isCancelled {
            if let restoredID {
                if restore.byUser { engine.selectSubtitle(restoredID) } else { engine.autoSelectSubtitle(restoredID) }
                RemoteLog.info("player", "Addon-UT nach Neuladen wieder gewählt: \(restoredID) · \(restore.name ?? "?")")
                return
            }
            RemoteLog.info("player", "Addon-UT nach Neuladen nicht wiedergefunden: \(restore.name ?? "?")")
        }
        // Neu bewerten außer bei „Aus“ und ohne volle eingebettete Spur in der Wunschsprache (die bleibt vorn).
        // Ob eine Addon-Spur gewählt wird, entscheidet SubtitlePicker wie beim Start: „Immer“ volle Spur in
        // Wunsch-/Zweitsprache, „Nur erzwungene“ volle Spur nur bei fremdem Ton (sonst Forced in Tonsprache);
        // Nicht-SDH vor SDH, nie Kommentar. Hat der Nutzer im Panel gewählt (selectSubtitle setzt
        // subtitleChosenByUser), tut reconsiderSubtitles nichts: Spuren nur hinzugefügt.
        guard !added.isEmpty,
              AddonSubtitlePlan.shouldReconsider(mode: profile.subtitleMode, wishLanguage: profile.subtitleLanguage,
                                                 embedded: embedded),
              !Task.isCancelled else { return }
        guard let track = engine.reconsiderSubtitles(audioLanguage: audioLanguage)?.track,
              let chosen = added.first(where: { $0.id == track.id }) else { return }
        RemoteLog.info("player", "Addon-UT gewählt: \(chosen.id) · \(chosen.sub.addonName) · \(chosen.sub.languageCode ?? "?")")
    }
}
