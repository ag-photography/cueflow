import Foundation

/// Surface forms that no suffix rule can reach.
///
/// This is deliberately **not** a lemmatiser, and the distinction matters.
/// Three general approaches were measured and rejected:
///
/// - `NLTagger` with `.lemma` returns nothing at all for Russian or Arabic —
///   Apple's on-device lemmatiser does not cover these languages (0/20 on the
///   forms below).
/// - A Snowball-style Russian stemmer unified only 7 of 16 hard pairs, and those
///   seven were ones `ClozeBuilder`'s prefix rule already handled. It fails on
///   precisely the stem-changing cases (быть/была, ходить/хожу, угол/углу)
///   because they are suppletive or involve fleeting vowels.
/// - A real morphological analyser needs a multi-megabyte inflection dictionary,
///   which is a content-acquisition problem rather than an algorithm.
///
/// What makes a table workable instead is that the vocabulary is **closed**: the
/// app ships a fixed corpus, so the forms that need resolving are finite and
/// known. Every pair below was harvested from `example-sentences.json`, where the
/// headword and the sentence written for it are both given — so the mapping is
/// verified by construction, not inferred.
///
/// Prefix matching already covers 96.7 % of the Russian corpus. These are the
/// remaining 60.
enum IrregularForms {
    /// Keys and values are `ClozeBuilder.compareKey`-folded: lowercase, no
    /// stress marks.
    private static let byHeadword: [String: [String]] = [
        // stem-changing and suppletive verbs
        "бояться": ["боюсь"],
        "начать": ["начнём", "начнем"],
        "снять": ["сними"],
        "пользоваться": ["пользуюсь"],
        "касаться": ["касайся"],
        "оставаться": ["остаюсь"],
        "требоваться": ["требуются"],
        "учиться": ["учусь"],
        "появиться": ["появилась"],
        "являться": ["является"],
        "есть": ["ем"],
        "ехать": ["едем"],
        "следовать": ["следуйте"],
        "требовать": ["требуют"],
        "вести": ["ведёт", "ведет"],
        "давать": ["даю"],
        "родиться": ["родился"],
        "идти": ["иду"],
        "ходить": ["хожу"],
        "удаться": ["удалось"],
        "считаться": ["считается"],
        "случиться": ["случилось"],
        "жениться": ["женился"],
        "взяться": ["взялись"],
        "надеяться": ["надеюсь"],
        "слышать": ["слышишь"],
        "мочь": ["могу"],
        "смеяться": ["смеялись"],
        "учить": ["учу"],
        "поехать": ["поедем"],
        "придтись": ["придётся", "придется"],
        "прийтись": ["пришлось"],
        "брать": ["беру"],
        "спать": ["спит"],
        "писать": ["пишу"],
        "видеть": ["вижу"],
        "стараться": ["старается"],
        "двигаться": ["двигалась"],
        "держаться": ["держись"],
        "найтись": ["нашлись"],
        "оказаться": ["оказалось"],
        "сесть": ["сядь"],
        "собраться": ["собрались"],
        "приняться": ["принялась"],
        "броситься": ["бросилась"],
        "носить": ["ношу"],
        "пить": ["пью"],
        "пытаться": ["пытаюсь"],
        "иметься": ["имеется"],
        "делаться": ["делается"],
        "жить": ["живу"],
        "хотеть": ["хочу"],
        "хотеться": ["хочется"],
        "прислать": ["пришли"],
        "удивиться": ["удивилась"],
        // nouns with a fleeting vowel or consonant alternation
        "угол": ["углу"],
        "май": ["мае"],
        "щека": ["щёку", "щеку"],
        // adjectives and pronouns whose short stem defeats the ratio test
        "злой": ["злая"],
        "кой": ["коем"],
        // `быть` is fully suppletive and turns up constantly, so its paradigm is
        // listed rather than only the one observed form. Note `есть` is
        // deliberately absent: it collides with the verb "to eat".
        "быть": ["был", "была", "было", "были", "буду", "будет", "будем", "будут", "будете", "будешь"],
    ]

    private static let byForm: [String: String] = {
        var result: [String: String] = [:]
        for (headword, forms) in byHeadword {
            for form in forms where result[form] == nil {
                result[form] = headword
            }
        }
        return result
    }()

    /// Known surface forms of a headword, or empty when it inflects regularly.
    static func forms(ofHeadword key: String) -> [String] {
        byHeadword[key] ?? []
    }

    /// The headword a surface form belongs to, when the form is irregular enough
    /// to be listed here.
    static func headword(forForm key: String) -> String? {
        byForm[key]
    }

    /// Every listed form, for callers that want to expand a known vocabulary.
    static func allForms(ofHeadwords keys: some Sequence<String>) -> [String] {
        keys.flatMap { forms(ofHeadword: $0) }
    }
}
