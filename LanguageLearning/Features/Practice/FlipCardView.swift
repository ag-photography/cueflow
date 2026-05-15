import SwiftUI
import UIKit

/// Tap-to-flip flashcard with swipe-to-rate gesture. German phrase on the
/// front; tap flips to Russian answer; once flipped, swipe right ("knew it")
/// or left ("didn't know") to record an FSRS rating and advance.
///
/// Recognition-mode practice — easier than typing/speaking, useful when
/// the user is still picking up new vocabulary.
struct FlipCardView: View {
    let card: StudyCard
    let showTransliteration: Bool
    let onRate: (Int) -> Void   // 1 = Again, 3 = Good

    @State private var flipped = false
    @State private var dragOffset: CGSize = .zero
    @State private var dismissed = false

    /// Swipe distance (pts) before a swipe commits to a rating.
    private let commitThreshold: CGFloat = 110

    var body: some View {
        ZStack {
            edgeHints
            cardStack
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / 18)))
                .scaleEffect(dismissed ? 0.85 : 1.0)
                .opacity(dismissed ? 0 : 1)
                .gesture(swipeGesture)
                .onTapGesture {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    let willReveal = !flipped
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                        flipped.toggle()
                    }
                    // Speak the Russian when revealing (not when flipping back).
                    // Matches the auto-play behaviour on the type/speak reveal screens.
                    if willReveal {
                        TTSService.shared.speak(
                            card.phrase?.targetText ?? "",
                            language: card.phrase?.language?.ttsLocale ?? "ru-RU",
                            times: 2
                        )
                    }
                }
        }
    }

    // MARK: - Card faces

    @ViewBuilder
    private var cardStack: some View {
        ZStack {
            face(
                text: card.phrase?.sourceText ?? "",
                subtitle: nil,
                showTapHint: !flipped
            )
            .opacity(flipped ? 0 : 1)
            .rotation3DEffect(
                .degrees(flipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )

            face(
                text: card.phrase?.targetText ?? "",
                subtitle: showTransliteration ? card.phrase?.transliteration : nil,
                showTapHint: false
            )
            .opacity(flipped ? 1 : 0)
            .rotation3DEffect(
                .degrees(flipped ? 0 : -180),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
        }
    }

    private func face(text: String, subtitle: String?, showTapHint: Bool) -> some View {
        // Length-aware font scaling so longer phrases wrap gracefully.
        let size: CGFloat = text.count > 30 ? 28 : (text.count > 15 ? 34 : 42)
        return VStack(spacing: DS.space.md) {
            Spacer()
            Text(text)
                .font(.system(size: size, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.textPrimary)
                .padding(.horizontal, DS.space.md)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(DS.textTertiary)
            }
            Spacer()
            if showTapHint {
                Label("Tippen zum Aufdecken", systemImage: "hand.tap")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.bottom, DS.space.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
    }

    // MARK: - Edge hints

    private var edgeHints: some View {
        // Subtle coloured panels behind the card revealed by the drag direction.
        // Right = green ("Gewusst"), left = red ("Nicht gewusst").
        HStack {
            hintPanel(
                color: DS.gradeWrong,
                icon: "xmark",
                label: "Nicht gewusst",
                shown: dragOffset.width < -20
            )
            Spacer()
            hintPanel(
                color: DS.gradePerfect,
                icon: "checkmark",
                label: "Gewusst",
                shown: dragOffset.width > 20
            )
        }
        .padding(.horizontal, DS.space.lg)
    }

    private func hintPanel(color: Color, icon: String, label: String, shown: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title.weight(.bold))
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .opacity(shown ? min(1, abs(dragOffset.width) / 100) : 0)
        .animation(.easeOut(duration: 0.15), value: shown)
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard flipped else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard flipped else { return }
                if abs(value.translation.width) > commitThreshold {
                    let knewIt = value.translation.width > 0
                    let rating = knewIt ? 3 : 1
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = knewIt ? .medium : .heavy
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
                    let flyTo = CGSize(
                        width: knewIt ? 600 : -600,
                        height: value.translation.height
                    )
                    withAnimation(.easeOut(duration: 0.28)) {
                        dragOffset = flyTo
                        dismissed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onRate(rating)
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}
