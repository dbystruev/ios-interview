import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class LibraryViewModel {
    var searchText = ""
    var topicFilter = "All"
    var showNeedsReviewOnly = false

    func topics(context: ModelContext) -> [Topic] {
        let descriptor = FetchDescriptor<Topic>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func entries(context: ModelContext) -> [QAEntry] {
        let descriptor = FetchDescriptor<QAEntry>(sortBy: [SortDescriptor(\.question)])
        let all = (try? context.fetch(descriptor)) ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.filter { entry in
            if showNeedsReviewOnly, entry.needsReview == false { return false }
            if topicFilter != "All", entry.topic?.name != topicFilter { return false }
            if query.isEmpty == false {
                let hit = entry.question.lowercased().contains(query)
                    || entry.answer.lowercased().contains(query)
                    || entry.keywords.contains(where: { $0.lowercased().contains(query) })
                if hit == false { return false }
            }
            return true
        }
    }

    func importMarkdown(url: URL, context: ModelContext, llm: (any LLMService)?) async -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Could not read file."
        }
        let fileName = url.lastPathComponent
        let parsed = MarkdownImporter().parse(markdown: text, sourceFile: fileName)
        var raws = parsed.entries
        if parsed.isUnknownFormat, let llm {
            do {
                let extractor = LLMExtractor(llm: llm)
                let extracted = try await extractor.extract(markdown: text, sourceFile: fileName)
                if extracted.isEmpty == false { raws = extracted }
            } catch {
                // Keep deterministic entries on extractor failure.
            }
        }
        if raws.isEmpty { return "No questions found." }
        let normalized: [NormalizedQA] = raws.map { raw in
            let keywords = KeywordSuggest.suggest(from: raw.question + " " + raw.answer, limit: 8)
            return NormalizedQA.offline(from: raw, keywords: keywords)
        }
        let service = MergeService(modelContext: context, nearDuplicateThreshold: 0.8, allowedHosts: [], llm: nil)
        let report = await service.importEntries(normalized)
        return "Inserted \(report.inserted) • Enriched \(report.enriched) • Flagged \(report.flagged)"
    }

    func cleanEntry(_ entry: QAEntry, llm: (any LLMService)?, context: ModelContext) async {
        guard let llm else { return }
        let raw = RawQA(
            question: entry.question,
            answer: entry.answer,
            topicHint: entry.topic?.name ?? "General",
            sourceFile: entry.sourceFiles.first ?? "",
            sourceIndex: entry.sourceIndexes.first ?? 0,
            isFollowUp: entry.isFollowUp,
            parentQuestionText: ""
        )
        let normalizer = LLMNormalizer(llm: llm)
        let output = await normalizer.normalize([raw])
        guard let first = output.first else { return }
        entry.question = first.question
        entry.answer = first.answer
        entry.hasAnswer = first.hasAnswer
        entry.keywords = first.keywords
        entry.needsReview = false
        entry.updatedAt = Date()
        if entry.topic?.name != first.topic {
            let existing = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
            if let match = existing.first(where: { $0.name == first.topic }) {
                entry.topic = match
            } else {
                let created = Topic(name: first.topic)
                context.insert(created)
                entry.topic = created
            }
        }
        try? context.save()
    }

    func generateAnswer(_ entry: QAEntry, llm: (any LLMService)?, context: ModelContext, registry: SourceRegistry) async {
        guard let llm else { return }
        guard let answer = try? await llm.answer(
            transcript: entry.question,
            nearMiss: nil,
            allowedHosts: Array(registry.allowedHosts),
            topic: entry.topic?.name
        ) else { return }
        entry.answer = answer.text
        entry.hasAnswer = true
        entry.isAIGenerated = true
        let filtered = registry.filter(answer.citations)
        entry.citations = filtered.kept
        if filtered.dropped > 0 { entry.needsReview = true }
        entry.updatedAt = Date()
        try? context.save()
    }

    func deleteEntry(_ entry: QAEntry, context: ModelContext) {
        context.delete(entry)
        try? context.save()
    }

    @discardableResult
    func clearAIGenerated(context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<QAEntry>())) ?? []
        let ai = all.filter { $0.isAIGenerated }
        for entry in ai { context.delete(entry) }
        try? context.save()
        return ai.count
    }
}
