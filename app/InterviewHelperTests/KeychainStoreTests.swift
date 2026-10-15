import XCTest
@testable import InterviewHelper

final class KeychainStoreTests: XCTestCase {
    func testSaveLoadRoundtrip() throws {
        let service = "test-\(UUID().uuidString)"
        try KeychainStore.save("secret-123", service: service, account: "apiKey")
        XCTAssertEqual(KeychainStore.load(service: service, account: "apiKey"), "secret-123")
        try KeychainStore.delete(service: service, account: "apiKey")
    }

    func testDeleteRemoves() throws {
        let service = "test-\(UUID().uuidString)"
        try KeychainStore.save("to-delete", service: service, account: "apiKey")
        try KeychainStore.delete(service: service, account: "apiKey")
        XCTAssertNil(KeychainStore.load(service: service, account: "apiKey"))
    }
}
