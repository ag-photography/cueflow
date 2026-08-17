import Foundation
import Testing
@testable import LanguageLearning

struct AppIntentRoutingTests {
    @Test func pendingActionIsConsumedExactlyOnce() throws {
        let suite = "CueFlowPendingActionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        CueFlowPendingAction.store(.conversation, defaults: defaults)

        #expect(CueFlowPendingAction.consume(defaults: defaults) == .conversation)
        #expect(CueFlowPendingAction.consume(defaults: defaults) == nil)
    }
}
