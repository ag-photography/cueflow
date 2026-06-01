import SwiftUI
import UIKit

extension Color {
    /// Light/dark variant convenience — bakes a `UIColor.init(dynamicProvider:)`
    /// behind the scenes so trait collection changes are observed.
    init(light: Color, dark: Color) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// Single source of truth for visual tokens — colour, spacing, corner radius,
/// shadow, typography helpers. Every screen pulls from here so the look stays
/// coherent and a future palette swap is one file.
enum DS {

    // MARK: - Colour

    /// Brand accent — deep teal, slightly more saturated than the previous
    /// muted shade so primary buttons read as confident, not tentative.
    static let accent = Color(red: 0.08, green: 0.42, blue: 0.52)
    static let accentSoft = Color(red: 0.08, green: 0.42, blue: 0.52).opacity(0.12)

    /// Fixed warm cream that does NOT flip in dark mode — for content layered
    /// directly on the brand teal (e.g. the onboarding badge lettering), where
    /// it must stay light in both appearances. `surface0` would invert to
    /// near-black in dark and kill the contrast.
    static let onAccent = Color(red: 0.97, green: 0.95, blue: 0.90)

    /// Surface scale. Warm cream in light mode (Babbel-style premium reading
    /// surface), deep neutral charcoal in dark mode. Avoids the stark
    /// iOS-default white that read as "system form".
    static let surface0 = Color(
        light: Color(red: 0.97, green: 0.95, blue: 0.90),   // warm cream
        dark: Color(red: 0.09, green: 0.09, blue: 0.10)      // near-black
    )
    static let surface1 = Color(
        light: Color(red: 1.00, green: 0.99, blue: 0.96),   // very light cream / "white" on cream
        dark: Color(red: 0.16, green: 0.16, blue: 0.17)
    )
    static let surface2 = Color(
        light: Color(red: 0.93, green: 0.90, blue: 0.83),   // slightly deeper cream
        dark: Color(red: 0.22, green: 0.22, blue: 0.23)
    )

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    /// Disabled-state grey. Distinct from the faded-accent look so a disabled
    /// primary button reads as "waiting for input" not "broken".
    static let disabled = Color(
        light: Color(red: 0.85, green: 0.83, blue: 0.78),
        dark: Color(red: 0.27, green: 0.27, blue: 0.28)
    )
    static let disabledText = Color(
        light: Color(red: 0.55, green: 0.53, blue: 0.48),
        dark: Color(red: 0.55, green: 0.55, blue: 0.56)
    )

    /// Semantic colours for grading. Slightly desaturated so they feel
    /// information-conveying, not alarming.
    static let gradePerfect = Color(red: 0.18, green: 0.60, blue: 0.35)
    static let gradeHesitant = Color(red: 0.85, green: 0.65, blue: 0.15)
    static let gradeMinor = Color(red: 0.90, green: 0.55, blue: 0.20)
    static let gradeWrong = Color(red: 0.80, green: 0.30, blue: 0.30)

    // MARK: - Spacing

    /// 4pt scale. Compose with `padding(.horizontal, DS.space.md)`.
    enum space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner radius

    enum radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Shadow

    /// Soft elevation; use for cards that should "lift" off the surface.
    struct Elevation: ViewModifier {
        let level: Int
        func body(content: Content) -> some View {
            switch level {
            case 1:
                content.shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
            case 2:
                content.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            default:
                content
            }
        }
    }
}

// MARK: - View modifiers

extension View {
    /// Soft "card" container — rounded surface1 background, optional shadow.
    func dsCard(elevation: Int = 1, padding: CGFloat = DS.space.md) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            .modifier(DS.Elevation(level: elevation))
    }

    /// Strong elevated prompt — used for the German source text. Slightly
    /// larger radius and more depth than `dsCard` so it reads as the focal point.
    func dsHeroCard() -> some View {
        self
            .padding(.horizontal, DS.space.lg)
            .padding(.vertical, DS.space.xl)
            .frame(maxWidth: .infinity)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            .modifier(DS.Elevation(level: 2))
    }

    /// The premium "flashcard" surface shared by the practice prompt and the
    /// flip-card faces: continuous corners, a subtle top highlight (lit-from-
    /// above), and a layered shadow — a soft teal-tinted ambient glow plus a
    /// tighter contact shadow. One definition so all three modes read identically.
    func dsFlashcardSurface() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(DS.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: DS.accent.opacity(0.10), radius: 22, x: 0, y: 12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
