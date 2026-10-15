import XCTest
@testable import InterviewHelper

struct MockCleaningLLM: CleaningLLM {
    let response: String

    func complete(system: String, user: String) async throws -> String {
        response
    }
}

actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

struct CountingLLM: CleaningLLM {
    let counter: CallCounter

    func complete(system: String, user: String) async throws -> String {
        await counter.increment()
        return "```json\n[{\"question\":\"What is ARC?\",\"answer\":\"An answer.\",\"topicHint\":\"Swift\",\"keywords\":[]}]\n```"
    }
}

final class LLMExtractorTests: XCTestCase {
    func testExtractBasic() async throws {
        let canned = """
        ```json
        [{"question":"What is ARC?","answer":"Automatic Reference Counting.","topicHint":"Swift","keywords":["automatic"]},
         {"question":"What is a struct?","answer":null,"topicHint":"Swift","keywords":[]}]
        ```
        """
        let extractor = LLMExtractor(llm: MockCleaningLLM(response: canned))
        let result = try await extractor.extract(markdown: "some notes", sourceFile: "notes.md")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].question, "What is ARC?")
        XCTAssertTrue(result[0].hasAnswer)
        XCTAssertEqual(result[0].topicHint, "Swift")
        XCTAssertFalse(result[1].hasAnswer)
        XCTAssertEqual(result[1].answer, "")
    }

    func testMultiChunk() async throws {
        let paragraph = "Swift memory management uses automatic reference counting to track lifetimes.\n"
        let long = String(repeating: paragraph, count: 300)
        XCTAssertGreaterThan(long.count, 8000)
        let counter = CallCounter()
        let extractor = LLMExtractor(llm: CountingLLM(counter: counter))
        let result = try await extractor.extract(markdown: long, sourceFile: "long.md")
        let calls = await counter.count
        XCTAssertGreaterThan(calls, 1)
        XCTAssertEqual(result.count, calls)
        XCTAssertEqual(result.map(\.sourceIndex), Array(0..<result.count))
    }
}
