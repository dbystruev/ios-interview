import XCTest
@testable import InterviewHelper

final class LLMJSONTests: XCTestCase {
    func testStripFences_json() {
        let input = "```json\n{\"a\":1}\n```"
        XCTAssertEqual(LLMJSON.stripFences(input), "{\"a\":1}")
    }

    func testStripFences_plain() {
        let input = "```\nhello\n```"
        XCTAssertEqual(LLMJSON.stripFences(input), "hello")
    }

    func testStripFences_none() {
        XCTAssertEqual(LLMJSON.stripFences("  hello  "), "hello")
        XCTAssertEqual(LLMJSON.stripFences("{\"a\":1}"), "{\"a\":1}")
    }

    func testDecodeArrayValid() throws {
        let json = """
        [{"question":"What is ARC?","answer":"Automatic Reference Counting","topicHint":"Memory","keywords":["arc"]}]
        """
        let arr = try LLMJSON.decodeArray([ExtractedQA].self, from: json)
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr.first?.question, "What is ARC?")
    }

    func testDecodeArrayWithFences() throws {
        let json = "```json\n[{\"question\":\"Q?\",\"answer\":null,\"topicHint\":null,\"keywords\":[]}]\n```"
        let arr = try LLMJSON.decodeArray([ExtractedQA].self, from: json)
        XCTAssertEqual(arr.count, 1)
    }

    func testDecodeFailureThrowsLLMError() {
        XCTAssertThrowsError(try LLMJSON.decode(CleanedQA.self, from: "not json")) { error in
            XCTAssertTrue(error is LLMError)
        }
    }
}
