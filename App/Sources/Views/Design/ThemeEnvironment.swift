import SwiftUI

/// Task 4.4: the runtime theme in the environment. Set once at the root (`PlayerApp`) from the profile's look;
/// views that are not set up read `ThemeValues.standard` (= today's design).
private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeValues.standard
}

extension EnvironmentValues {
    var theme: ThemeValues {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
