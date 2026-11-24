import Foundation

/// Task 3.4 (F-B-1, F-B-5): whether a source list with an autostart intent (continue with the last source,
/// "play now") may start playback by itself. The intent lives in the route, which survives a rebuild of the
/// TabView, while the list's own state does not; so a used autostart is also remembered outside the view.
public enum AutostartGate {
    /// - `requestID`: ID of the route's request (the episode or film the list was pushed for).
    /// - `alreadyStarted`: route IDs whose autostart already ran (kept by the app; a new push clears its ID).
    /// - `isRebuild`: the load task runs again for a list that already autostarted in this view, or now
    ///   follows another episode (after "next episode automatically" or an episode chosen in the side panel).
    public static func shouldStart(requestID: String, alreadyStarted: Set<String>, isRebuild: Bool) -> Bool {
        !isRebuild && !alreadyStarted.contains(requestID)
    }
}
