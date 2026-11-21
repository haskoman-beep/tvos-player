import SwiftUI
import Combine
import PlayerCore

// Qualitäts-Plaketten (Task 8): neutrales Glas, nur der Cache-Status farbig; gezeichnete Wortmarken-Logos
// (keine Bilddateien, keine fremden Logos). Logik (welche Plaketten, beste Werte) liegt in PlayerCore/QualityBadges.

/// Untergrund, auf dem eine Plakette sitzt – bestimmt Schrift- und Flächenfarbe.
enum BadgeSurface {
    /// Dunkler Hintergrund (Quellenliste, Detailseite): weiße Schrift auf hellem Glas.
    case dark
    /// Helle, fokussierte Zeile: dunkle Schrift auf dunklem Glas.
    case light
    /// Auf einem Bild (Poster): weiße Schrift auf dunkler Fläche.
    case image

    var foreground: Color { self == .light ? Color.black.opacity(0.85) : .white }
    var fill: Color {
        switch self {
        case .dark: Color.white.opacity(0.14)
        case .light: Color.black.opacity(0.10)
        case .image: Color.black.opacity(0.6)
        }
    }
}

/// Gezeichnete Logo-Plakette im Wortmarken-Stil, monochrom. Wiederverwendbar (z. B. später im Player).
struct QualityLogo: View {
    let kind: QualityLogoKind
    var height: CGFloat = 38
    var color: Color = .white

    var body: some View {
        wordmark
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, height * 0.26)
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                .strokeBorder(color.opacity(0.65), lineWidth: max(1, height * 0.045)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.label(kind))
    }

    /// Unter dieser Höhe entfällt die kleine Zusatzzeile bei 4K (wäre unleserlich).
    private var compact: Bool { height < 34 }

    @ViewBuilder private var wordmark: some View {
        switch kind {
        case .uhd4K:
            if compact { line("4K", 0.56) } else { twoLine("4K", "ULTRA HD", top: 0.42, bottom: 0.2) }
        case .dolbyVision: twoLine("DOLBY", "VISION")
        case .dolbyAtmos: twoLine("DOLBY", "ATMOS")
        case .dtsHDMA: twoLine("DTS-HD", "MASTER AUDIO", bottom: 0.22)
        case .dtsX: line("DTS:X", 0.46)
        case .hdr10: line("HDR10", 0.44)
        case .hdr10Plus: line("HDR10+", 0.44)
        case .remux: line("REMUX", 0.42, tracking: 0.06)
        }
    }

    private func line(_ t: String, _ size: CGFloat, tracking: CGFloat = 0.02) -> some View {
        Text(t).font(.system(size: height * size, weight: .heavy)).tracking(height * tracking)
    }

    /// Zweizeilig: oben fett, unten leicht und gesperrt.
    private func twoLine(_ top: String, _ bottom: String, top topSize: CGFloat = 0.34, bottom bottomSize: CGFloat = 0.27) -> some View {
        VStack(spacing: -height * 0.03) {
            Text(top).font(.system(size: height * topSize, weight: .heavy)).tracking(height * 0.03)
            Text(bottom).font(.system(size: height * bottomSize, weight: .light)).tracking(height * 0.07)
        }
    }

    static func label(_ k: QualityLogoKind) -> String {
        switch k {
        case .uhd4K: "4K Ultra HD"
        case .dolbyVision: "Dolby Vision"
        case .dolbyAtmos: "Dolby Atmos"
        case .dtsHDMA: "DTS-HD Master Audio"
        case .dtsX: "DTS:X"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .remux: "Remux"
        }
    }
}

/// Eine Plakette: Logo oder Text, gleiche Höhe; neutral, nur der Cache-Status farbig.
struct QualityBadgeView: View {
    let badge: QualityBadge
    var height: CGFloat = 38
    var surface: BadgeSurface = .dark

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
        if let logo = badge.logo {
            QualityLogo(kind: logo, height: height, color: surface.foreground)
                .background(surface.fill, in: shape)
        } else {
            Text(badge.text)
                .font(.system(size: height * 0.56, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(foreground)
                .padding(.horizontal, height * 0.3)
                .frame(height: height)
                .background(fill, in: shape)
        }
    }

    private var foreground: Color { badge.tone == .neutral ? surface.foreground : .white }

    private var fill: Color {
        switch badge.tone {
        case .neutral: surface.fill
        case .ready: Color(red: 0.16, green: 0.56, blue: 0.30)
        case .pending: Color(red: 0.56, green: 0.24, blue: 0.24)
        }
    }
}

/// Kleine Plaketten unten am Poster (beste Auflösung, DV/HDR, Atmos) – nur aus dem Quellen-Cache, keine Netzabfrage.
struct PosterQualityBadges: View {
    @EnvironmentObject var model: AppModel
    let item: MetaPreview
    var scale: CGFloat = 1
    @State private var best: BestQuality?

    var body: some View {
        let settings = model.profile.appearance.badges
        let list = best.map { QualityBadges.poster($0, settings: settings) } ?? []
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if !list.isEmpty {
                // Fortschrittsbalken (CardStateOverlay) sitzt ganz unten: Plaketten darüber.
                let lifted = (model.progress.cardState(itemID: item.id)?.fraction ?? 0) > 0
                HStack(spacing: 6 * scale) {
                    ForEach(list) { QualityBadgeView(badge: $0, height: 30 * scale, surface: .image) }
                }
                .padding(.trailing, 10 * scale)
                .padding(.bottom, (lifted ? 24 : 10) * scale)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(item.id)|\(settings.onPosters)") {
            best = settings.onPosters ? QualityBadgeCache.shared.best(for: item, model: model) : nil
        }
        .onReceive(QualityBadgeCache.shared.stored) { id in
            guard settings.onPosters, model.streamCacheKey(for: item) == id else { return }
            withAnimation(.easeOut(duration: 0.2)) { best = QualityBadgeCache.shared.best(id: id, model: model) }
        }
    }
}

/// Beste Werte je Quellen-Cache-ID, einmal berechnet (nicht in jedem body). `AppModel` meldet neue Quellen über
/// `streamsStored`, wartende Poster aktualisieren sich dann über `stored`.
@MainActor
final class QualityBadgeCache {
    static let shared = QualityBadgeCache()
    /// Sendet die Cache-ID, sobald neue Quellen im AppModel-Cache liegen.
    let stored = PassthroughSubject<String, Never>()
    private var cache: [String: BestQuality] = [:]

    private init() {}

    func streamsStored(id: String) {
        cache[id] = nil
        stored.send(id)
    }

    /// Nur solange die Quellen im AppModel-Cache liegen; sonst nil.
    func best(id: String, model: AppModel) -> BestQuality? {
        guard let list = model.cachedStreams(id: id), !list.isEmpty else { cache[id] = nil; return nil }
        if let b = cache[id] { return b }
        guard let b = BestQuality.from(list.map(\.stream)) else { return nil }
        if cache.count >= 2 * StreamPrefetcher.cacheLimit {
            cache = cache.filter { model.cachedStreams(id: $0.key) != nil }
        }
        cache[id] = b
        return b
    }

    func best(for item: MetaPreview, model: AppModel) -> BestQuality? {
        model.streamCacheKey(for: item).flatMap { best(id: $0, model: model) }
    }
}
