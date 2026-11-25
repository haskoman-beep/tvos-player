import SwiftUI

/// Task 5.5 (D-3): fixed sizes and the two functional colours of the remaining screens (profile picker, login, phone
/// page, TorBox row, row manager). Kept in their own file next to `Theme` so the views outside `Views/Design/`
/// carry no literals; spacing, radii, colours and motion come from the runtime theme (`@Environment(\.theme)`).
extension Theme.Layout {
    // Profile picker (Build 4 follow-up 2 ring style).
    /// Profile circle.
    static let profileCircle: CGFloat = 220
    /// Gap between circle and focus ring, and the ring's stroke.
    static let profileRingGap: CGFloat = 10
    static let profileRingWidth: CGFloat = 6
    /// Lift of the focused profile (larger than `focus.tileScale`: the circle is the only thing on the page).
    static let profileFocusScale: CGFloat = 1.1

    // QR codes (login page, phone page).
    static let qrLogin: CGFloat = 360
    static let qrPhone: CGFloat = 480
    /// Longest line of the phone page's explanation.
    static let phoneTextWidth: CGFloat = 900

    // TorBox row (library).
    static let fileTileWidth: CGFloat = 480
    /// Two title lines, one detail line and the progress line at `rowDetail` (29 pt) plus the gaps.
    static let fileTileHeight: CGFloat = 180
    static let fileRefreshWidth: CGFloat = 240
    static let fileProgressWidth: CGFloat = 160
    /// Height of the hint while the list loads or is empty.
    static let fileHintHeight: CGFloat = 120

    // Row manager.
    /// Position number in front of a row ("12").
    static let positionColumn: CGFloat = 56
    /// Buttons of the action bar under an open row.
    static let actionBarRowHeight: CGFloat = 64
}

extension Theme.Palette {
    /// Quiet zone behind a QR code: always white, whatever the look (cameras need the contrast).
    static let qrBackground = Color.white
}
