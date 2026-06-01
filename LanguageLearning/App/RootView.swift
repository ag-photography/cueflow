import SwiftUI
import SwiftData

/// Root gate: a fresh install sees the onboarding walkthrough; once
/// `hasCompletedOnboarding` is set, every launch goes straight to practice.
///
/// The practice screen itself uses a custom header with an internal mode picker
/// (an earlier `TabView` page-style put bottom page dots over the rating row),
/// so RootView's only job is the onboarding/main decision.
struct RootView: View {
    @Query private var settings: [AppSettings]

    private var hasOnboarded: Bool {
        settings.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        Group {
            if hasOnboarded {
                PracticeView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasOnboarded)
    }
}
