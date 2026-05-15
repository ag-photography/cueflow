import SwiftUI

/// Single source of truth for visual tokens — colour, spacing, corner radius,
/// shadow, typography helpers. Every screen pulls from here so the look stays
/// coherent and a future palette swap is one file.
enum DS {

    // MARK: - Colour

    /// Brand accent — calm deep teal. Reads as "premium reading app" rather
    /// than gamified or playful.
    static let accent = Color(red: 0.16, green: 0.45, blue: 0.55)
    static let accentSoft = Color(red: 0.16, green: 0.45, blue: 0.55).opacity(0.12)

    /// Surface scale. Use these instead of `.background` / hard-coded greys
    /// so dark mode just works.
    static let surface0 = Color(.systemBackground)
    static let surface1 = Color(.secondarySystemBackground)
    static let surface2 = Color(.tertiarySystemBackground)

    /// Disabled-state grey. Distinct from the faded-accent look so a disabled
    /// primary button reads as "waiting for input" not "broken".
    static let disabled = Color(.systemGray5)
    static let disabledText = Color(.systemGray2)

    /// Foreground scale.
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

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
}
