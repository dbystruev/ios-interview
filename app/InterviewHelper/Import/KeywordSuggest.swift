import Foundation

public enum KeywordSuggest: Sendable {
    private static let stopwords: Set<String> = [
        "a", "the", "of", "to", "in", "is", "are", "how", "what", "when", "why",
        "which", "with", "for", "and", "or", "an", "on", "do", "does", "vs",
        "by", "from", "that", "this", "it", "as", "be", "can", "you", "your"
    ]

    public static func suggest(from text: String, limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for token in tokens {
            let word = String(token)
            guard word.count >= 4,
                  !stopwords.contains(word),
                  !word.allSatisfy(\.isNumber) else {
                continue
            }
            if seen.insert(word).inserted {
                result.append(word)
            }
            if result.count >= limit {
                break
            }
        }
        return result
    }
}
