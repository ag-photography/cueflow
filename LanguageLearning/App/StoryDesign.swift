import SwiftUI

/// Scene colours are decorative, never correctness signals. Native vector art
/// stays crisp offline and introduces no image decoding on tab switches.
enum StoryPalette {
    case orchard, cafe, sky, evening

    init(_ episode: LearningEpisode) {
        if episode.id.contains("cafe") { self = .cafe }
        else if episode.id.contains("seasons-2") { self = .sky }
        else if episode.interest == "Beruf" { self = .evening }
        else { self = .orchard }
    }

    var paper: Color {
        switch self {
        case .orchard: return Color(light: Color(red: 0.88, green: 0.94, blue: 0.83), dark: Color(red: 0.17, green: 0.25, blue: 0.20))
        case .cafe: return Color(light: Color(red: 0.99, green: 0.87, blue: 0.76), dark: Color(red: 0.29, green: 0.20, blue: 0.17))
        case .sky: return Color(light: Color(red: 0.84, green: 0.92, blue: 0.98), dark: Color(red: 0.16, green: 0.23, blue: 0.31))
        case .evening: return Color(light: Color(red: 0.91, green: 0.87, blue: 0.97), dark: Color(red: 0.23, green: 0.19, blue: 0.31))
        }
    }

    var ink: Color {
        Color(light: Color(red: 0.16, green: 0.24, blue: 0.23), dark: Color(red: 0.92, green: 0.95, blue: 0.87))
    }

    var accent: Color {
        switch self {
        case .orchard: return Color(red: 0.38, green: 0.58, blue: 0.36)
        case .cafe: return Color(red: 0.77, green: 0.39, blue: 0.26)
        case .sky: return Color(red: 0.31, green: 0.55, blue: 0.72)
        case .evening: return Color(red: 0.55, green: 0.44, blue: 0.72)
        }
    }
}

/// Purpose-built, decorative postcard illustration. A single bounded Canvas,
/// with no timers, remote assets, endless particles or offscreen animation.
struct StoryArtwork: View {
    let episode: LearningEpisode
    var celebrating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = StoryPalette(episode)
        Canvas { context, size in
            context.scaleBy(x: size.width / 320, y: size.height / 150)
            func ellipse(_ rect: CGRect, _ color: Color) { context.fill(Path(ellipseIn: rect), with: .color(color)) }
            func box(_ rect: CGRect, radius: CGFloat = 8, _ color: Color) {
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
            }
            func line(_ start: CGPoint, _ end: CGPoint, _ color: Color, width: CGFloat = 3) {
                var p = Path(); p.move(to: start); p.addLine(to: end)
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            let dark = Color(red: 0.18, green: 0.23, blue: 0.23)
            let cream = Color(red: 1, green: 0.96, blue: 0.84)
            ellipse(CGRect(x: 237, y: 12, width: 49, height: 49), Color(red: 0.98, green: 0.74, blue: 0.32))
            ellipse(CGRect(x: -65, y: 100, width: 310, height: 110), palette.accent.opacity(0.22))
            ellipse(CGRect(x: 140, y: 115, width: 250, height: 85), palette.accent.opacity(0.32))

            if episode.id.contains("cafe") {
                box(CGRect(x: 22, y: 22, width: 90, height: 92), radius: 12, cream)
                box(CGRect(x: 30, y: 30, width: 74, height: 58), radius: 8, palette.accent.opacity(0.4))
                line(CGPoint(x: 67, y: 30), CGPoint(x: 67, y: 88), cream)
                box(CGRect(x: 211, y: 111, width: 94, height: 8), radius: 4, palette.accent)
                ellipse(CGRect(x: 261, y: 83, width: 20, height: 19), cream)
                ellipse(CGRect(x: 264, y: 87, width: 11, height: 10), palette.paper)
                box(CGRect(x: 237, y: 79, width: 29, height: 29), radius: 7, cream)
                line(CGPoint(x: 246, y: 70), CGPoint(x: 249, y: 59), palette.ink.opacity(0.45), width: 2)
            } else if episode.interest == "Beruf" {
                box(CGRect(x: 25, y: 30, width: 99, height: 58), radius: 18, cream)
                for index in 0..<3 { ellipse(CGRect(x: 45 + index * 23, y: 54, width: 8, height: 8), palette.accent) }
                line(CGPoint(x: 102, y: 84), CGPoint(x: 113, y: 99), cream, width: 10)
            } else {
                line(CGPoint(x: 59, y: 71), CGPoint(x: 59, y: 137), palette.accent, width: 7)
                ellipse(CGRect(x: 21, y: 25, width: 75, height: 77), palette.accent)
                ellipse(CGRect(x: 34, y: 16, width: 59, height: 62), palette.accent)
                if episode.id.contains("seasons-2") {
                    for point in [CGPoint(x: 38, y: 30), CGPoint(x: 88, y: 16), CGPoint(x: 112, y: 68)] {
                        ellipse(CGRect(x: point.x, y: point.y, width: 7, height: 7), cream)
                    }
                } else {
                    ellipse(CGRect(x: 39, y: 55, width: 12, height: 12), Color(red: 0.97, green: 0.69, blue: 0.37))
                    ellipse(CGRect(x: 68, y: 38, width: 12, height: 12), Color(red: 0.97, green: 0.69, blue: 0.37))
                }
            }

            // Fictional companions, not flags or national caricatures.
            let lina = episode.language == "ar"
            let skin = lina ? Color(red: 0.73, green: 0.47, blue: 0.32) : Color(red: 0.91, green: 0.67, blue: 0.48)
            ellipse(CGRect(x: 136, y: 27, width: 63, height: lina ? 88 : 65), dark)
            box(CGRect(x: 124, y: 100, width: 88, height: 76), radius: 32, palette.accent)
            box(CGRect(x: 158, y: 87, width: 20, height: 24), radius: 7, skin)
            ellipse(CGRect(x: 143, y: 39, width: 50, height: 60), skin)
            ellipse(CGRect(x: 140, y: 29, width: 53, height: 24), dark)
            if lina { ellipse(CGRect(x: 175, y: 24, width: 28, height: 37), dark) }
            ellipse(CGRect(x: 154, y: 62, width: 4, height: 5), dark)
            ellipse(CGRect(x: 178, y: 62, width: 4, height: 5), dark)
            var smile = Path(); smile.move(to: CGPoint(x: 159, y: 80))
            smile.addQuadCurve(to: CGPoint(x: 176, y: 80), control: CGPoint(x: 168, y: celebrating ? 97 : 89))
            context.stroke(smile, with: .color(dark), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            line(CGPoint(x: 136, y: 114), CGPoint(x: 113, y: celebrating ? 73 : 100), skin, width: 13)
            ellipse(CGRect(x: 104, y: celebrating ? 64 : 92, width: 17, height: 19), skin)
            if celebrating {
                for point in [CGPoint(x: 219, y: 38), CGPoint(x: 97, y: 24), CGPoint(x: 285, y: 86)] {
                    line(CGPoint(x: point.x - 5, y: point.y), CGPoint(x: point.x + 5, y: point.y), palette.ink, width: 2)
                    line(CGPoint(x: point.x, y: point.y - 5), CGPoint(x: point.x, y: point.y + 5), palette.ink, width: 2)
                }
            }
        }
        .background(palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .scaleEffect(celebrating && !reduceMotion ? 1.015 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2), value: celebrating)
        .accessibilityHidden(true)
    }
}

struct StoryStampRow: View {
    let stamp: StoryPassport.Stamp
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.space.md) { markers }
            VStack(alignment: .leading, spacing: DS.space.sm) { markers }
        }
    }
    @ViewBuilder private var markers: some View {
        marker("Entdeckt", earned: stamp.collected, symbol: "photo")
        marker("Abgerufen", earned: stamp.recalled, symbol: "bubble.left")
        marker("Nach 7 Tagen", earned: stamp.remembered, symbol: "calendar")
    }
    private func marker(_ title: String, earned: Bool, symbol: String) -> some View {
        Label(title, systemImage: earned ? "checkmark.seal.fill" : symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(earned ? DS.accentText : DS.textSecondary)
            .accessibilityLabel("\(title): \(earned ? "erreicht" : "noch offen")")
    }
}

/// The companion remains present during retrieval; a correct saved response
/// produces one small tilt, not an ongoing animation or a reaction to errors.
struct StoryCompanion: View {
    let language: String
    var celebrating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, _ in
            let hair = Color(red: 0.18, green: 0.23, blue: 0.23)
            let skin = language == "ar" ? Color(red: 0.73, green: 0.47, blue: 0.32) : Color(red: 0.91, green: 0.67, blue: 0.48)
            func oval(_ rect: CGRect, _ color: Color) { context.fill(Path(ellipseIn: rect), with: .color(color)) }
            oval(CGRect(x: 0, y: 0, width: 44, height: 44), DS.accentSoft)
            oval(CGRect(x: 8, y: 4, width: 29, height: 36), hair)
            oval(CGRect(x: 11, y: 11, width: 23, height: 29), skin)
            oval(CGRect(x: 10, y: 6, width: 24, height: 12), hair)
            if language == "ar" { oval(CGRect(x: 28, y: 3, width: 13, height: 15), hair) }
            oval(CGRect(x: 16, y: 23, width: 2, height: 2.5), hair)
            oval(CGRect(x: 27, y: 23, width: 2, height: 2.5), hair)
            var smile = Path(); smile.move(to: CGPoint(x: 18, y: 31))
            smile.addQuadCurve(to: CGPoint(x: 27, y: 31), control: CGPoint(x: 22, y: celebrating ? 39 : 35))
            context.stroke(smile, with: .color(hair), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }.frame(width: 44, height: 44)
            .rotationEffect(.degrees(celebrating && !reduceMotion ? -7 : 0))
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2), value: celebrating)
            .accessibilityHidden(true)
    }
}

struct StoryPassportLink: View {
    let passport: StoryPassport
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space.md) {
                Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(DS.accentText)
                    .frame(width: 48, height: 48).background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dein Geschichtenpass").font(.headline).foregroundStyle(DS.textPrimary)
                    Text("\(passport.collectedCount) von \(passport.episodes.count) Postkarten entdeckt")
                        .font(.subheadline).foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DS.textSecondary)
            }.dsCard()
        }.buttonStyle(.plain).accessibilityIdentifier("story-passport-open")
    }
}
