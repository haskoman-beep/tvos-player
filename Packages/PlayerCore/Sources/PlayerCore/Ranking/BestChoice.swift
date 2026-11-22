import Foundation

/// Welle G-a: „Sofort abspielen / Beste Wahl“ auf der Detailseite. Ein Druck startet die beste Quelle ohne
/// Quellenliste. Reine Regeln; die App zeigt die Karte und startet über die Quellenliste (Fehlerleiter unverändert).
///
/// Wahl:
/// 1. Grundlage ist die automatische Ordnung (`StreamListOrder.automatic`, Welle C-d/E-b): Dubletten raus,
///    sicher ungecachte nach hinten, Wunschsprache vor, schweres AV1 ohne Hardware nach hinten.
/// 2. Nicht abspielbare (keine http(s)-Adresse) und im 8-h-Gedächtnis fehlgeschlagene Quellen fallen weg.
/// 3. Gibt es eine zuletzt gespielte Quelle (`LastSource`) in dieser Liste: „Weiter mit letzter Quelle“.
/// 4. Sonst innerhalb der besten Grundstufe (`SourceRanking.tier`) nach Technik, stabil (Addon-Reihenfolge bleibt
///    bei Gleichstand): sicher gecacht vor unbekannt, höhere Auflösung, kein schwaches AV1, Dolby Vision,
///    Mehrkanalton (5.1/7.1).
public enum BestChoice {
    public enum Reason: String, Sendable {
        /// Zuletzt gespielte Quelle dieses Titels.
        case lastSource
        /// Beste Quelle nach den Regeln oben.
        case best
    }

    public struct Pick: Equatable, Sendable {
        public var addon: String
        public var stream: StreamItem
        public var reason: Reason
        public init(addon: String, stream: StreamItem, reason: Reason) {
            self.addon = addon; self.stream = stream; self.reason = reason
        }
    }

    /// Text auf der Karte ohne abspielbare Quelle.
    public static let noSourceText = "Keine Quelle gefunden – Quellen ansehen"

    /// Beste Quelle oder nil (keine abspielbare, alle kürzlich fehlgeschlagen).
    /// `list` in beliebiger Reihenfolge (die automatische Ordnung wird hier gebildet).
    public static func pick(_ list: [(addon: String, stream: StreamItem)], context: SourceRankContext,
                            last: LastSource?, isFailed: (StreamItem) -> Bool) -> Pick? {
        let candidates = StreamListOrder.automatic(list, context: context)
            .filter { isPlayable($0.stream) && !isFailed($0.stream) }
        guard let first = candidates.first else { return nil }
        if let last, let s = last.match(in: candidates), let e = candidates.first(where: { $0.stream.id == s.id }) {
            return Pick(addon: e.addon, stream: e.stream, reason: .lastSource)
        }
        let top = SourceRanking.tier(StreamTraits.parse(first.stream), context: context)
        let tier = candidates.enumerated().compactMap { i, e -> (Int, (addon: String, stream: StreamItem), [Int])? in
            let t = StreamTraits.parse(e.stream)
            guard SourceRanking.tier(t, context: context) == top else { return nil }
            return (i, e, preference(t, context: context))
        }
        let best = tier.min { a, b in a.2 != b.2 ? a.2.lexicographicallyPrecedes(b.2) : a.0 < b.0 }!
        return Pick(addon: best.1.addon, stream: best.1.stream, reason: .best)
    }

    /// Kleiner = besser (innerhalb einer Grundstufe).
    static func preference(_ t: StreamTraits, context: SourceRankContext) -> [Int] {
        [t.cached == true ? 0 : 1,
         -resolutionRank(t.resolution),
         SourceRanking.isWeakAV1(t, av1Hardware: context.av1Hardware) ? 1 : 0,
         t.hdr.contains("DV") ? 0 : 1,
         ["7.1", "5.1"].contains(t.channels ?? "") ? 0 : 1]
    }

    static func resolutionRank(_ r: String?) -> Int {
        switch r {
        case "2160p": 5
        case "1440p": 4
        case "1080p": 3
        case "720p": 2
        case "480p": 1
        default: 0
        }
    }

    static func isPlayable(_ s: StreamItem) -> Bool {
        guard let u = s.url, let scheme = URL(string: u)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: Kartentext

    /// Überschrift der Karte: „Sofort abspielen“ bzw. „Weiter mit letzter Quelle“, mit Startstelle „ab 1:02:03“.
    public static func title(_ reason: Reason, resumeText: String? = nil) -> String {
        let base = reason == .lastSource ? "Weiter mit letzter Quelle" : "Sofort abspielen"
        guard let r = resumeText, !r.isEmpty else { return base }
        return base + " ab " + r
    }

    /// Was spielen wird, z. B. „4K DV · Deutsch 5.1 · 12,3 GB · TorBox ⚡“. Teile ohne Angabe fallen weg;
    /// ganz ohne Angaben der Name der Quelle (erste Zeile).
    public static func detail(_ s: StreamItem, primaryLanguage: String?) -> String {
        let t = StreamTraits.parse(s)
        var parts: [String] = []
        let video = [t.resolution.map(resolutionLabel), hdrLabel(t.hdr)].compactMap { $0 }.joined(separator: " ")
        if !video.isEmpty { parts.append(video) }
        let audio = [languageLabel(t.languages, primary: primaryLanguage), t.channels].compactMap { $0 }.joined(separator: " ")
        if !audio.isEmpty { parts.append(audio) }
        if let b = t.sizeBytes, b > 0 { parts.append(sizeLabel(b)) }
        if let svc = t.service {
            parts.append(serviceName(svc) + (t.cached == true ? " ⚡" : ""))
        } else if t.cached == true {
            parts.append(QualityBadges.cachedText)
        }
        if parts.isEmpty {
            let name = StreamRowText(s).name.components(separatedBy: "\n").first ?? ""
            return name.isEmpty ? "Beste Quelle" : name
        }
        return parts.joined(separator: " · ")
    }

    static func resolutionLabel(_ r: String) -> String { r == "2160p" ? "4K" : r }

    static func hdrLabel(_ hdr: [String]) -> String? {
        if hdr.contains("DV") { return "DV" }
        if hdr.contains("HDR10+") { return "HDR10+" }
        if hdr.contains("HDR10") || hdr.contains("HDR") { return "HDR" }
        if hdr.contains("HLG") { return "HLG" }
        return nil
    }

    /// Wunschsprache genannt → ihr Name; Multi → „Multi“; genau eine andere Sprache → deren Name; sonst nichts.
    static func languageLabel(_ langs: [String], primary: String?) -> String? {
        if let p = primary, langs.contains(p) { return MediaLabels.languageName(p) }
        if langs.contains("multi") { return "Multi" }
        let named = langs.filter { $0 != "multi" }
        if named.count == 1 { return MediaLabels.languageName(named[0]) }
        return nil
    }

    /// Eine Nachkommastelle wie in der Karte („12,3 GB“); MB ganzzahlig.
    static func sizeLabel(_ bytes: Int64) -> String {
        let v = Double(bytes)
        if v >= 1e12 { return DesignText.decimal(v / 1e12, fractionDigits: 1) + " TB" }
        if v >= 1e9 { return DesignText.decimal(v / 1e9, fractionDigits: 1) + " GB" }
        return DesignText.decimal(v / 1e6, fractionDigits: 0) + " MB"
    }

    static func serviceName(_ code: String) -> String {
        switch code {
        case "TB": "TorBox"
        case "RD": "Real-Debrid"
        case "AD": "AllDebrid"
        case "PM": "Premiumize"
        case "DL": "Debrid-Link"
        case "ED": "EasyDebrid"
        case "OC": "Offcloud"
        case "PKP": "PikPak"
        case "NZB": "Usenet"
        default: code
        }
    }
}
