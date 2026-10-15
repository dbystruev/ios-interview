import Foundation
import SwiftData

@Model public final class Topic {
    public var name: String
    @Relationship(deleteRule: .cascade, inverse: \QAEntry.topic) public var entries: [QAEntry] = []
    public var createdAt: Date = Date()

    public init(name: String) {
        self.name = name
    }
}

@Model public final class QAEntry {
    public var question: String
    public var answer: String
    public var hasAnswer: Bool
    public var normalizedKey: String
    public var topic: Topic?
    public var keywords: [String] = []
    public var citationsData: Data = Data()
    public var sourceFiles: [String] = []
    public var sourceIndexes: [Int] = []
    public var isFollowUp: Bool = false
    public var parentQuestionKey: String?
    public var needsReview: Bool = false
    public var isAIGenerated: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        question: String,
        answer: String,
        hasAnswer: Bool,
        normalizedKey: String,
        topic: Topic? = nil,
        keywords: [String] = [],
        citations: [SourceCitation] = [],
        sourceFiles: [String] = [],
        sourceIndexes: [Int] = [],
        isFollowUp: Bool = false,
        parentQuestionKey: String? = nil,
        needsReview: Bool = false,
        isAIGenerated: Bool = false
    ) {
        self.question = question
        self.answer = answer
        self.hasAnswer = hasAnswer
        self.normalizedKey = normalizedKey
        self.topic = topic
        self.keywords = keywords
        self.citationsData = (try? JSONEncoder().encode(citations)) ?? Data()
        self.sourceFiles = sourceFiles
        self.sourceIndexes = sourceIndexes
        self.isFollowUp = isFollowUp
        self.parentQuestionKey = parentQuestionKey
        self.needsReview = needsReview
        self.isAIGenerated = isAIGenerated
    }

    public var citations: [SourceCitation] {
        get {
            (try? JSONDecoder().decode([SourceCitation].self, from: citationsData)) ?? []
        }
        set {
            citationsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
