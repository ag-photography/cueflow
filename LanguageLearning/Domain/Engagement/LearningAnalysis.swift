import Foundation

/// Descriptive, local-only metrics. Missing probes are not treated as failures
/// or silently removed from denominators. This is not a causal experiment.
struct LearningAnalysis {
    let runs: [EpisodeRun]
    let now: Date
    let events: [LocalLearningEvent]
    let cohortStart: Date?
    let cohortEnd: Date?
    init(experience: LearningExperience, language: String, now: Date = .now) {
        runs = experience.runs.filter { $0.language == language }
        self.now = now
        events = experience.events.filter { $0.language == language }
        cohortStart = experience.trial?.startedAt ?? (experience.runs.filter { $0.language == language }.map(\.startedAt)
            + experience.events.filter { $0.language == language && $0.name.hasSuffix("started") }.map(\.timestamp)).min()
        cohortEnd = experience.trial?.endedAt
    }
    var completed: Int { runs.filter { $0.completedAt != nil }.count }
    var paused: Int { runs.filter { $0.isOpen && now.timeIntervalSince($0.updatedAt) < 86_400 }.count }
    var abandoned: Int { runs.filter { $0.endedAt != nil || ($0.isOpen && now.timeIntervalSince($0.updatedAt) >= 86_400) }.count }
    var activeMinutes: Double { runs.compactMap(\.activeSeconds).reduce(0, +) / 60 }
    var attempts: [EpisodeAttempt] { runs.flatMap(\.attempts) }
    var retained: Int {
        runs.filter { $0.isDelayedCheck && ($0.exposureGapSeconds ?? 0) >= 7 * 86_400 }
            .reduce(0) { $0 + $1.attempts.filter { $0.stepID.hasPrefix("recall-") && $0.correct && !$0.supported }.count }
    }
    func returnStatus(day: Int, calendar: Calendar = .current) -> String {
        guard let first = cohortStart,
              let target = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: first)) else { return "not enrolled" }
        guard now >= target.addingTimeInterval(86_400) else { return "not yet observable" }
        if let cohortEnd, cohortEnd < target { return "not observed: opted out" }
        if now.timeIntervalSince(target) > 90 * 86_400 { return "raw-event window expired; cross-mode return unknown" }
        let recorded = runs.contains { run in
            run.attempts.contains { calendar.isDate($0.timestamp, inSameDayAs: target) }
        } || events.contains { LearningExperience.meaningfulEventNames.contains($0.name) && calendar.isDate($0.timestamp, inSameDayAs: target) }
        return recorded ? "returned with learning activity" : "no recorded learning activity (not proof of no app use)"
    }
    var report: String {
        let previews = Set(events.filter { $0.name == "today_story_preview" }.map(\.sessionID))
        let starts = Set(runs.map(\.id)).intersection(previews).count
        let practiceStarts = Set(events.filter { $0.name == "practice_started" }.map(\.sessionID)).count
        let practiceCompletions = Set(events.filter { $0.name == "practice_completed" }.map(\.sessionID)).count
        return """
        CueFlow descriptive pilot · policy 2
        Story-run counts below are separate from card/other-mode events. Return windows include recorded learning interactions across modes.
        Lifetime story totals (not cohort-filtered): started \(runs.count); completed \(completed); paused <24h \(paused); ended/idle >=24h \(abandoned)
        First answers: \(attempts.count); unaided correct: \(attempts.filter { $0.correct && !$0.supported }.count)
        Foreground active minutes (60-second idle cap per interaction): \(String(format: "%.1f", activeMinutes))
        Timing missing for legacy runs: \(runs.filter { $0.activeSeconds == nil }.count)
        Completed delayed checks: \(runs.filter { $0.isDelayedCheck && $0.completedAt != nil }.count)
        >=7-day gap unaided answers: \(retained)
        D7: \(returnStatus(day: 7)); D28: \(returnStatus(day: 28))
        Today story preview→new start (last 90d, resumes and other entry points excluded): \(starts)/\(previews.count)
        Card plans (last 90d): started \(practiceStarts), completed \(practiceCompletions)
        Card answers (last 90d): \(events.filter { $0.name == "practice_answer" }.count)
        Other-mode learning interactions (last 90d, not verified recall): \(events.filter { LearningExperience.meaningfulEventNames.contains($0.name) && $0.name != "practice_answer" }.count)
        Non-story capped foreground minutes (last 90d): \(String(format: "%.1f", events.compactMap(\.activeSeconds).reduce(0, +) / 60))
        Local cohort assignment is not an analysed controlled result. No causal learning-speed, conversation-proficiency or Instagram-substitution claim.
        """
    }
}

@MainActor
enum ExposureMatchedAnalysis {
    /// Export only bucket totals, never phrase text, identifiers or answers.
    /// Comparable exposure strata are descriptive, not a controlled result.
    static func report(reviews: [Review], since: Date?, until: Date? = nil) -> String {
        guard let since else { return "Exposure strata unavailable: no prospective enrolment." }
        let groups = Dictionary(grouping: reviews.filter { $0.card != nil }, by: { $0.card!.contentID })
        var buckets: [Int: (attempts: Int, correct: Int, delayed: Int)] = [:]
        for history in groups.values {
            let ordered = history.sorted { $0.timestamp < $1.timestamp }
            for (index, review) in ordered.enumerated() where review.timestamp >= since && review.timestamp <= (until ?? .distantFuture) {
                guard let evidence = review.evidence, evidence.support == .none, review.gradeTier > 0 else { continue }
                let key = min(3, index)
                var bucket = buckets[key] ?? (0, 0, 0)
                bucket.attempts += 1
                if evidence.assessedCorrect { bucket.correct += 1 }
                if index > 0 && review.timestamp.timeIntervalSince(ordered[index - 1].timestamp) >= 7 * 86_400 { bucket.delayed += 1 }
                buckets[key] = bucket
            }
        }
        return (0...3).map { count in
            let value = buckets[count] ?? (0, 0, 0)
            return "Prior recorded exposures \(count == 3 ? "3+" : String(count)): attempts \(value.attempts), correct \(value.correct), >=7d review gaps \(value.delayed)"
        }.joined(separator: "\n") + "\nReview gaps exclude untracked external exposure; unknown exposure remains a limitation. No per-phrase identifiers exported."
    }
}

@MainActor
enum ComparableSubmissionTiming {
    private struct Key: Hashable {
        let card: ContentID
        let mode: String
        let spoken: Bool
        let words: Int
    }
    static func report(reviews: [Review]) -> String {
        let comparable = reviews.filter {
            $0.card != nil && $0.rating >= 3 && $0.evidence?.support == AttemptEvidence.Support.none
                && $0.evidence?.assessedCorrect == true && $0.evidence?.timingInterrupted == false
                && $0.evidence?.inputAvailableMs != nil && $0.responseTimeMs > 0 && !$0.userAnswer.isEmpty
        }
        let groups = Dictionary(grouping: comparable) { item in
            Key(card: item.card!.contentID, mode: item.modeRaw, spoken: item.evidence?.inputWasSpeech ?? false,
                words: item.userAnswer.split(whereSeparator: \.isWhitespace).count)
        }.values.filter { $0.count >= 6 }
        let quicker = groups.filter { values in
            let ordered = values.sorted { $0.timestamp < $1.timestamp }
            let first = ordered.prefix(3).map(\.responseTimeMs).sorted()[1]
            let latest = ordered.suffix(3).map(\.responseTimeMs).sorted()[1]
            return latest < first
        }.count
        return "Comparable submission groups (same phrase, mode, input route and answer word count; 3 early vs 3 recent successes): \(groups.count); lower recent median: \(quicker). Input availability is a keyboard/ASR callback, not true speech onset. Submission timing still includes reading/ASR; grading wait is recorded separately. Not a fluency or causal learning-speed result."
    }
}
