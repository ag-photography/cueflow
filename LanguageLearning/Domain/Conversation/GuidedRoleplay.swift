import Foundation

struct GuidedRoleplay: Identifiable, Equatable, Sendable {
    struct Step: Equatable, Sendable {
        let partnerText: String
        let learnerGoal: String
        let referenceAnswers: [String]
        let partnerReply: String
    }

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let languageCode: String
    let steps: [Step]
    let closingText: String

    var openingText: String { steps.first?.partnerText ?? closingText }
}

struct GuidedRoleplayProgress: Equatable, Sendable {
    enum Support: Equatable, Sendable {
        case independent
        case close(reference: String)
        case model(reference: String)
    }

    let support: Support
    let partnerReply: String
    let nextPartnerText: String?
    let isComplete: Bool
}

enum GuidedRoleplayEngine {
    static func progress(
        scenario: GuidedRoleplay,
        stepIndex: Int,
        learnerText: String
    ) -> GuidedRoleplayProgress? {
        guard scenario.steps.indices.contains(stepIndex) else { return nil }
        let step = scenario.steps[stepIndex]
        let support = support(for: learnerText, references: step.referenceAnswers)
        let nextIndex = stepIndex + 1
        return GuidedRoleplayProgress(
            support: support,
            partnerReply: step.partnerReply,
            nextPartnerText: scenario.steps.indices.contains(nextIndex)
                ? scenario.steps[nextIndex].partnerText
                : nil,
            isComplete: nextIndex >= scenario.steps.count
        )
    }

    /// This signal only decides how much scaffolding to show. It deliberately
    /// does not claim semantic correctness: a valid free-form answer can differ
    /// from every authored reference.
    static func support(for learnerText: String, references: [String]) -> GuidedRoleplayProgress.Support {
        let actual = FuzzyMatcher.normalize(learnerText)
        guard let first = references.first else { return .independent }
        if references.contains(where: { FuzzyMatcher.normalize($0) == actual }) {
            return .independent
        }
        let closest = references.min { lhs, rhs in
            FuzzyMatcher.wordEditAnalysis(expected: lhs, actual: learnerText).totalEdits
                < FuzzyMatcher.wordEditAnalysis(expected: rhs, actual: learnerText).totalEdits
        } ?? first
        let analysis = FuzzyMatcher.wordEditAnalysis(expected: closest, actual: learnerText)
        if analysis.editedWords <= 1 && analysis.totalEdits <= 2 {
            return .close(reference: closest)
        }
        return .model(reference: closest)
    }
}

enum GuidedRoleplayLibrary {
    static func scenarios(languageCode: String) -> [GuidedRoleplay] {
        languageCode == "ar" ? arabic : russian
    }

    private static let russian: [GuidedRoleplay] = [
        GuidedRoleplay(
            id: "ru-cafe",
            title: "Im Café",
            subtitle: "Bestellen, ergänzen und bezahlen",
            systemImage: "cup.and.saucer.fill",
            languageCode: "ru",
            steps: [
                .init(
                    partnerText: "Здравствуйте! Что вы хотите заказать?",
                    learnerGoal: "Bestelle einen Kaffee, bitte.",
                    referenceAnswers: ["Кофе, пожалуйста.", "Я хотел бы кофе, пожалуйста."],
                    partnerReply: "Конечно. Что-нибудь ещё?"
                ),
                .init(
                    partnerText: "Что-нибудь ещё?",
                    learnerGoal: "Sage, dass das alles ist.",
                    referenceAnswers: ["Нет, спасибо. Это всё.", "Это всё, спасибо."],
                    partnerReply: "Хорошо. С вас три евро."
                ),
                .init(
                    partnerText: "С вас три евро.",
                    learnerGoal: "Bedanke dich.",
                    referenceAnswers: ["Спасибо.", "Большое спасибо."],
                    partnerReply: "Пожалуйста!"
                )
            ],
            closingText: "Пожалуйста! Хорошего дня!"
        ),
        GuidedRoleplay(
            id: "ru-meeting",
            title: "Kennenlernen",
            subtitle: "Begrüßen und sich vorstellen",
            systemImage: "person.2.fill",
            languageCode: "ru",
            steps: [
                .init(
                    partnerText: "Привет! Как тебя зовут?",
                    learnerGoal: "Stelle dich mit deinem Namen vor.",
                    referenceAnswers: ["Меня зовут Алекс.", "Я Алекс."],
                    partnerReply: "Очень приятно! Откуда ты?"
                ),
                .init(
                    partnerText: "Откуда ты?",
                    learnerGoal: "Sage, dass du aus Deutschland kommst.",
                    referenceAnswers: ["Я из Германии."],
                    partnerReply: "Здорово! Ты говоришь по-русски?"
                ),
                .init(
                    partnerText: "Ты говоришь по-русски?",
                    learnerGoal: "Sage: ein bisschen.",
                    referenceAnswers: ["Немного.", "Я немного говорю по-русски."],
                    partnerReply: "Отлично!"
                )
            ],
            closingText: "Очень приятно познакомиться!"
        ),
        GuidedRoleplay(
            id: "ru-directions",
            title: "Unterwegs",
            subtitle: "Nach dem Weg fragen",
            systemImage: "map.fill",
            languageCode: "ru",
            steps: [
                .init(
                    partnerText: "Здравствуйте! Вам помочь?",
                    learnerGoal: "Frage, wo die Metro ist.",
                    referenceAnswers: ["Где метро?", "Скажите, пожалуйста, где метро?"],
                    partnerReply: "Метро прямо и потом направо."
                ),
                .init(
                    partnerText: "Метро прямо и потом направо.",
                    learnerGoal: "Frage, ob es weit ist.",
                    referenceAnswers: ["Это далеко?"],
                    partnerReply: "Нет, пять минут пешком."
                ),
                .init(
                    partnerText: "Пять минут пешком.",
                    learnerGoal: "Bedanke dich für die Hilfe.",
                    referenceAnswers: ["Спасибо за помощь.", "Большое спасибо."],
                    partnerReply: "Не за что!"
                )
            ],
            closingText: "Счастливого пути!"
        )
    ]

    private static let arabic: [GuidedRoleplay] = [
        GuidedRoleplay(
            id: "ar-cafe",
            title: "Im Café",
            subtitle: "Bestellen, ergänzen und bezahlen",
            systemImage: "cup.and.saucer.fill",
            languageCode: "ar",
            steps: [
                .init(
                    partnerText: "مرحباً! ماذا تريد أن تطلب؟",
                    learnerGoal: "Bestelle einen Kaffee, bitte.",
                    referenceAnswers: ["قهوة من فضلك."],
                    partnerReply: "بالتأكيد. هل تريد شيئاً آخر؟"
                ),
                .init(
                    partnerText: "هل تريد شيئاً آخر؟",
                    learnerGoal: "Sage: nein, danke.",
                    referenceAnswers: ["لا، شكراً.", "هذا كل شيء، شكراً."],
                    partnerReply: "حسناً. الحساب ثلاثة يورو."
                ),
                .init(
                    partnerText: "الحساب ثلاثة يورو.",
                    learnerGoal: "Bedanke dich.",
                    referenceAnswers: ["شكراً.", "شكراً جزيلاً."],
                    partnerReply: "عفواً!"
                )
            ],
            closingText: "عفواً! يوم سعيد!"
        ),
        GuidedRoleplay(
            id: "ar-meeting",
            title: "Kennenlernen",
            subtitle: "Begrüßen und sich vorstellen",
            systemImage: "person.2.fill",
            languageCode: "ar",
            steps: [
                .init(
                    partnerText: "مرحباً! ما اسمك؟",
                    learnerGoal: "Stelle dich mit deinem Namen vor.",
                    referenceAnswers: ["اسمي أليكس.", "أنا أليكس."],
                    partnerReply: "تشرفت بمعرفتك! من أين أنت؟"
                ),
                .init(
                    partnerText: "من أين أنت؟",
                    learnerGoal: "Sage, dass du aus Deutschland kommst.",
                    referenceAnswers: ["أنا من ألمانيا."],
                    partnerReply: "جميل! هل تتكلم العربية؟"
                ),
                .init(
                    partnerText: "هل تتكلم العربية؟",
                    learnerGoal: "Sage: ein bisschen.",
                    referenceAnswers: ["قليلاً.", "أتكلم العربية قليلاً."],
                    partnerReply: "ممتاز!"
                )
            ],
            closingText: "تشرفت بمعرفتك!"
        ),
        GuidedRoleplay(
            id: "ar-directions",
            title: "Unterwegs",
            subtitle: "Nach dem Weg fragen",
            systemImage: "map.fill",
            languageCode: "ar",
            steps: [
                .init(
                    partnerText: "مرحباً! هل تحتاج إلى مساعدة؟",
                    learnerGoal: "Frage, wo die Metro ist.",
                    referenceAnswers: ["أين المترو؟", "من فضلك، أين المترو؟"],
                    partnerReply: "المترو إلى الأمام ثم إلى اليمين."
                ),
                .init(
                    partnerText: "المترو إلى الأمام ثم إلى اليمين.",
                    learnerGoal: "Frage, ob es weit ist.",
                    referenceAnswers: ["هل هو بعيد؟"],
                    partnerReply: "لا، خمس دقائق مشياً."
                ),
                .init(
                    partnerText: "خمس دقائق مشياً.",
                    learnerGoal: "Bedanke dich für die Hilfe.",
                    referenceAnswers: ["شكراً على المساعدة.", "شكراً جزيلاً."],
                    partnerReply: "عفواً!"
                )
            ],
            closingText: "رحلة سعيدة!"
        )
    ]
}
