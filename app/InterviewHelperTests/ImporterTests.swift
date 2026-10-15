import XCTest
@testable import InterviewHelper

final class ImporterTests: XCTestCase {
    private let importer = MarkdownImporter()

    func testStyleA() throws {
        let markdown = """
        ## Swift Basics
        1. **What is ARC?**
           - Automatic Reference Counting manages memory.
        2. **What is a struct?**
        3. **Explain optionals.**
           - An optional holds a value or nil.
        """
        let result = importer.parse(markdown: markdown, sourceFile: "a.md")
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.entries[0].question, "What is ARC?")
        XCTAssertEqual(result.entries[0].topicHint, "Swift Basics")
        XCTAssertTrue(result.entries[0].hasAnswer)
        XCTAssertEqual(result.entries[1].question, "What is a struct?")
        XCTAssertFalse(result.entries[1].hasAnswer)
        XCTAssertEqual(result.entries[1].answer, "")
        XCTAssertTrue(result.entries[2].hasAnswer)
        XCTAssertFalse(result.isUnknownFormat)
    }

    func testStyleB() throws {
        let markdown = """
        ## Memory Management
        ## Question 1: What is ARC?
        **Answer:**
        Automatic Reference Counting manages memory.
        ## Question 2: What is a retain cycle?
        Answer:
        Two objects holding strong references to each other.
        """
        let result = importer.parse(markdown: markdown, sourceFile: "b.md")
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].question, "What is ARC?")
        XCTAssertEqual(result.entries[0].topicHint, "Memory Management")
        XCTAssertEqual(result.entries[0].answer, "Automatic Reference Counting manages memory.")
        XCTAssertEqual(result.entries[1].question, "What is a retain cycle?")
        XCTAssertEqual(result.entries[1].answer, "Two objects holding strong references to each other.")
    }

    func testStyleC() throws {
        let markdown = """
        ## Welcome
        ## Part 1 - Swift
        ### Question 1. What is ARC?
        > Automatic Reference Counting manages memory.
        ### Question 2. What is a struct?
        > A value type.
        *Follow-up question: When do you prefer a struct over a class?*
        """
        let result = importer.parse(markdown: markdown, sourceFile: "c.md")
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertFalse(result.entries.contains(where: { $0.topicHint == "Welcome" }))
        XCTAssertEqual(result.entries[0].topicHint, "Swift")
        XCTAssertEqual(result.entries[0].question, "What is ARC?")
        XCTAssertTrue(result.entries[0].answer.contains("Automatic Reference Counting"))
        XCTAssertFalse(result.entries[0].isFollowUp)
        XCTAssertTrue(result.entries[2].isFollowUp)
        XCTAssertEqual(result.entries[2].question, "When do you prefer a struct over a class?")
        XCTAssertEqual(result.entries[2].parentQuestionText, "What is a struct?")
        XCTAssertFalse(result.isUnknownFormat)
    }

    func testUnknownFormat() throws {
        let markdown = "Just some plain prose about interviews.\nNothing structured here.\nMore words without questions."
        let result = importer.parse(markdown: markdown, sourceFile: "plain.md")
        XCTAssertLessThan(result.entries.count, 3)
        XCTAssertTrue(result.isUnknownFormat)
    }
}
