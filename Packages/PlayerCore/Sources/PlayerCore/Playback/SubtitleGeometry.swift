import Foundation

/// Lage von Untertiteln auf dem Bildschirm (reine Rechnung, für das Overlay).
public enum SubtitleGeometry {
    /// Rechteck, in dem das Bild steht: seitenrichtig eingepasst und zentriert (wie `resizeAspect`).
    /// Unbekannte Videogröße → ganzer Container.
    public static func videoRect(container: CGSize, videoWidth: Int, videoHeight: Int, pixelAspect: Double = 1) -> CGRect {
        let full = CGRect(origin: .zero, size: container)
        guard videoWidth > 0, videoHeight > 0, container.width > 0, container.height > 0 else { return full }
        let par = pixelAspect.isFinite && pixelAspect > 0 ? pixelAspect : 1
        let aspect = Double(videoWidth) * par / Double(videoHeight)
        let containerAspect = Double(container.width / container.height)
        if aspect > containerAspect {
            let h = container.width / CGFloat(aspect)
            return CGRect(x: 0, y: (container.height - h) / 2, width: container.width, height: h)
        } else {
            let w = container.height * CGFloat(aspect)
            return CGRect(x: (container.width - w) / 2, y: 0, width: w, height: container.height)
        }
    }

    /// Bildschirmrahmen eines Bild-Untertitels (PGS/DVB/DVD).
    /// - position: normiert [0, 1] auf die Kompositionsfläche (`SubtitleImage.position`).
    /// - canvas: Pixelgröße der Kompositionsfläche (`SubtitleImage.canvasSize`), .zero = wie das Video.
    /// - codedVideo: kodierte Videogröße (`sourceVideoWidth/Height`), .zero = unbekannt.
    /// Vorgehen laut AetherEngine: Fläche breitenbündig und mittig auf das kodierte Bild legen,
    /// dann je Achse auf das angezeigte Bild skalieren (Achsen unterscheiden sich nur bei anamorph).
    public static func bitmapFrame(position: CGRect, canvas: CGSize, codedVideo: CGSize, videoRect: CGRect) -> CGRect {
        let coded = (codedVideo.width > 0 && codedVideo.height > 0) ? codedVideo
            : ((canvas.width > 0 && canvas.height > 0) ? canvas : CGSize(width: 1, height: 1))
        let canvasSize = (canvas.width > 0 && canvas.height > 0) ? canvas : coded
        let scale = coded.width / canvasSize.width
        let mappedHeight = canvasSize.height * scale
        let originY = (coded.height - mappedHeight) / 2
        let inCoded = CGRect(x: position.minX * coded.width, y: originY + position.minY * mappedHeight,
                             width: position.width * coded.width, height: position.height * mappedHeight)
        let sx = videoRect.width / coded.width, sy = videoRect.height / coded.height
        return CGRect(x: videoRect.minX + inCoded.minX * sx, y: videoRect.minY + inCoded.minY * sy,
                      width: inCoded.width * sx, height: inCoded.height * sy)
    }

    /// ASS-Ziffernblock (1 unten links … 9 oben rechts) als Anker: x 0/0.5/1, y von oben 0/0.5/1.
    /// Fehlend oder ungültig → unten mittig (2).
    public static func anchor(numpad: Int?) -> (x: Double, y: Double) {
        let n = (1...9).contains(numpad ?? 2) ? (numpad ?? 2) : 2
        let x = [0.0, 0.5, 1.0][(n - 1) % 3]
        let y = n <= 3 ? 1.0 : (n <= 6 ? 0.5 : 0.0)
        return (x, y)
    }

    /// Ist ein Cue zur Zeit `t` aktiv? Start eingeschlossen, Ende ausgeschlossen.
    public static func isActive(start: Double, end: Double, at t: Double) -> Bool { start <= t && t < end }
}
