import Foundation

/// Zielgröße eines Bildes in Pixeln: gezeichnete Größe (Punkte) × Bildschirmfaktor, je Seite auf
/// gemeinsame Stufen aufgerundet, damit ähnlich große Ansichten ein Bitmap teilen.
public struct ImageTarget: Hashable, Sendable {
    /// Stufen der Kantenlänge in Pixeln.
    public static let steps = [64, 128, 192, 256, 384, 512, 640, 768, 1024, 1280, 1536, 1920, 2560, 3840]

    public var width: Int
    public var height: Int
    /// true = Bild ganz zeigen (Logos), false = Fläche füllen (beschneiden).
    public var fit: Bool

    public init(width: Int, height: Int, fit: Bool) {
        self.width = width; self.height = height; self.fit = fit
    }

    /// nil, solange die Größe noch nicht bekannt ist (erster Layout-Durchlauf mit 0): nicht winzig dekodieren.
    public init?(points width: Double, _ height: Double, scale: Double, fit: Bool) {
        guard width.isFinite, height.isFinite, scale.isFinite, width >= 1, height >= 1, scale > 0 else { return nil }
        self.init(width: Self.step(Int((width * scale).rounded(.up))), height: Self.step(Int((height * scale).rounded(.up))), fit: fit)
    }

    /// Quadrat mit fester Kantenlänge (alte Aufrufe mit `maxPixels`): Ergebnis wie bisher höchstens `maxPixels` lang.
    public static func square(_ maxPixels: Int) -> ImageTarget {
        ImageTarget(width: max(1, maxPixels), height: max(1, maxPixels), fit: true)
    }

    public static func step(_ px: Int) -> Int {
        steps.first { $0 >= px } ?? steps[steps.count - 1]
    }

    /// Längere Seite des Bitmaps beim Dekodieren für ein Bild mit `imageWidth`×`imageHeight` Pixeln:
    /// füllen = so groß, dass beide Seiten das Ziel decken; ganz zeigen = so groß, dass es hineinpasst.
    /// Nie größer als das Original.
    public func decodeMaxPixels(imageWidth: Int, imageHeight: Int) -> Int {
        guard imageWidth > 0, imageHeight > 0 else { return max(width, height) }
        let sx = Double(width) / Double(imageWidth), sy = Double(height) / Double(imageHeight)
        let s = min(1, fit ? min(sx, sy) : max(sx, sy))
        return max(1, Int((Double(max(imageWidth, imageHeight)) * s).rounded(.up)))
    }

    /// Breite, die eine Variante beim Bilddienst mindestens haben sollte. Seitenverhältnis unbekannt:
    /// beim Füllen wird ein Hochformat-Bild (2:3, Poster) angenommen, das die Höhe decken muss.
    public var neededSourceWidth: Int {
        fit ? width : max(width, Int((Double(height) * 2 / 3).rounded(.up)))
    }

    public var cacheKey: String { "\(width)x\(height)\(fit ? "f" : "c")" }
}

/// Größen-Varianten bekannter Bilddienste. Reihenfolge der Kandidaten: passende Variante zuerst,
/// danach die Original-Adresse als Ersatz (fehlt die Variante, bleibt keine Lücke).
public enum ImageURLVariant {
    /// TMDB-Breiten, die der Bilddienst für Poster, Hintergründe und Logos ausliefert.
    public static let tmdbWidths = [342, 500, 780, 1280]
    /// Metahub-Posterstufen mit ungefährer Breite.
    static let metahubSteps: [(name: String, width: Int)] = [("small", 160), ("medium", 340), ("large", 680)]

    public static func candidates(for url: String, neededWidth: Int) -> [String] {
        if let t = tmdb(url, neededWidth: neededWidth), t != url { return [t, url] }
        if let m = metahub(url, neededWidth: neededWidth), m != url { return [m, url] }
        return [url]
    }

    /// `image.tmdb.org/t/p/<größe>/…`: `original` → kleinste ausreichende Breite (#23);
    /// eine zu kleine `w…`-Stufe → größere Stufe (nur wenn nötig). SVG bleibt unverändert.
    static func tmdb(_ url: String, neededWidth: Int) -> String? {
        guard let r = url.range(of: "image.tmdb.org/t/p/"), !url.lowercased().hasSuffix(".svg") else { return nil }
        let rest = url[r.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let size = String(rest[..<slash])
        let target = tmdbWidths.first { $0 >= neededWidth }.map { "w\($0)" } ?? "original"
        if size == "original" {
            guard target != "original" else { return nil }
        } else if size.hasPrefix("w"), let w = Int(size.dropFirst()) {
            guard w < neededWidth else { return nil }   // reicht schon
            if let t = Int(target.dropFirst()), t <= w { return nil }
        } else {
            return nil                                   // h632 u. a.: nicht anfassen
        }
        return String(url[..<r.upperBound]) + target + String(rest[slash...])
    }

    /// `images.metahub.space/poster/<stufe>/…`: nur Poster und nur aufwerten (Hintergrund/Logo sind
    /// in allen Stufen dieselbe Datei).
    static func metahub(_ url: String, neededWidth: Int) -> String? {
        guard let r = url.range(of: "metahub.space/poster/") else { return nil }
        let rest = url[r.upperBound...]
        guard let slash = rest.firstIndex(of: "/"), let cur = metahubSteps.firstIndex(where: { $0.name == rest[..<slash] }) else { return nil }
        guard metahubSteps[cur].width < neededWidth else { return nil }
        let want = metahubSteps.firstIndex { $0.width >= neededWidth } ?? metahubSteps.count - 1
        guard want > cur else { return nil }
        return String(url[..<r.upperBound]) + metahubSteps[want].name + String(rest[slash...])
    }
}
