import Foundation

public enum QuestionKey: Sendable {
    public static func normalize(_ question: String) -> String {
        var text = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = try? NSRegularExpression(pattern: #"^(question\s*\d+|part\s*\d+|\d+)\s*[\s.:)\-–—]+"#) {
            var stripping = true
            while stripping {
                stripping = false
                let range = NSRange(text.startIndex..., in: text)
                if let match = prefix.firstMatch(in: text, range: range),
                   match.range.location == 0,
                   match.range.length > 0,
                   let swiftRange = Range(match.range, in: text) {
                    text = String(text[swiftRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    stripping = true
                }
            }
        }
        let kept = text.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
                || CharacterSet.decimalDigits.contains($0)
                || CharacterSet.whitespacesAndNewlines.contains($0)
        }
        let filtered = String(String.UnicodeScalarView(kept))
        return filtered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
