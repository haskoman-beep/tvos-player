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
        var extra: [String: String] = [:]
        // Höchstens 8 s für den Hash, dann ohne fragen.
        // `try?` glättet das doppelte Optional: nil bei Zeitablauf oder ohne Hash.
        if let media, let h = try? await AddonClient.withTimeout(8, { await VideoHash.fetch(media, headers: headers) }) {
            extra = OpenSubtitlesHash.extras(hash: h.hash, size: h.size)
            RemoteLog.info("player", "Addon-UT: Datei-Hash \(h.hash) · \(h.size) B")
        }
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
