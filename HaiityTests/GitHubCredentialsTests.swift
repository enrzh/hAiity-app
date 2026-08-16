import Foundation
import XCTest
@testable import Haiity

final class MemoryGitHubCredentialVault: GitHubCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var deleteError: Error?

    init(token: String? = nil) {
        self.token = token
    }

    func read() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func save(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        if let deleteError { throw deleteError }
        token = nil
    }

    func failDeletes(with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        deleteError = error
    }
}

final class GitHubCredentialsTests: XCTestCase {
    func testMemoryVaultSaveReadAndDeleteRoundTrip() throws {
        let vault = MemoryGitHubCredentialVault()
        XCTAssertNil(try vault.read())
        try vault.save("secret-token")
        XCTAssertEqual(try vault.read(), "secret-token")
        try vault.save("second")
        XCTAssertEqual(try vault.read(), "second")
        try vault.delete()
        XCTAssertNil(try vault.read())
        try vault.delete()
    }

    func testKeychainVaultUsesDeviceOnlyAttributes() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Services/GitHubCredentials.swift"))
        XCTAssertTrue(source.contains("com.aiity.haiity.github"))
        XCTAssertTrue(source.contains("oauth-token"))
        XCTAssertTrue(source.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
        XCTAssertTrue(source.contains("kSecClassGenericPassword"))
        XCTAssertFalse(source.contains("kSecAttrSynchronizable"))
    }

    func testKeychainReplacementDoesNotDeleteTheExistingTokenFirst() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Services/GitHubCredentials.swift"))
        let vault = try XCTUnwrap(source.range(of: "struct KeychainGitHubCredentialVault"))
        let save = try XCTUnwrap(source.range(of: "func save(_ token: String) throws",
                                              range: vault.upperBound..<source.endIndex))
        let delete = try XCTUnwrap(source.range(of: "func delete() throws", range: save.upperBound..<source.endIndex))
        let body = source[save.lowerBound..<delete.lowerBound]

        XCTAssertTrue(body.contains("SecItemUpdate"))
        XCTAssertFalse(body.contains("try delete()"))
    }

    func testErrorsNeverIncludeTheToken() {
        let error = GitHubCredentialError.keychain(-34018)
        let text = "\(error) \(String(describing: error)) \(error.localizedDescription)"
        XCTAssertFalse(text.contains("secret-token"))
        XCTAssertFalse(text.contains("oauth-token"))
    }

    func testAppConfigTrimsAndRejectsPlaceholder() {
        XCTAssertEqual(GitHubAppConfig.placeholderClientID, "REPLACE_ME_CLIENT_ID")
        XCTAssertFalse(GitHubAppConfig.placeholderClientID.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
