import Foundation

public enum TextAnalysis: Sendable {
    public static let stopwords: Set<String> = [
        "a", "the", "of", "to", "in", "is", "are", "how", "what", "when",
        "why", "which", "with", "for", "and", "or", "an", "on", "do", "does",
        "vs", "by", "from", "that", "this", "it", "as", "be", "can", "you",
        "your", "we", "our", "they", "their", "there", "here", "was", "were",
        "will", "would", "should", "could", "has", "have", "had", "not", "but",
        "at", "into"
    ]

    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard token.count >= 2, !stopwords.contains(token) else { return false }
                return !token.allSatisfy(\.isNumber)
            }
    }

    public static func termFrequencies(_ text: String) -> [String: Int] {
        var freq: [String: Int] = [:]
        for token in tokens(text) {
            freq[token, default: 0] += 1
        }
        return freq
    }

    public static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty, b.isEmpty { return 1.0 }
        let union = a.union(b)
        guard !union.isEmpty else { return 1.0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    public static func bm25(
        termFreq: [String: Int],
        docLength: Int,
        avgDocLength: Double,
        docCount: Int,
        docFreq: [String: Int],
        k1: Double = 1.2,
        b: Double = 0.75
    ) -> Double {
        guard docCount > 0, avgDocLength > 0, docLength > 0 else { return 0 }
        var score = 0.0
        for (term, tf) in termFreq {
            let df = Double(docFreq[term] ?? 0)
            let idf = log(1 + (Double(docCount) - df + 0.5) / (df + 0.5))
            let denom = Double(tf) + k1 * (1 - b + b * Double(docLength) / avgDocLength)
            guard denom > 0 else { continue }
            score += idf * Double(tf) * (k1 + 1) / denom
        }
        return score
    }
}
