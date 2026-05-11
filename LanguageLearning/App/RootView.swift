import SwiftUI

/// Two practice modes side by side; swipe horizontally to switch. Page dots at
/// the bottom show position. Library + settings live in each mode's toolbar.
struct RootView: View {
    @State private var mode: CardDirection = .typeDeToRu

    var body: some View {
        TabView(selection: $mode) {
            ForEach(CardDirection.allCases, id: \.self) { direction in
                PracticeView(mode: direction)
                    .tag(direction)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        // Intentionally NOT .ignoresSafeArea(.bottom): that disables SwiftUI's
        // automatic keyboard-avoidance in the child PracticeView, which lets
        // the keyboard overlay the Prüfen / "Ich weiß es nicht" buttons.
    }
}
