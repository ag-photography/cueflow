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

    /// Scrolls Heute until one of its activity tiles is reachable.
    ///
    /// The readiness wait is the whole point. The store opens asynchronously, so
    /// touching `app.scrollViews` before Heute is on screen fails hard — "no
    /// matches for ScrollView" — rather than retrying. Two tests scrolled first
    /// and only waited afterwards, which is why they failed whenever the store
    /// took a moment to open.
    @discardableResult
    private func activityTile(
        _ identifier: String,
        in app: XCUIApplication,
        maxScrolls: Int = 8
    ) -> XCUIElement {
        XCTAssertTrue(
            app.buttons["recommended-session-start"].waitForExistence(timeout: 15),
            "Heute never finished loading, so there is nothing to scroll"
        )
        let tile = app.buttons[identifier]
        var scrolls = 0
        while !tile.isHittable, scrolls < maxScrolls {
            app.scrollViews.firstMatch.swipeUp()
            scrolls += 1
        }
        return tile
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
        XCTAssertTrue(app.staticTexts["Was willst du als Nächstes können?"].waitForExistence(timeout: 5))
    }

    func testTabsRemainResponsiveWhileDestinationsLoad() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 8))

        app.tabBars.buttons["Bibliothek"].tap()
        XCTAssertTrue(app.navigationBars["Bibliothek"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Fortschritt"].tap()
        XCTAssertTrue(app.navigationBars["Fortschritt"].waitForExistence(timeout: 3))

        // Switching back exercises the already-materialized, warm-cache path.
        app.tabBars.buttons["Bibliothek"].tap()
        XCTAssertTrue(app.navigationBars["Bibliothek"].waitForExistence(timeout: 3))
    }

    func testTutorFocusCreatesAndStartsALessonScopedSession() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Bibliothek"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Bibliothek"].tap()

        let addFocus = app.buttons["tutor-focus-add"]
        XCTAssertTrue(addFocus.waitForExistence(timeout: 5))
        addFocus.tap()
        XCTAssertTrue(app.navigationBars["Tutor-Fokus"].waitForExistence(timeout: 3))

        let topic = app.textFields["z. B. Jahreszeiten"]
        XCTAssertTrue(topic.waitForExistence(timeout: 2))
        topic.tap()
        topic.typeText("Jahreszeiten")

        let phrases = app.textViews.firstMatch
        XCTAssertTrue(phrases.exists)
        phrases.tap()
        phrases.typeText("Frühling = весна\nSommer = лето")

        let save = app.buttons["tutor-focus-save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let practice = app.buttons["tutor-focus-practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 4))
        practice.tap()
        let close = app.buttons["practice-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertTrue(addFocus.waitForExistence(timeout: 4))
        addFocus.tap()
        let editDate = app.buttons["Termin bearbeiten"].firstMatch
        XCTAssertTrue(editDate.waitForExistence(timeout: 3))
        editDate.tap()
        XCTAssertTrue(app.buttons["tutor-focus-date-save"].waitForExistence(timeout: 3))
    }

    func testAccessibilityTextSizeKeepsPrimaryActionReachable() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
        XCTAssertTrue(app.buttons["recommended-session-start"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["today-settings"].exists)
    }

    func testProgressRecommendationStartsPractice() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Fortschritt"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Fortschritt"].tap()

        let recommendation = app.buttons["progress-recommended-practice"]
        XCTAssertTrue(recommendation.waitForExistence(timeout: 5))
        recommendation.tap()
        XCTAssertTrue(app.buttons["practice-close"].waitForExistence(timeout: 5))
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
        let entry = activityTile("conversation-start", in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Gespräch"].waitForExistence(timeout: 4))
        let cafe = app.buttons["roleplay-ru-cafe"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 3))
        cafe.tap()
        XCTAssertTrue(app.staticTexts["Deine Aufgabe"].waitForExistence(timeout: 3))
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 4))
    }

    func testLandscapeKeepsPrimaryActionReachable() {
        let app = launch()
        XCTAssertTrue(app.buttons["recommended-session-start"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["recommended-session-start"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["recommended-session-start"].isHittable)
        XCUIDevice.shared.orientation = .portrait
    }

    func testSkillPathIsDiscoverableFromToday() {
        let app = launch()
        let entry = activityTile("skill-path-start", in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        entry.tap()
        XCTAssertTrue(app.otherElements["skill-path"].waitForExistence(timeout: 4)
            || app.scrollViews.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Dein Weg ins Gespräch"].exists)
    }

    func testListeningLabOpensWithoutSpeechPermission() {
        let app = launch()
        let entry = activityTile("listening-lab-start", in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Hörstudio"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Schließen"].exists)
        // Both exercise types must be offered, not just meaning-recognition.
        XCTAssertTrue(app.buttons["Diktat"].exists || app.staticTexts["Diktat"].exists)
    }

    /// The reading pass is new in build 51 and had no coverage. On the tests'
    /// empty in-memory store nothing is stabilised, so the deterministic result
    /// is the empty state — which is exactly the branch worth pinning.
    func testReadingPassOpensAndExplainsItselfWhenNothingIsStabilised() {
        let app = launch()
        let entry = activityTile("reading-start", in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Lesen"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["Noch nicht genug gefestigt"].waitForExistence(timeout: 4),
            "An empty reading pass must say why it is empty"
        )
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 4))
    }
}
