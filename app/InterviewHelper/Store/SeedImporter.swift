import Foundation
import SwiftData

@MainActor
enum SeedImporter {
    static func seedIfEmpty(context: ModelContext) async {
        do {
            let count = try context.fetchCount(FetchDescriptor<QAEntry>())
            if count != 0 { return }
        } catch {
            return
        }
        guard let url = Bundle.main.url(forResource: "sample-ios-qa", withExtension: "md") else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = MarkdownImporter().parse(markdown: text, sourceFile: url.lastPathComponent)
        if parsed.entries.isEmpty { return }
        let normalized: [NormalizedQA] = parsed.entries.map { raw in
            let keywords = KeywordSuggest.suggest(from: raw.question + " " + raw.answer, limit: 8)
            return NormalizedQA.offline(from: raw, keywords: keywords)
        }
        let service = MergeService(modelContext: context, nearDuplicateThreshold: 0.8, allowedHosts: [], llm: nil)
        _ = await service.importEntries(normalized)
    }
}
