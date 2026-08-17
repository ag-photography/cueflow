import Foundation
import Testing
@testable import LanguageLearning

struct PlatformServicesTests {
    @Test func widgetSnapshotRoundTripsWithoutModelDependencies() throws {
        let original = CueFlowWidgetSnapshot(
            dueCount: 12,
            newCount: 4,
            languageLabel: "Arabisch",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let decoded = try JSONDecoder().decode(
            CueFlowWidgetSnapshot.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    @Test func feedbackReportExplicitlyExcludesPrivateLearningContent() {
        let report = MetricsDiagnosticsService.shared.feedbackReport(storageMode: .local)
        #expect(report.contains("keine Lerninhalte"))
        #expect(report.contains("Speicher: local"))
        #expect(!report.contains("userAnswer"))
    }
}
