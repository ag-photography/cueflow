import SwiftUI
import WidgetKit

private struct CueFlowEntry: TimelineEntry {
    let date: Date
    let snapshot: CueFlowWidgetSnapshot
}

private struct CueFlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> CueFlowEntry {
        CueFlowEntry(date: .now, snapshot: .init(dueCount: 8, newCount: 3, languageLabel: "Russisch", updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (CueFlowEntry) -> Void) {
        completion(CueFlowEntry(date: .now, snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CueFlowEntry>) -> Void) {
        let entry = CueFlowEntry(date: .now, snapshot: load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func load() -> CueFlowWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: CueFlowWidgetSnapshot.suiteName),
              let data = defaults.data(forKey: CueFlowWidgetSnapshot.storageKey),
              let snapshot = try? JSONDecoder().decode(CueFlowWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}

private struct CueFlowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CueFlowEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.snapshot.dueCount), in: 0...Double(max(10, entry.snapshot.dueCount))) {
                Image(systemName: "quote.bubble.fill")
            } currentValueLabel: {
                Text("\(entry.snapshot.dueCount)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Text("CueFlow · \(entry.snapshot.dueCount) heute fällig")
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("CueFlow", systemImage: "quote.bubble.fill")
                        .font(.headline)
                    Spacer()
                    Text(entry.snapshot.languageLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entry.snapshot.dueCount)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.38, blue: 0.36))
                Text(entry.snapshot.dueCount == 1 ? "Ausdruck heute fällig" : "Ausdrücke heute fällig")
                    .font(.subheadline.weight(.semibold))
                if family == .systemMedium, entry.snapshot.newCount > 0 {
                    Text("Außerdem \(entry.snapshot.newCount) neue Ausdrücke verfügbar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(Color(red: 0.98, green: 0.96, blue: 0.90), for: .widget)
        }
    }
}

struct CueFlowWidget: Widget {
    let kind = "CueFlowPracticeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CueFlowProvider()) { entry in
            CueFlowWidgetView(entry: entry)
                .widgetURL(URL(string: "cueflow://practice"))
        }
        .configurationDisplayName("Heute sprechen")
        .description("Zeigt fällige Ausdrücke und öffnet direkt deine nächste Einheit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

@main
struct CueFlowWidgetBundle: WidgetBundle {
    var body: some Widget { CueFlowWidget() }
}
