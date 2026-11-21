import SwiftUI

/// Uhr oben rechts für die obere Leiste (Format HH:mm, aktualisiert jede Minute).
struct ClockView: View {
    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(Self.format.string(from: ctx.date))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
    }
}
