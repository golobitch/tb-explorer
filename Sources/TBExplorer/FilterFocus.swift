import Foundation
import Observation

/// The filter row of whichever screen is frontmost in the focused window.
///
/// Published per screen with `focusedSceneValue`, so ⌘F reaches the view the user is looking at.
/// A counter on the window would not do: `NavigationStack` keeps the screens underneath the top
/// one alive, so every filter row in the window would answer at once.
@MainActor
@Observable
final class FilterFocus {
    private(set) var token = 0

    func request() {
        token += 1
    }
}
