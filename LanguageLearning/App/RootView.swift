import SwiftUI

/// Single practice screen with an internal mode picker. Earlier versions used
/// `TabView` page-style for swipe-to-switch, but the bottom page dots overlay
/// the rating buttons and conflict with editing — the explicit segmented
/// control at the top is clearer.
struct RootView: View {
    var body: some View {
        PracticeView()
    }
}
