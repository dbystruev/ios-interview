import Foundation
import SwiftData

@MainActor public final class MergeService {
    public struct Report: Sendable {
        public var inserted = 0
        public var enriched = 0
        public var flagged = 0

        public init(inserted: Int = 0, enriched: Int = 0, flagged: Int = 0) {
            self.inserted = inserted
            self.enriched = enriched
            self.flagged = flagged
        }
    }

    private let modelContext: ModelContext
    private let nearDuplicateThreshold: Double
    private let allowedHosts: Set<String>
    private let llm: (any CleaningLLM)?

    public init(
        modelContext: ModelContext,
        nearDuplicateThreshold: Double = 0.8,
        allowedHosts: Set<String> = [],
        llm: (any CleaningLLM)? = nil
    ) {
        self.modelContext = modelContext
        self.nearDuplicateThreshold = nearDuplicateThreshold
        self.allowedHosts = allowedHosts
        self.llm = llm
    }

    public func importEntries(_ entries: [NormalizedQA]) async -> Report {
        var report = Report()
        var existing = (try? modelContext.fetch(FetchDescriptor<QAEntry>())) ?? []
        var topicCache: [String: Topic] = [:]
        for topic in (try? modelContext.fetch(FetchDescriptor<Topic>())) ?? [] {
            topicCache[topic.name] = topic
        }
        let filter = CitationFilter(allowedHosts: allowedHosts)
        for incoming in entries {
            let key = QuestionKey.normalize(incoming.question)
            guard !key.isEmpty else { continue }
            if let match = existing.first(where: { $0.normalizedKey == key }) {
                await enrich(match, with: incoming, filter: filter, nearDuplicate: false)
                report.enriched += 1
                continue
            }
            let ordered: [QAEntry]
            if incoming.isFollowUp {
                ordered = existing.filter(\.isFollowUp) + existing.filter { !$0.isFollowUp }
            } else {
                ordered = existing
            }
            let incomingTokens = Self.tokens(incoming.question)
            var best: QAEntry?
            var bestScore = 0.0
            for candidate in ordered {
                let score = Self.jaccard(incomingTokens, Self.tokens(candidate.question))
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
            if let best, bestScore >= nearDuplicateThreshold {
                await enrich(best, with: incoming, filter: filter, nearDuplicate: true)
                report.enriched += 1
                report.flagged += 1
                continue
            }
            let rawName = incoming.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            let topic = topic(named: rawName.isEmpty ? "General" : rawName, cache: &topicCache)
            let filtered = filter.filter(incoming.citations)
            let parentKey = QuestionKey.normalize(incoming.parentQuestionText ?? "")
            let entry = QAEntry(
                question: incoming.question,
                answer: incoming.answer,
                hasAnswer: incoming.hasAnswer,
                normalizedKey: key,
                topic: topic,
                keywords: Array(incoming.keywords.prefix(12)),
                citations: filtered.kept,
                sourceFiles: [incoming.sourceFile],
                sourceIndexes: [incoming.sourceIndex],
                isFollowUp: incoming.isFollowUp,
                parentQuestionKey: parentKey.isEmpty ? nil : parentKey,
                needsReview: incoming.needsReview || filtered.dropped > 0,
                isAIGenerated: incoming.isAIGenerated
            )
            modelContext.insert(entry)
            existing.append(entry)
            report.inserted += 1
        }
        try? modelContext.save()
        return report
    }

    private func enrich(_ entry: QAEntry, with incoming: NormalizedQA, filter: CitationFilter, nearDuplicate: Bool) async {
        if let llm {
            do {
                let merged = try await llm.complete(
                    system: "Merge two answers about the same interview question. Preserve all existing points, append only novel sentences, keep Markdown.",
                    user: "Existing answer:\n\(entry.answer)\n\nIncoming answer:\n\(incoming.answer)"
                )
                entry.answer = merged.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                entry.answer = appendMissingParagraphs(existing: entry.answer, incoming: incoming.answer)
            }
        } else {
            entry.answer = appendMissingParagraphs(existing: entry.answer, incoming: incoming.answer)
        }
        entry.hasAnswer = entry.hasAnswer || incoming.hasAnswer
            || !entry.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let incomingQuestion = incoming.question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !incomingQuestion.isEmpty, incomingQuestion.count > entry.question.count {
            entry.question = incoming.question
        }
        var keywords: [String] = []
        var seenKeywords = Set<String>()
        for keyword in entry.keywords + incoming.keywords {
            if seenKeywords.insert(keyword).inserted {
                keywords.append(keyword)
            }
            if keywords.count >= 12 {
                break
            }
        }
        entry.keywords = keywords
        var union: [SourceCitation] = []
        var seenCitations = Set<SourceCitation>()
        for citation in entry.citations + incoming.citations {
            if seenCitations.insert(citation).inserted {
                union.append(citation)
            }
        }
        let filtered = filter.filter(union)
        entry.citations = filtered.kept
        if filtered.dropped > 0 {
            entry.needsReview = true
        }
        if !entry.sourceFiles.contains(incoming.sourceFile) {
            entry.sourceFiles.append(incoming.sourceFile)
        }
        if !entry.sourceIndexes.contains(incoming.sourceIndex) {
            entry.sourceIndexes.append(incoming.sourceIndex)
        }
        entry.updatedAt = Date()
        if nearDuplicate {
            entry.needsReview = true
        }
    }

    private func topic(named name: String, cache: inout [String: Topic]) -> Topic {
        if let cached = cache[name] {
            return cached
        }
        let created = Topic(name: name)
        modelContext.insert(created)
        cache[name] = created
        return created
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }

    func appendMissingParagraphs(existing: String, incoming: String) -> String {
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = Self.splitParagraphs(incoming)
        guard !paragraphs.isEmpty else { return existing }
        let normalizedBase = QuestionKey.normalize(base)
        let novel = paragraphs.filter { paragraph in
            let normalized = QuestionKey.normalize(paragraph)
            return !normalized.isEmpty && !normalizedBase.contains(normalized)
        }
        guard !novel.isEmpty else { return existing }
        if base.isEmpty {
            return novel.joined(separator: "\n\n")
        }
        return base + "\n\n" + novel.joined(separator: "\n\n")
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        var paragraphs: [[String]] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current)
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current)
        }
        return paragraphs
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
