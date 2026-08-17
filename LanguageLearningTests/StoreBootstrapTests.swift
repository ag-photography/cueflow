import Foundation
import Testing
@testable import LanguageLearning

struct StoreBootstrapTests {
    private enum TestError: Error { case persistent, fallback }

    @Test func persistentStoreSuccessDoesNotCreateFallback() throws {
        var fallbackWasCalled = false
        let result = try StoreBootstrap.resolve {
            "persistent"
        } fallback: {
            fallbackWasCalled = true
            return "fallback"
        }

        #expect(result.value == "persistent")
        #expect(result.usedFallback == false)
        #expect(fallbackWasCalled == false)
    }

    @Test func persistentStoreFailureCreatesSafeFallback() throws {
        let result = try StoreBootstrap.resolve {
            throw TestError.persistent
        } fallback: {
            "fallback"
        }

        #expect(result.value == "fallback")
        #expect(result.usedFallback)
        #expect(result.persistentError is TestError)
    }

    @Test func fallbackFailureStillSurfacesAnError() {
        #expect(throws: TestError.fallback) {
            try StoreBootstrap.resolve {
                throw TestError.persistent
            } fallback: {
                throw TestError.fallback
            }
        }
    }

    @Test func forcedRecoveryBuildsAnEphemeralContainer() throws {
        let result = try StoreBootstrap.make(forceRecovery: true)

        #expect(result.isRecovering)
        #expect(result.mode == .recovery)
        #expect(result.recoveryMessage?.contains("sicheren Sitzung") == true)
    }

    @Test func persistentStoreParentExistsBeforeSwiftDataOpensIt() throws {
        let url = try StoreBootstrap.persistentStoreURL()
        var isDirectory: ObjCBool = false

        #expect(url.lastPathComponent == "LanguageLearning.store")
        #expect(FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }
}
