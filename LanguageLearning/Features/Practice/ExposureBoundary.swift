import SwiftUI
import SwiftData

/// Legacy modes do not yet identify every expression encountered (a reading
/// passage can contain several). Conservatively invalidate the language's
/// delayed-probe window instead of claiming an unobserved seven-day gap.
struct ExposureBoundary: ViewModifier {
    var mode = "practice"
    var sessionID: UUID? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [AppSettings]
    @State private var failure: String?
    @State private var language: String?
    @State private var fallbackID = UUID()
    @State private var activeSince: Date?
    func body(content: Content) -> some View {
        content
            .onAppear { language = settings.first?.activeLanguageCode; activeSince = .now; record("started") }
            .onDisappear { record("paused") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { activeSince = .now; record("resumed") }
                else { record("paused"); activeSince = nil }
            }
            .alert("Lernverlauf nicht gespeichert", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("Erneut versuchen") { record() }
            } message: { Text(failure ?? "") }
    }
    private func record(_ event: String = "exposure") {
        do {
            guard let row = settings.first, let language else { return }
            var data = try row.readExperience()
            var dates = data.otherModeExposureAt ?? [:]
            dates[language] = .now
            data.otherModeExposureAt = dates
            if mode != "practice" {
                data.events.append(.init(name: mode + "_" + event, language: language,
                    sessionID: sessionID ?? fallbackID, timestamp: .now, stepID: nil,
                    activeSeconds: min(60, max(0, activeSince.map { Date.now.timeIntervalSince($0) } ?? 0))))
            }
            try row.writeExperience(data)
            try context.save()
            failure = nil
        } catch { context.rollback(); failure = error.localizedDescription }
    }
}
