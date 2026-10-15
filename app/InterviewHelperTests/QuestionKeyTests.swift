import XCTest
@testable import InterviewHelper

final class QuestionKeyTests: XCTestCase {
    func testPrefixesStripped() throws {
        let expected = QuestionKey.normalize("What is ARC?")
        XCTAssertEqual(QuestionKey.normalize("Question 3. What is ARC?"), expected)
        XCTAssertEqual(QuestionKey.normalize("3. What is ARC?"), expected)
        XCTAssertEqual(QuestionKey.normalize("Part 2: What is ARC?"), expected)
    }

    func testCaseAndPunctuationInsensitive() throws {
        XCTAssertEqual(QuestionKey.normalize("What is ARC?"), QuestionKey.normalize("what is arc!"))
        XCTAssertEqual(QuestionKey.normalize("(What) is ARC..."), "what is arc")
    }
}
