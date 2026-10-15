import SwiftData
import XCTest
@testable import InterviewHelper

@MainActor
final class MergeServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: QAEntry.self, Topic.self, configurations: configuration)
        return ModelContext(container)
    }

    private func fetchEntries(_ context: ModelContext) throws -> [QAEntry] {
        try context.fetch(FetchDescriptor<QAEntry>())
    }

    func testExactMerge() async throws {
        let context = try makeContext()
        let service = MergeService(modelContext: context)
        let first = NormalizedQA(
            question: "What is ARC?",
            answer: "Automatic Reference Counting manages memory.",
            topic: "Swift",
            sourceFile: "a.md",
            sourceIndex: 0
        )
        let second = NormalizedQA(
            question: "What is ARC?",
            answer: "It frees developers from manual retain and release.",
            topic: "Swift",
            sourceFile: "b.md",
            sourceIndex: 1
        )
        let firstReport = await service.importEntries([first])
        XCTAssertEqual(firstReport.inserted, 1)
        let secondReport = await service.importEntries([second])
        XCTAssertEqual(secondReport.inserted, 0)
        XCTAssertEqual(secondReport.enriched, 1)
        let rows = try fetchEntries(context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].sourceFiles.contains("a.md"))
        XCTAssertTrue(rows[0].sourceFiles.contains("b.md"))
        XCTAssertTrue(rows[0].answer.contains("Automatic Reference Counting"))
        XCTAssertTrue(rows[0].answer.contains("retain and release"))
    }

    func testNearDuplicateFlagged() async throws {
        let context = try makeContext()
        let service = MergeService(modelContext: context)
        let first = NormalizedQA(
            question: "How does ARC work in Swift?",
            answer: "The compiler inserts retain and release calls.",
            topic: "Swift",
            sourceFile: "a.md",
            sourceIndex: 0
        )
        let paraphrase = NormalizedQA(
            question: "How does ARC work in Swift today?",
            answer: "It tracks references automatically.",
            topic: "Swift",
            sourceFile: "b.md",
            sourceIndex: 1
        )
        let firstReport = await service.importEntries([first])
        XCTAssertEqual(firstReport.inserted, 1)
        let secondReport = await service.importEntries([paraphrase])
        XCTAssertEqual(secondReport.flagged, 1)
        let rows = try fetchEntries(context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].needsReview)
    }

    func testReimportIdempotent() async throws {
        let context = try makeContext()
        let service = MergeService(modelContext: context)
        let items = [
            NormalizedQA(question: "What is ARC?", answer: "Automatic Reference Counting.", topic: "Swift", sourceFile: "a.md", sourceIndex: 0),
            NormalizedQA(question: "What is a struct?", answer: "A value type.", topic: "Swift", sourceFile: "a.md", sourceIndex: 1),
        ]
        let firstReport = await service.importEntries(items)
        XCTAssertEqual(firstReport.inserted, 2)
        let before = try fetchEntries(context)
        let secondReport = await service.importEntries(items)
        XCTAssertEqual(secondReport.inserted, 0)
        let after = try fetchEntries(context)
        XCTAssertEqual(after.count, before.count)
    }

    func testQuestionOnlyThenAnswered() async throws {
        let context = try makeContext()
        let service = MergeService(modelContext: context)
        let questionOnly = NormalizedQA(
            question: "What is a value type?",
            answer: "",
            topic: "Swift",
            sourceFile: "q.md",
            sourceIndex: 0
        )
        _ = await service.importEntries([questionOnly])
        var rows = try fetchEntries(context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].hasAnswer)
        let answered = NormalizedQA(
            question: "What is a value type?",
            answer: "A type copied on assignment.",
            topic: "Swift",
            sourceFile: "a.md",
            sourceIndex: 3
        )
        let report = await service.importEntries([answered])
        XCTAssertEqual(report.enriched, 1)
        rows = try fetchEntries(context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].hasAnswer)
        XCTAssertTrue(rows[0].answer.contains("copied on assignment"))
    }

    func testCitationAllowlist() async throws {
        let context = try makeContext()
        let service = MergeService(modelContext: context, allowedHosts: ["apple.com"])
        let goodURL = try XCTUnwrap(URL(string: "https://developer.apple.com/documentation/swift"))
        let badURL = try XCTUnwrap(URL(string: "https://evil.example/x"))
        let item = NormalizedQA(
            question: "What is Swift?",
            answer: "A language.",
            topic: "Swift",
            citations: [
                SourceCitation(sourceId: "1", title: "Apple Docs", url: goodURL),
                SourceCitation(sourceId: "2", title: "Evil", url: badURL),
            ],
            sourceFile: "c.md",
            sourceIndex: 0
        )
        let report = await service.importEntries([item])
        XCTAssertEqual(report.inserted, 1)
        let rows = try fetchEntries(context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].citations.count, 1)
        XCTAssertEqual(rows[0].citations.first?.url.host, "developer.apple.com")
        XCTAssertTrue(rows[0].needsReview)
    }
}
