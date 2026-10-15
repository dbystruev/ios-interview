import Foundation

public struct MatchableEntry: Sendable, Hashable, Identifiable {
    public var id: String
    public var question: String
    public var answer: String
    public var keywords: [String]
    public var topicName: String

    public init(
        id: String,
        question: String,
        answer: String = "",
        keywords: [String] = [],
        topicName: String = "General"
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.keywords = keywords
        self.topicName = topicName
    }
}

public struct ScoredEntry: Sendable, Hashable {
    public var entry: MatchableEntry
    public var score: Double

    public init(entry: MatchableEntry, score: Double) {
        self.entry = entry
        self.score = score
    }
}

public struct TopicMatcher: Sendable {
    public var threshold: Double
    public var limit: Int

    public init(threshold: Double = 0.35, limit: Int = 3) {
        self.threshold = threshold
        self.limit = limit
    }

    public func rank(query: String, entries: [MatchableEntry]) -> [ScoredEntry] {
        guard !entries.isEmpty else { return [] }
        let baseTokens = TextAnalysis.tokens(query)
        guard !baseTokens.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ".?!\n")
        let sentences = query.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var weighted = baseTokens
        if let last = sentences.last {
            weighted += TextAnalysis.tokens(last)
        }
        var queryTF: [String: Int] = [:]
        for token in weighted {
            queryTF[token, default: 0] += 1
        }

        let groupA = entries.map { $0.question + " " + $0.keywords.joined(separator: " ") }
        let groupB = entries.map(\.answer)
        let dfA = docFreqs(groupA)
        let dfB = docFreqs(groupB)
        let lensA = groupA.map { TextAnalysis.tokens($0).count }
        let lensB = groupB.map { TextAnalysis.tokens($0).count }
        let avgA = average(lensA)
        let avgB = average(lensB)

        var scored: [ScoredEntry] = []
        scored.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            let rawA = TextAnalysis.termFrequencies(groupA[index])
            let rawB = TextAnalysis.termFrequencies(groupB[index])
            let tfA = rawA.filter { queryTF[$0.key] != nil }
            let tfB = rawB.filter { queryTF[$0.key] != nil }
            let sA = TextAnalysis.bm25(
                termFreq: tfA, docLength: lensA[index],
                avgDocLength: avgA, docCount: entries.count, docFreq: dfA
            )
            let sB = TextAnalysis.bm25(
                termFreq: tfB, docLength: lensB[index],
                avgDocLength: avgB, docCount: entries.count, docFreq: dfB
            )
            let topicLower = entry.topicName.lowercased()
            let boost: Double = (!topicLower.isEmpty && weighted.contains {
                $0.count >= 4 && (topicLower.contains($0) || $0.contains(topicLower))
            }) ? 1 : 0
            let score = 0.6 * (sA / (sA + 1)) + 0.3 * (sB / (sB + 1)) + 0.1 * boost
            if score >= threshold {
                scored.append(ScoredEntry(entry: entry, score: score))
            }
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit))
    }

    public static func shouldSwap(currentScore: Double, newScore: Double, currentStale: Bool) -> Bool {
        newScore > currentScore + 0.1 || currentStale
    }

    private func docFreqs(_ texts: [String]) -> [String: Int] {
        var df: [String: Int] = [:]
        for text in texts {
            for term in Set(TextAnalysis.tokens(text)) {
                df[term, default: 0] += 1
            }
        }
        return df
    }

    private func average(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
