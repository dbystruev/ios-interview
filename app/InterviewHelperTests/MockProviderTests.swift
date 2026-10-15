import XCTest
@testable import InterviewHelper

final class MockProviderTests: XCTestCase {
    func testCannedReturnsText() async throws {
        let mock = MockProvider.canned("hello world")
        let out = try await mock.complete(system: "sys", user: "hi")
        XCTAssertEqual(out, "hello world")
    }

    func testAnswerParsesCitations() async throws {
        let json = """
        {"answer":"Use structured concurrency.","citations":[{"sourceId":"apple-docs","title":"Apple Docs","url":"https://developer.apple.com/documentation/swift"},{"sourceId":"bad","title":"Bad","url":"not a url"}]}
        """
        let mock = MockProvider.cannedExtraction(json)
        let ans = try await mock.answer(
            transcript: "What is async await?",
            nearMiss: nil,
            allowedHosts: ["developer.apple.com"],
            topic: nil
        )
        XCTAssertEqual(ans.text, "Use structured concurrency.")
        XCTAssertEqual(ans.citations.count, 1)
        XCTAssertEqual(ans.citations.first?.sourceId, "apple-docs")
    }
}
