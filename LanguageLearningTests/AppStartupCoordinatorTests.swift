import Testing
@testable import LanguageLearning

@MainActor
struct AppStartupCoordinatorTests {
    private enum Failure: Error { case setup }

    @Test func successfulPreparationBecomesReady() async {
        let coordinator = AppStartupCoordinator(preparation: {})

        await coordinator.start()

        #expect(coordinator.state == .ready)
    }

    @Test func preparationRunsOnlyOnce() async {
        var runs = 0
        let coordinator = AppStartupCoordinator(preparation: { runs += 1 })

        await coordinator.start()
        await coordinator.start()

        #expect(runs == 1)
        #expect(coordinator.state == .ready)
    }

    @Test func failedPreparationShowsRecoverableMessage() async {
        let coordinator = AppStartupCoordinator(preparation: { throw Failure.setup })

        await coordinator.start()

        guard case .failed(let message) = coordinator.state else {
            Issue.record("Expected failed startup state")
            return
        }
        #expect(message.contains("erneut"))
    }
}
