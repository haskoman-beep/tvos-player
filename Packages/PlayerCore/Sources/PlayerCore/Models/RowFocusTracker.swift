import Foundation

/// Build 6 (redraw): the focus state of one home row, built from the reports of its cards and placeholders instead
/// of reading the row's `@FocusState` in the row body (that read ran the whole row body twice per focus move:
/// old card → nil → new card). Each focusable view reports its own focus change; the two reports of one move come
/// from two views in no fixed order, so:
/// - a "false" only clears the current card (or placeholder) when it is the reporter (a late "false" of the old card
///   after the new card's "true" changes nothing);
/// - a "true" while another card is current first emits the old card → nil step, so the route still passes through
///   nil as the focus state did (the rest-prefetch cancel relies on it), but no leave.
/// The events are what the row's two `onChange` handlers saw before (`route` = focused card, `inside` = a card or
/// placeholder of the row holds the focus).
public struct RowFocusTracker<Card: Equatable> {
    public enum Event: Equatable {
        case route(old: Card?, new: Card?)
        case inside(Bool)
    }

    public private(set) var card: Card?
    public private(set) var placeholder: Int?
    private var reportedInside = false

    public init() {}

    public var inside: Bool { card != nil || placeholder != nil }

    /// Re-review L4: tracker slot of the status tile (empty/failed row). Its `.focused` value is 0 like the first
    /// placeholder, but the two are different views: on the switch from placeholders to the status tile their
    /// reports must not cancel each other.
    public static var statusSlot: Int { -1 }

    /// The focused placeholder as the row's focus state value (status tile → 0), nil without one.
    public var focusStateSlot: Int? {
        guard let p = placeholder else { return nil }
        return p == Self.statusSlot ? 0 : p
    }

    /// A card's button focus changed (also its first report when built).
    public mutating func card(_ c: Card, focused: Bool) -> [Event] {
        var out: [Event] = []
        if focused {
            guard card != c else { return [] }
            if let old = card {
                card = nil
                out.append(.route(old: old, new: nil))
            }
            card = c
            out.append(.route(old: nil, new: c))
        } else {
            guard card == c else { return [] }
            card = nil
            out.append(.route(old: c, new: nil))
        }
        return out + insideEvent()
    }

    /// A placeholder's (or the status tile's, `statusSlot`) focus changed.
    public mutating func placeholder(_ slot: Int, focused: Bool) -> [Event] {
        if focused {
            guard placeholder != slot else { return [] }
            placeholder = slot
        } else {
            guard placeholder == slot else { return [] }
            placeholder = nil
        }
        return insideEvent()
    }

    private mutating func insideEvent() -> [Event] {
        let now = inside
        guard now != reportedInside else { return [] }
        reportedInside = now
        return [.inside(now)]
    }
}
