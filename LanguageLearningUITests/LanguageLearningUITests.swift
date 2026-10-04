import XCTest

final class LanguageLearningUITests: XCTestCase {
    func testNewExpressionHasAnUnscoredDiscoveryStep() {
        for language in ["ru", "ar"] {
            let app = launch(language: language, appearance: language == "ru" ? "Dark" : "Light")
            app.buttons["today-primary-start"].tap()
            let discover = app.buttons["practice-discovery-next"]
            XCTAssertTrue(discover.waitForExistence(timeout: 8))
            let preview = XCTAttachment(screenshot: app.screenshot())
            preview.name = "Discovery — \(language)"; preview.lifetime = .keepAlways; add(preview)
            discover.tap()
            XCTAssertTrue(app.descendants(matching: .any)["practice-instruction"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["1 von 10"].exists, "Discovery must not consume an opportunity")
            XCTAssertFalse(discover.exists)
            let choices = XCTAttachment(screenshot: app.screenshot())
            choices.name = "Recognition — \(language)"; choices.lifetime = .keepAlways; add(choices)
            app.buttons["practice-close"].tap()
            app.buttons["today-primary-start"].tap()
            XCTAssertTrue(app.staticTexts["Schau dir die Formulierung an und probiere sie aus."].waitForExistence(timeout: 5),
                          "An interrupted model exposure must resume with support, not unaided recall")
            XCTAssertFalse(discover.exists)
            app.terminate()
        }
    }

    func testQuietPracticeKeepsFeedbackAndContinueReachable() {
        for language in ["ru", "ar"] {
            let app = launch(language: language,
                contentSize: language == "ar" ? "UICTContentSizeCategoryAccessibilityXXXL" : nil,
                appearance: language == "ru" ? "Dark" : "Light")
            app.buttons["today-settings"].tap()
            let rhythm = app.buttons["Mein Lernrhythmus"]
            for _ in 0..<5 where !rhythm.isHittable { app.swipeUp() }
            XCTAssertTrue(rhythm.waitForExistence(timeout: 5))
            rhythm.tap()
            let quiet = app.switches["Leise starten"]
            for _ in 0..<5 where !quiet.isHittable { app.swipeUp() }
            XCTAssertTrue(quiet.waitForExistence(timeout: 5))
            if quiet.value as? String == "0" {
                // SwiftUI exposes the whole Form row as a switch; its centre
                // can be the label rather than the trailing toggle control.
                quiet.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: quiet)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed)
            app.navigationBars["Mein Lernrhythmus"].buttons.firstMatch.tap()
            app.buttons["Mein Lernrhythmus"].tap()
            XCTAssertTrue(app.switches["Leise starten"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.switches["Leise starten"].value as? String, "1")
            app.navigationBars["Mein Lernrhythmus"].buttons.firstMatch.tap()
            app.buttons["Fertig"].tap()
            let start = app.buttons["today-primary-start"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            start.tap()
            let input = app.textFields.firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 8))
            input.tap()
            input.typeText("xyz\n")
            let next = app.buttons["practice-continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            XCTAssertTrue(next.isHittable)
            let feedback = XCTAttachment(screenshot: app.screenshot())
            feedback.name = "Practice feedback — \(language)"; feedback.lifetime = .keepAlways; add(feedback)
            next.tap()
            XCTAssertFalse(next.waitForExistence(timeout: 1))
            app.terminate()
        }
    }

    func testIllustratedTodayAndPassportInBothAppearances() {
        for appearance in ["Light", "Dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["today-primary-start"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["today-primary-start"].isHittable)
            XCTAssertFalse(app.buttons["story-passport-open"].exists)
            XCTAssertFalse(app.buttons["sprint-start"].exists)
            XCTAssertFalse(app.buttons["Deine Ziele & Lernmomente"].exists)
            let home = XCTAttachment(screenshot: app.screenshot())
            home.name = "Illustrated Today — \(appearance)"; home.lifetime = .keepAlways; add(home)
            openOtherPractice(in: app)
        let collection = app.buttons["Alle Situationen"]
            collection.tap()
            XCTAssertTrue(app.navigationBars["Deine Situationen"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["0 von 6 Situationen geübt"].exists)
            let passport = XCTAttachment(screenshot: app.screenshot())
            passport.name = "Story passport — \(appearance)"; passport.lifetime = .keepAlways; add(passport)
            app.buttons["Fertig"].tap()
            app.terminate()
        }
    }
    func testOptionalCalibrationStartsWithoutShowingAModel() {
        let app = launch()
        XCTAssertTrue(app.buttons["today-settings"].waitForExistence(timeout: 8))
        app.buttons["today-settings"].tap()
        let rhythm = app.buttons["Mein Lernrhythmus"]
        XCTAssertTrue(rhythm.waitForExistence(timeout: 4))
        rhythm.tap()
        let calibration = app.buttons["Startcheck ausprobieren"]
        for _ in 0..<4 where !calibration.isHittable { app.swipeUp() }
        XCTAssertTrue(calibration.exists)
        calibration.tap()
        XCTAssertTrue(app.buttons["episode-check"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["episode-next"].exists)
        XCTAssertTrue(app.buttons["Formulierung zeigen"].exists)
    }

    func testStoryAcceptsUnaidedTypedRussianAnswer() {
        let app = launch()
        openOtherPractice(in: app)
        let collection = app.buttons["Alle Situationen"]
        XCTAssertTrue(collection.waitForExistence(timeout: 15))
        collection.tap()
        XCTAssertTrue(app.navigationBars["Deine Situationen"].waitForExistence(timeout: 5))
        let episode = app.buttons["episode-ru-seasons-1"]
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        episode.tap()
        let next = app.buttons["episode-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["Eine zweite Möglichkeit"].waitForExistence(timeout: 5))
        next.tap()
        let quiet = app.switches["Leise üben"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 5))
        if quiet.value as? String == "0" { quiet.tap() }
        let answer = app.descendants(matching: .any).matching(identifier: "episode-answer").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        answer.typeText("Я люблю осень.")
        app.buttons["episode-check"].tap()
        XCTAssertTrue(app.staticTexts["Formulierung getroffen"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["Ich mag den Winter."].waitForExistence(timeout: 5))
    }

    func testStoryResumesAtSavedStepAndCompletesWithoutMicrophone() {
        let app = launch()
        openOtherPractice(in: app)
        let start = app.buttons["episode-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let next = app.buttons["episode-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["Eine zweite Möglichkeit"].waitForExistence(timeout: 5))
        next.tap()
        let quiet = app.switches["Leise üben"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 3))
        if quiet.value as? String == "0" { quiet.tap() }
        let skip = app.buttons["Noch unsicher · gemeinsam weiter"]
        if !skip.isHittable { app.scrollViews.firstMatch.swipeUp() }
        skip.tap()
        next.tap()
        app.buttons["episode-close"].tap()
        openOtherPractice(in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["episode-check"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["episode-next"].exists, "Resume must not replay the model or completed answer")
        for _ in 0..<2 {
            if !skip.isHittable { app.scrollViews.firstMatch.swipeUp() }
            skip.tap()
            next.tap()
        }
        let finish = app.buttons["episode-finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Eine weitere Situation geübt"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Story completion — quiet, supported answers"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        finish.tap()
        openOtherPractice(in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["Alle Situationen"].tap()
        XCTAssertTrue(app.staticTexts["1 von 6 Situationen geübt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 ohne Hilfe · 0 nach mindestens 7 Tagen abgerufen"].exists)
    }

    func testArabicStorySupportsLargeText() {
        let app = launch(language: "ar", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openOtherPractice(in: app)
        let start = app.buttons["episode-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        // Native accessibility scrolling brings the exact button into view;
        // full-page swipes can skip it at the largest Dynamic Type size.
        start.tap()
        let next = app.buttons["episode-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["Eine zweite Möglichkeit"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic story — accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["episode-close"].tap()
    }

    private func launch(
        language: String = "ru",
        contentSize: String? = nil,
        appearance: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CUEFLOW_FORCE_STORE_RECOVERY"] = "1"
        app.launchEnvironment["CUEFLOW_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["CUEFLOW_ACTIVE_LANGUAGE"] = language
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        if let appearance { app.launchEnvironment["CUEFLOW_TEST_APPEARANCE"] = appearance }
        app.launch()
        // Each launch intentionally builds a new complete in-memory library.
        // Keep this fixture-readiness allowance separate from the 3-second
        // tab-transition assertions below; it is not a cold-launch benchmark.
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 45), "Fresh test library did not become ready")
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
            app.buttons["today-primary-start"].waitForExistence(timeout: 15),
            "Heute never finished loading, so there is nothing to scroll"
        )
        openOtherPractice(in: app)
        return app.buttons[identifier]
    }

    private func openOtherPractice(in app: XCUIApplication) {
        let other = app.buttons["today-other-practice"]
        XCTAssertTrue(other.waitForExistence(timeout: 15))
        other.tap()
    }

    func testPrimaryJourneyStartsAndClosesCleanly() {
        let app = launch()
        let start = app.buttons["today-primary-start"]
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

        app.tabBars.buttons["Heute"].tap()
        let quickRound = app.buttons["today-primary-start"]
        for _ in 0..<5 where !quickRound.isHittable { app.swipeUp() }
        XCTAssertTrue(quickRound.waitForExistence(timeout: 5))
        let invitation = XCTAttachment(screenshot: app.screenshot())
        invitation.name = "Tutor quick round invitation"; invitation.lifetime = .keepAlways; add(invitation)
        quickRound.tap()
        XCTAssertTrue(app.buttons["practice-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["practice-tutor-context"].exists)
        let tutorRound = XCTAttachment(screenshot: app.screenshot())
        tutorRound.name = "Tutor quick round from Today"; tutorRound.lifetime = .keepAlways; add(tutorRound)
        app.buttons["practice-close"].tap()
        openOtherPractice(in: app)
        let manage = app.buttons["Unterricht verwalten"]
        XCTAssertTrue(manage.waitForExistence(timeout: 4))
        for _ in 0..<3 where !manage.isHittable { app.swipeUp() }
        manage.tap()
        let editDate = app.buttons["Termin bearbeiten"].firstMatch
        XCTAssertTrue(editDate.waitForExistence(timeout: 3))
        editDate.tap()
        XCTAssertTrue(app.buttons["tutor-focus-date-save"].waitForExistence(timeout: 3))
    }

    func testAccessibilityTextSizeKeepsPrimaryActionReachable() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
        XCTAssertTrue(app.buttons["today-primary-start"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.buttons["today-primary-start"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.buttons["today-primary-start"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["today-primary-start"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["today-primary-start"].isHittable)
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
