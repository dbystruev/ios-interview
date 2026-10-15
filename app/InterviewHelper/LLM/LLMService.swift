import Foundation

public enum LLMError: Error, Sendable {
    case unavailable(String)
    case transport(String)
    case badResponse(String)
    case decodingFailed(String)
}

public protocol LLMService: CleaningLLM {
    var id: String { get }
    var displayName: String { get }
    var isAvailable: Bool { get }
}

public struct GeneratedAnswer: Sendable {
    public var text: String
    public var citations: [SourceCitation]

    public init(text: String, citations: [SourceCitation]) {
        self.text = text
        self.citations = citations
    }
}

public enum LLMJSON {
    public static func stripFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let nl = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: nl)...])
        } else {
            s = s.replacingOccurrences(of: "```", with: "")
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = s.range(of: "```", options: .backwards) {
            s = String(s[..<range.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeArray<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let cleaned = stripFences(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Non-UTF8 JSON")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMError.decodingFailed("Decode failed: \(error.localizedDescription)")
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let cleaned = stripFences(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Non-UTF8 JSON")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMError.decodingFailed("Decode failed: \(error.localizedDescription)")
        }
    }
}

private struct LLMAnswerPayload: Decodable, Sendable {
    var answer: String?
    var text: String?
    var content: String?
    var citations: [LLMCitation]?

    var resolvedText: String {
        answer ?? text ?? content ?? ""
    }
}

extension LLMService {
    public func extractQAs(from markdown: String) async throws -> [ExtractedQA] {
        let system = "You are an iOS interview Q&A extractor. Output STRICT JSON only: an array of objects with keys \"question\" (string), \"answer\" (string or null), \"topicHint\" (string or null), \"keywords\" (array of strings). No markdown, no fences, no commentary."
        let user = "Extract all interview questions and answers from this Markdown:\n\n\(markdown)"
        let raw = try await complete(system: system, user: user)
        return try LLMJSON.decodeArray([ExtractedQA].self, from: raw)
    }

    public func clean(raw: RawQA) async throws -> CleanedQA {
        let system = "You are an iOS interview Q&A normalizer. Output STRICT JSON only with keys: question (string), answer (Markdown string), topic (short string), keywords (array of up to 8 lowercase strings), citations (array of {sourceId,title,url} or null). No fences."
        var user = "Question: \(raw.question)\nAnswer: \(raw.answer)"
        if !raw.topicHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            user += "\nTopicHint: \(raw.topicHint)"
        }
        if raw.isFollowUp, let parent = raw.parentQuestionText, !parent.isEmpty {
            user += "\nFollowUpOf: \(parent)"
        }
        let out = try await complete(system: system, user: user)
        return try LLMJSON.decode(CleanedQA.self, from: out)
    }

    public func mergeAnswers(existing: String, incoming: String) async throws -> String {
        let system = "Merge answers: preserve all existing points, append only novel sentences from incoming, keep Markdown, no deletion. Output merged Markdown text only, no JSON, no fences."
        let user = "Existing:\n\(existing)\n\nIncoming:\n\(incoming)"
        let raw = try await complete(system: system, user: user)
        return LLMJSON.stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func answer(transcript: String, nearMiss: String?, allowedHosts: [String], topic: String?) async throws -> GeneratedAnswer {
        let allowList = allowedHosts.joined(separator: ", ")
        let system = "You are an iOS interview assistant. Answer concisely for iOS interview context. Output STRICT JSON only: {\"answer\": \"...\", \"citations\": [{\"sourceId\": \"...\", \"title\": \"...\", \"url\": \"...\"}]}. Cite only hosts from allowlist: \(allowList). No fences."
        var user = "Transcript:\n\(transcript)"
        if let near = nearMiss, !near.isEmpty {
            user += "\n\nNear-miss Q&A:\n\(near)"
        }
        if let t = topic, !t.isEmpty {
            user += "\n\nTopic: \(t)"
        }
        let raw = try await complete(system: system, user: user)
        let cleaned = LLMJSON.stripFences(raw)
        guard let data = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(LLMAnswerPayload.self, from: data) else {
            return GeneratedAnswer(text: cleaned, citations: [])
        }
        let resolved = payload.resolvedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = resolved.isEmpty ? cleaned : resolved
        var kept: [SourceCitation] = []
        for c in payload.citations ?? [] {
            guard let url = URL(string: c.url), let host = url.host, !host.isEmpty else { continue }
            let ok = allowedHosts.contains { HostUtil.hostMatches(host, allowedBase: $0) }
            if ok {
                kept.append(SourceCitation(sourceId: c.sourceId, title: c.title, url: url))
            }
        }
        return GeneratedAnswer(text: finalText, citations: kept)
    }
}
