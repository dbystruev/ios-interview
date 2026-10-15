import Foundation

public struct ExtractedQA: Codable, Sendable {
    public var question: String
    public var answer: String?
    public var topicHint: String?
    public var keywords: [String]?
}

public enum LLMExtractorError: Error, Sendable {
    case unavailable
    case noEntries
    case decodingFailed(String)
}

public struct LLMExtractor: Sendable {
    public var llm: any CleaningLLM

    public init(llm: any CleaningLLM) {
        self.llm = llm
    }

    public func extract(markdown: String, sourceFile: String) async throws -> [RawQA] {
        let chunks = Self.chunk(markdown: markdown, limit: 8000)
        var result: [RawQA] = []
        var index = 0
        for chunk in chunks {
            let text = try await llm.complete(system: Self.systemPrompt, user: Self.userPrompt(chunk))
            let json = Self.stripFences(text)
            guard let data = json.data(using: .utf8) else {
                throw LLMExtractorError.decodingFailed("Response is not valid UTF-8")
            }
            let decoded: [ExtractedQA]
            do {
                decoded = try JSONDecoder().decode([ExtractedQA].self, from: data)
            } catch {
                throw LLMExtractorError.decodingFailed(String(describing: error))
            }
            for item in decoded {
                let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty else { continue }
                let topic = (item.topicHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(RawQA(
                    question: question,
                    answer: item.answer ?? "",
                    topicHint: topic.isEmpty ? "General" : topic,
                    sourceFile: sourceFile,
                    sourceIndex: index
                ))
                index += 1
            }
        }
        if result.isEmpty {
            throw LLMExtractorError.noEntries
        }
        return result
    }

    private static let systemPrompt = "Extract iOS interview questions and answers. Respond with strict JSON only: an array of objects with keys question (string), answer (string or null when unanswered), topicHint (string or null), keywords (array of strings or null). No prose, no fences."

    private static func userPrompt(_ chunk: String) -> String {
        "Extract Q&A records from this Markdown chunk. Return a strict JSON array.\n\n\(chunk)"
    }

    private static func stripFences(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chunk(markdown: String, limit: Int) -> [String] {
        let lines = markdown.components(separatedBy: "\n")
        var chunks: [String] = []
        var current: [String] = []
        var currentLength = 0
        for line in lines {
            let length = line.count + 1
            if currentLength + length > limit, !current.isEmpty {
                if let heading = current.lastIndex(where: isHeadingLine), heading > 0 {
                    chunks.append(Array(current[..<heading]).joined(separator: "\n"))
                    current = Array(current[heading...])
                    currentLength = current.reduce(0) { $0 + $1.count + 1 }
                } else {
                    chunks.append(current.joined(separator: "\n"))
                    current = []
                    currentLength = 0
                }
            }
            current.append(line)
            currentLength += length
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        return chunks.isEmpty ? [markdown] : chunks
    }

    private static func isHeadingLine(_ line: String) -> Bool {
        line.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil
    }
}
