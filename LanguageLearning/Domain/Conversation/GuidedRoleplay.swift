import Foundation

struct GuidedRoleplay: Identifiable, Equatable, Sendable {
    struct Step: Equatable, Sendable {
        struct Branch: Equatable, Sendable {
            let signals: [String]
            let partnerReply: String
        }

        let partnerText: String
        let learnerGoal: String
        let referenceAnswers: [String]
        let partnerReply: String
        let branches: [Branch]

        init(
            partnerText: String,
            learnerGoal: String,
            referenceAnswers: [String],
            partnerReply: String,
            branches: [Branch] = []
        ) {
            self.partnerText = partnerText
            self.learnerGoal = learnerGoal
            self.referenceAnswers = referenceAnswers
            self.partnerReply = partnerReply
            self.branches = branches
        }
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
        let normalizedAnswer = FuzzyMatcher.normalize(learnerText)
        let reply = step.branches.first(where: { branch in
            branch.signals.contains { normalizedAnswer.contains(FuzzyMatcher.normalize($0)) }
        })?.partnerReply ?? step.partnerReply
        return GuidedRoleplayProgress(
            support: support,
            partnerReply: reply,
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
        ),
        GuidedRoleplay(
            id: "ru-shopping",
            title: "Einkaufen",
            subtitle: "Fragen, wählen und bezahlen",
            systemImage: "bag.fill",
            languageCode: "ru",
            steps: [
                .init(partnerText: "Здравствуйте! Я могу вам помочь?", learnerGoal: "Sage, dass du ein Hemd suchst.", referenceAnswers: ["Я ищу рубашку."], partnerReply: "Какой цвет вы хотите?"),
                .init(
                    partnerText: "Какой цвет вы хотите?",
                    learnerGoal: "Wähle blau oder weiß.",
                    referenceAnswers: ["Синюю, пожалуйста.", "Белую, пожалуйста."],
                    partnerReply: "Хорошо, вот белая рубашка.",
                    branches: [
                        .init(signals: ["син"], partnerReply: "Хорошо, вот синяя рубашка."),
                        .init(signals: ["бел"], partnerReply: "Хорошо, вот белая рубашка.")
                    ]
                ),
                .init(partnerText: "Вот рубашка.", learnerGoal: "Frage, ob du sie anprobieren kannst.", referenceAnswers: ["Можно примерить?", "Я могу её примерить?"], partnerReply: "Конечно, примерочная там."),
                .init(partnerText: "Примерочная там.", learnerGoal: "Sage, dass sie gut passt.", referenceAnswers: ["Она хорошо сидит.", "Мне подходит."], partnerReply: "Отлично. Вы её берёте?"),
                .init(partnerText: "Вы её берёте?", learnerGoal: "Sage ja und frage nach Kartenzahlung.", referenceAnswers: ["Да. Можно оплатить картой?"], partnerReply: "Да, конечно.")
            ],
            closingText: "Спасибо за покупку!"
        ),
        GuidedRoleplay(
            id: "ru-hotel",
            title: "Im Hotel",
            subtitle: "Einchecken und Wichtiges klären",
            systemImage: "bed.double.fill",
            languageCode: "ru",
            steps: [
                .init(partnerText: "Добрый вечер! У вас есть бронь?", learnerGoal: "Sage, dass du eine Reservierung hast.", referenceAnswers: ["Да, у меня есть бронь."], partnerReply: "На какое имя?"),
                .init(partnerText: "На какое имя?", learnerGoal: "Nenne deinen Namen.", referenceAnswers: ["На имя Алекс Мюллер.", "Меня зовут Алекс Мюллер."], partnerReply: "Спасибо. Вы на две ночи?"),
                .init(partnerText: "Вы на две ночи?", learnerGoal: "Bestätige zwei Nächte.", referenceAnswers: ["Да, на две ночи."], partnerReply: "Вот ваш ключ. Завтрак с семи часов."),
                .init(partnerText: "Завтрак с семи часов.", learnerGoal: "Frage nach dem WLAN-Passwort.", referenceAnswers: ["Какой пароль от Wi-Fi?", "Скажите, пожалуйста, пароль от Wi-Fi."], partnerReply: "Пароль написан на ключе."),
                .init(partnerText: "Пароль написан на ключе.", learnerGoal: "Frage, wann du auschecken musst.", referenceAnswers: ["Во сколько нужно выехать?", "Когда выезд?"], partnerReply: "До одиннадцати часов.")
            ],
            closingText: "Приятного отдыха!"
        ),
        GuidedRoleplay(
            id: "ru-pharmacy",
            title: "In der Apotheke",
            subtitle: "Beschwerden erklären und nachfragen",
            systemImage: "cross.case.fill",
            languageCode: "ru",
            steps: [
                .init(partnerText: "Здравствуйте. Чем я могу помочь?", learnerGoal: "Sage, dass du Kopfschmerzen hast.", referenceAnswers: ["У меня болит голова.", "У меня головная боль."], partnerReply: "Как давно у вас болит голова?"),
                .init(partnerText: "Как давно?", learnerGoal: "Sage: seit heute Morgen.", referenceAnswers: ["С сегодняшнего утра.", "С утра."], partnerReply: "У вас есть температура?"),
                .init(partnerText: "У вас есть температура?", learnerGoal: "Sage, dass du kein Fieber hast.", referenceAnswers: ["Нет, температуры нет."], partnerReply: "У вас есть аллергия на лекарства?"),
                .init(partnerText: "Есть аллергия на лекарства?", learnerGoal: "Sage, dass dir keine bekannt ist.", referenceAnswers: ["Нет, насколько я знаю.", "Я не знаю ни о какой аллергии."], partnerReply: "Тогда можно принять эту таблетку."),
                .init(partnerText: "Можно принять эту таблетку.", learnerGoal: "Frage, wie oft du sie nehmen sollst.", referenceAnswers: ["Как часто её принимать?", "Сколько раз в день?"], partnerReply: "До двух раз в день после еды.")
            ],
            closingText: "Если не станет лучше, обратитесь к врачу."
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
        ),
        GuidedRoleplay(
            id: "ar-shopping",
            title: "Einkaufen",
            subtitle: "Fragen, wählen und bezahlen",
            systemImage: "bag.fill",
            languageCode: "ar",
            steps: [
                .init(partnerText: "مرحباً! هل أستطيع مساعدتك؟", learnerGoal: "Sage, dass du ein Hemd suchst.", referenceAnswers: ["أبحث عن قميص."], partnerReply: "أي لون تريد؟"),
                .init(
                    partnerText: "أي لون تريد؟",
                    learnerGoal: "Wähle blau oder weiß.",
                    referenceAnswers: ["الأزرق من فضلك.", "الأبيض من فضلك."],
                    partnerReply: "حسناً، هذا هو القميص الأبيض.",
                    branches: [
                        .init(signals: ["أزرق", "الأزرق"], partnerReply: "حسناً، هذا هو القميص الأزرق."),
                        .init(signals: ["أبيض", "الأبيض"], partnerReply: "حسناً، هذا هو القميص الأبيض.")
                    ]
                ),
                .init(partnerText: "هذا هو القميص.", learnerGoal: "Frage, ob du ihn anprobieren kannst.", referenceAnswers: ["هل يمكنني أن أقيسه؟"], partnerReply: "بالتأكيد، غرفة القياس هناك."),
                .init(partnerText: "غرفة القياس هناك.", learnerGoal: "Sage, dass er gut passt.", referenceAnswers: ["مقاسه مناسب.", "يناسبني جيداً."], partnerReply: "ممتاز. هل ستأخذه؟"),
                .init(partnerText: "هل ستأخذه؟", learnerGoal: "Sage ja und frage nach Kartenzahlung.", referenceAnswers: ["نعم. هل يمكنني الدفع بالبطاقة؟"], partnerReply: "نعم، بالتأكيد.")
            ],
            closingText: "شكراً لشرائك!"
        ),
        GuidedRoleplay(
            id: "ar-hotel",
            title: "Im Hotel",
            subtitle: "Einchecken und Wichtiges klären",
            systemImage: "bed.double.fill",
            languageCode: "ar",
            steps: [
                .init(partnerText: "مساء الخير! هل لديك حجز؟", learnerGoal: "Sage, dass du eine Reservierung hast.", referenceAnswers: ["نعم، لدي حجز."], partnerReply: "بأي اسم؟"),
                .init(partnerText: "بأي اسم؟", learnerGoal: "Nenne deinen Namen.", referenceAnswers: ["باسم أليكس مولر.", "اسمي أليكس مولر."], partnerReply: "شكراً. ستبقى ليلتين؟"),
                .init(partnerText: "ستبقى ليلتين؟", learnerGoal: "Bestätige zwei Nächte.", referenceAnswers: ["نعم، ليلتين."], partnerReply: "هذا مفتاحك. الإفطار من الساعة السابعة."),
                .init(partnerText: "الإفطار من الساعة السابعة.", learnerGoal: "Frage nach dem WLAN-Passwort.", referenceAnswers: ["ما كلمة مرور الواي فاي؟"], partnerReply: "كلمة المرور مكتوبة على المفتاح."),
                .init(partnerText: "كلمة المرور على المفتاح.", learnerGoal: "Frage, wann du auschecken musst.", referenceAnswers: ["متى يجب أن أغادر الغرفة؟", "متى تسجيل المغادرة؟"], partnerReply: "قبل الساعة الحادية عشرة.")
            ],
            closingText: "نتمنى لك إقامة سعيدة!"
        ),
        GuidedRoleplay(
            id: "ar-pharmacy",
            title: "In der Apotheke",
            subtitle: "Beschwerden erklären und nachfragen",
            systemImage: "cross.case.fill",
            languageCode: "ar",
            steps: [
                .init(partnerText: "مرحباً. كيف أستطيع مساعدتك؟", learnerGoal: "Sage, dass du Kopfschmerzen hast.", referenceAnswers: ["لدي صداع.", "رأسي يؤلمني."], partnerReply: "منذ متى لديك هذا الصداع؟"),
                .init(partnerText: "منذ متى؟", learnerGoal: "Sage: seit heute Morgen.", referenceAnswers: ["منذ هذا الصباح."], partnerReply: "هل لديك حمى؟"),
                .init(partnerText: "هل لديك حمى؟", learnerGoal: "Sage, dass du kein Fieber hast.", referenceAnswers: ["لا، ليست لدي حمى."], partnerReply: "هل لديك حساسية من أي دواء؟"),
                .init(partnerText: "هل لديك حساسية من أي دواء؟", learnerGoal: "Sage, dass dir keine bekannt ist.", referenceAnswers: ["لا، ليس حسب علمي."], partnerReply: "يمكنك أن تأخذ هذا القرص."),
                .init(partnerText: "يمكنك أن تأخذ هذا القرص.", learnerGoal: "Frage, wie oft du ihn nehmen sollst.", referenceAnswers: ["كم مرة آخذه؟", "كم مرة في اليوم؟"], partnerReply: "مرتين في اليوم بعد الطعام كحد أقصى.")
            ],
            closingText: "إذا لم تتحسن، راجع الطبيب."
        )
    ]
}
