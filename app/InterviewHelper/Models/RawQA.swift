import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RawQA: Sendable, Hashable {
    public var question: String
    public var answer: String
    public var topicHint: String
    public var sourceFile: String
    public var sourceIndex: Int
    public var isFollowUp: Bool
    public var parentQuestionText: String?

    public init(
        question: String,
        answer: String = "",
        topicHint: String = "General",
        sourceFile: String,
        sourceIndex: Int,
        isFollowUp: Bool = false,
        parentQuestionText: String? = nil
    ) {
        self.question = question
        self.answer = answer
        self.topicHint = topicHint
        self.sourceFile = sourceFile
        self.sourceIndex = sourceIndex
        self.isFollowUp = isFollowUp
        self.parentQuestionText = parentQuestionText
    }

    public var hasAnswer: Bool {
        !answer.trimmed.isEmpty
    }
}

public struct NormalizedQA: Sendable, Hashable {
    public var question: String
    public var answer: String
    public var topic: String
    public var keywords: [String]
    public var citations: [SourceCitation]
    public var sourceFile: String
    public var sourceIndex: Int
    public var isFollowUp: Bool
    public var parentQuestionText: String?
    public var isAIGenerated: Bool
    public var needsReview: Bool

    public init(
        question: String,
        answer: String = "",
        topic: String = "General",
        keywords: [String] = [],
        citations: [SourceCitation] = [],
        sourceFile: String,
        sourceIndex: Int,
        isFollowUp: Bool = false,
        parentQuestionText: String? = nil,
        isAIGenerated: Bool = false,
        needsReview: Bool = false
    ) {
        self.question = question
        self.answer = answer
        self.topic = topic
        self.keywords = keywords
        self.citations = citations
        self.sourceFile = sourceFile
        self.sourceIndex = sourceIndex
        self.isFollowUp = isFollowUp
        self.parentQuestionText = parentQuestionText
        self.isAIGenerated = isAIGenerated
        self.needsReview = needsReview
    }

    public var hasAnswer: Bool {
        !answer.trimmed.isEmpty
    }

    public static func offline(from raw: RawQA, keywords: [String] = []) -> NormalizedQA {
        let topic = raw.topicHint.trimmed
        return NormalizedQA(
            question: raw.question,
            answer: raw.answer,
            topic: topic.isEmpty ? "General" : topic,
            keywords: keywords,
            citations: [],
            sourceFile: raw.sourceFile,
            sourceIndex: raw.sourceIndex,
            isFollowUp: raw.isFollowUp,
            parentQuestionText: raw.parentQuestionText,
            isAIGenerated: false,
            needsReview: false
        )
    }
}
