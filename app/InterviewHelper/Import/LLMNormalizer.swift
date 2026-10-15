import Foundation

public struct CleanedQA: Codable, Sendable {
    public var question: String
    public var answer: String
    public var topic: String
    public var keywords: [String]
    public var citations: [LLMCitation]?
}

public struct LLMCitation: Codable, Sendable {
    public var sourceId: String
    public var title: String
    public var url: String
}

public struct LLMNormalizer: Sendable {
    public var llm: (any CleaningLLM)?

    public init(llm: (any CleaningLLM)? = nil) {
        self.llm = llm
    }

    public func normalize(_ raw: [RawQA]) async -> [NormalizedQA] {
        guard llm != nil else {
            return raw.map { offline($0) }
        }
        var result: [NormalizedQA] = []
        for item in raw {
            do {
                result.append(try await cleanWithLLM(item))
            } catch {
                result.append(offline(item))
            }
        }
        return result
    }

    private func offline(_ raw: RawQA) -> NormalizedQA {
        NormalizedQA.offline(from: raw, keywords: KeywordSuggest.suggest(from: "\(raw.question)\n\(raw.answer)"))
    }

    private func cleanWithLLM(_ raw: RawQA) async throws -> NormalizedQA {
        guard let llm else {
            throw NormalizerError.unavailable
        }
        let system = "You clean iOS interview Q&A records. Respond with strict JSON only: a single object with keys question (string), answer (string, Markdown), topic (string), keywords (array of strings), citations (array of objects with sourceId, title, url, or null). No prose, no fences."
        let user = "Question: \(raw.question)\nAnswer: \(raw.answer)\nTopic hint: \(raw.topicHint)\nReturn strict JSON."
        let text = try await llm.complete(system: system, user: user)
        let json = Self.stripFences(text)
        let cleaned = try JSONDecoder().decode(CleanedQA.self, from: Data(json.utf8))
        let keywords = Array(cleaned.keywords.prefix(8))
        let citations = (cleaned.citations ?? []).compactMap { citation -> SourceCitation? in
            guard let url = URL(string: citation.url),
                  let scheme = url.scheme,
                  (scheme == "http" || scheme == "https"),
                  url.host != nil else {
                return nil
            }
            return SourceCitation(sourceId: citation.sourceId, title: citation.title, url: url)
        }
        let topic = cleaned.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return NormalizedQA(
            question: cleaned.question,
            answer: cleaned.answer,
            topic: topic.isEmpty ? "General" : topic,
            keywords: keywords,
            citations: citations,
            sourceFile: raw.sourceFile,
            sourceIndex: raw.sourceIndex,
            isFollowUp: raw.isFollowUp,
            parentQuestionText: raw.parentQuestionText
        )
    }

    private static func stripFences(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum NormalizerError: Error {
    case unavailable
}
