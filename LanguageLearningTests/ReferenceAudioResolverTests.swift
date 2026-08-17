import Testing
@testable import LanguageLearning

struct ReferenceAudioResolverTests {
    @Test func prefersExistingHumanRecording() {
        let source = ReferenceAudioResolver.source(
            audioFileName: "hello.m4a", locale: "ru-RU", fileExists: { $0 == "hello.m4a" }
        )
        #expect(source == .bundled(fileName: "hello.m4a"))
    }

    @Test func fallsBackToLocaleAwareSynthesis() {
        let source = ReferenceAudioResolver.source(
            audioFileName: "missing.m4a", locale: "ar-SA", fileExists: { _ in false }
        )
        #expect(source == .synthesized(locale: "ar-SA"))
    }
}
