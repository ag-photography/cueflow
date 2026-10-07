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

    /// Shared reading width for the three primary destinations. Keeping this
    /// identical avoids a subtle horizontal jump when switching tabs.
    static let mainContentWidth: CGFloat = 720

    // MARK: - Colour

    /// Filled system controls retain light foreground contrast in both modes.
    static let accent = Color(light: Color(red: 0.08, green: 0.42, blue: 0.52),
                              dark: Color(red: 0.32, green: 0.36, blue: 0.84))
    static let accentText = Color(light: Color(red: 0.08, green: 0.42, blue: 0.52),
                                  dark: Color(red: 0.70, green: 0.75, blue: 1.00))
    static let accentSoft = accentText.opacity(0.16)
    static let onAccent = Color(red: 0.97, green: 0.98, blue: 1.00)

    /// Midnight blue keeps the canvas restful without draining the colour.
    static let surface0 = Color(light: Color(red: 0.97, green: 0.95, blue: 0.90),
                                dark: Color(red: 0.045, green: 0.065, blue: 0.12))
    static let surface1 = Color(light: Color(red: 1.00, green: 0.99, blue: 0.96),
                                dark: Color(red: 0.085, green: 0.12, blue: 0.20))
    static let surface2 = Color(light: Color(red: 0.93, green: 0.90, blue: 0.83),
                                dark: Color(red: 0.13, green: 0.17, blue: 0.28))
    static let pageBackground = LinearGradient(
        colors: [surface0, surface0, surface2], startPoint: .top, endPoint: .bottom)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(light: Color(.secondaryLabel),
                                     dark: Color(red: 0.72, green: 0.78, blue: 0.88))
    static let textTertiary = Color(light: Color(.tertiaryLabel),
                                    dark: Color(red: 0.60, green: 0.67, blue: 0.79))

    /// Decorative activity identities stay separate from grading signals.
    static let playMint = Color(red: 0.39, green: 0.94, blue: 0.73)
    static let playInk = Color(red: 0.035, green: 0.16, blue: 0.16)
    static let sprintColor = Color(light: Color(red: 0.65, green: 0.33, blue: 0.02),
                                   dark: Color(red: 1.00, green: 0.73, blue: 0.29))
    static let conversationColor = Color(light: Color(red: 0.49, green: 0.24, blue: 0.74),
                                         dark: Color(red: 0.79, green: 0.62, blue: 1.00))
    static let listeningColor = Color(light: Color(red: 0.02, green: 0.43, blue: 0.56),
                                      dark: Color(red: 0.32, green: 0.82, blue: 1.00))

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
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg, style: .continuous))
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

    /// One restrained card surface for practice and flip-card faces, using
    /// semantic colour and the same elevation system as the main screens.
    func dsFlashcardSurface() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(DS.surface1)
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(DS.textSecondary.opacity(0.10), lineWidth: 1))
            .modifier(DS.Elevation(level: 1))
    }
}

/// One scrollable stage for recognition, construction and production. Short
/// prompts keep the full viewport; long text and the keyboard never clip input.
struct PracticeStage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content().frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// The shared session frame (docs/coherence.md → Interaction grammar): title,
/// page background and one way to leave. When progress would be lost the
/// learner is asked "Runde beenden?" first; `onQuit` runs before dismissal so
/// the activity can save what it has.
struct SessionChrome: ViewModifier {
    let title: String
    var confirmQuit: Bool = false
    var closeIdentifier: String = "session-close"
    var onQuit: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        if confirmQuit { confirming = true } else { onQuit(); dismiss() }
                    }
                    .accessibilityIdentifier(closeIdentifier)
                }
            }
            .confirmationDialog("Runde beenden?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Runde beenden", role: .destructive) { onQuit(); dismiss() }
                Button("Weitermachen", role: .cancel) {}
            } message: {
                Text("Was du aus dem Kopf gesagt hast, ist schon gespeichert.")
            }
    }
}

extension View {
    func sessionChrome(_ title: String, confirmQuit: Bool = false, closeIdentifier: String = "session-close",
                       onQuit: @escaping () -> Void = {}) -> some View {
        modifier(SessionChrome(title: title, confirmQuit: confirmQuit, closeIdentifier: closeIdentifier, onQuit: onQuit))
    }
}

/// The one answer-feedback header: icon in a tinted circle, a short title and
/// an optional line of detail. Correct, close, not-yet and shown each have one
/// icon and one grade colour app-wide.
struct FeedbackBanner: View {
    enum Outcome { case correct, close, notYet, shown }
    let icon: String
    let color: Color
    let title: String
    var detail: String? = nil

    init(_ outcome: Outcome, title: String, detail: String? = nil) {
        switch outcome {
        case .correct: icon = "checkmark.circle.fill"; color = DS.gradePerfect
        case .close: icon = "circle.lefthalf.filled"; color = DS.gradeMinor
        case .notYet: icon = "arrow.uturn.backward.circle.fill"; color = DS.gradeWrong
        case .shown: icon = "lightbulb.fill"; color = DS.accentText
        }
        self.title = title; self.detail = detail
    }

    /// For grades with their own nuance (e.g. Üben's "hesitant").
    init(icon: String, color: Color, title: String, detail: String? = nil) {
        self.icon = icon; self.color = color; self.title = title; self.detail = detail
    }

    var body: some View {
        HStack(spacing: DS.space.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.18))
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold()).foregroundStyle(DS.textPrimary)
                if let detail { Text(detail).font(.caption).foregroundStyle(DS.textSecondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The one typed-answer field. Return is the action ("Los" checks the answer),
/// so no "hide keyboard" control is needed; the field reads right-to-left for
/// RTL languages and highlights while focused.
struct AnswerField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var isRTL = false
    var disabled = false
    var identifier = "answer-field"
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.title3)
            .textFieldStyle(.plain)
            .multilineTextAlignment(isRTL ? .trailing : .leading)
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .padding(.horizontal, DS.space.lg)
            .padding(.vertical, 18)
            .background(DS.surface1)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(focus.wrappedValue ? DS.accent : DS.textTertiary.opacity(0.25), lineWidth: 2))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.go)
            .focused(focus)
            .disabled(disabled)
            .onSubmit {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onSubmit()
            }
            .accessibilityIdentifier(identifier)
    }
}

/// The one microphone control: the same look, wording and stop affordance in
/// every activity that listens.
struct MicButton: View {
    let isRecording: Bool
    var title: String = "Sprechen"
    var identifier: String = "mic-button"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isRecording ? "Ich höre zu … Stopp" : title,
                  systemImage: isRecording ? "stop.circle.fill" : "mic.fill")
        }
        .buttonStyle(DSPrimaryButtonStyle(fill: isRecording ? DS.gradeWrong : DS.accent))
        .accessibilityIdentifier(identifier)
    }
}

/// The one primary action style (docs/coherence.md → Visual language): accent
/// capsule, full width. Mint is for celebration content, never for actions.
struct DSPrimaryButtonStyle: ButtonStyle {
    /// Accent for every action; the mic swaps to the stop colour while recording.
    var fill: Color = DS.accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isEnabled ? Color.white : DS.disabledText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(isEnabled ? fill : DS.disabled))
            .shadow(color: isEnabled ? fill.opacity(0.30) : .clear, radius: 8, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

/// Immediate tactile acknowledgement, not success feedback or a timed gate.
struct PracticePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shared hierarchy marker for top-level content groups on the three main
/// destinations. Editorial hero copy remains free-form; repeated dashboard
/// sections use this component so casing, tracking and spacing stay coherent.
struct DSSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .textCase(.uppercase)
                .tracking(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.space.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Typography for language content, kept separate from editorial serif
/// headlines. Russian uses the modern rounded San Francisco Cyrillic face;
/// Arabic stays on Apple's native Arabic system face to preserve shaping and
/// diacritics without falling back to a Latin-oriented display serif.
enum LearningTypography {
    static func display(
        size: CGFloat,
        weight: Font.Weight = .semibold,
        languageCode: String? = nil
    ) -> Font {
        .system(size: size, weight: weight, design: design(for: languageCode))
    }

    static func display(
        _ style: Font.TextStyle,
        weight: Font.Weight = .semibold,
        languageCode: String? = nil
    ) -> Font {
        .system(style, design: design(for: languageCode), weight: weight)
    }

    private static func design(for languageCode: String?) -> Font.Design {
        languageCode == "ar" ? .default : .rounded
    }
}
