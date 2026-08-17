import XCTest

final class LanguageLearningUITests: XCTestCase {
    private func launch(
        language: String = "ru",
        contentSize: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CUEFLOW_FORCE_STORE_RECOVERY"] = "1"
        app.launchEnvironment["CUEFLOW_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["CUEFLOW_ACTIVE_LANGUAGE"] = language
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    func testPrimaryJourneyStartsAndClosesCleanly() {
        let app = launch()
        let start = app.buttons["recommended-session-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()

        let close = app.buttons["practice-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    func testAllPrimaryTabsRemainDiscoverable() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Bibliothek"].exists)
        XCTAssertTrue(app.tabBars.buttons["Fortschritt"].exists)
        app.tabBars.buttons["Bibliothek"].tap()
        XCTAssertTrue(app.navigationBars["Bibliothek"].waitForExistence(timeout: 3))
    }

    func testAccessibilityTextSizeKeepsPrimaryActionReachable() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
        XCTAssertTrue(app.buttons["recommended-session-start"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["today-settings"].exists)
    }

    func testArabicConfigurationLoadsWithoutBreakingNavigation() {
        let app = launch(language: "ar")
        XCTAssertTrue(app.buttons["recommended-session-start"].waitForExistence(timeout: 8))
        app.buttons["today-settings"].tap()
        XCTAssertTrue(app.otherElements["active-language-picker"].waitForExistence(timeout: 4)
            || app.buttons["active-language-picker"].waitForExistence(timeout: 1))
    }

    func testConversationEntryOpensAndCloses() {
        let app = launch()
        XCTAssertTrue(app.buttons["recommended-session-start"].waitForExistence(timeout: 8))
        let entry = app.buttons["conversation-start"]
        for _ in 0..<3 where !entry.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Gespräch"].waitForExistence(timeout: 4))
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 4))
    }
}
