import Foundation

public struct ImportParse: Sendable {
    public var entries: [RawQA]
    public var coverage: Double
    public var isUnknownFormat: Bool

    public init(entries: [RawQA], coverage: Double, isUnknownFormat: Bool) {
        self.entries = entries
        self.coverage = coverage
        self.isUnknownFormat = isUnknownFormat
    }
}

public struct MarkdownImporter: Sendable {
    public init() {}

    public func parse(markdown: String, sourceFile: String) -> ImportParse {
        let lines = markdown.components(separatedBy: "\n")
        if lines.contains(where: { matchesPattern($0, pattern: #"^###\s+Question\s*\d+"#) }) {
            return parseStyleC(lines: lines, sourceFile: sourceFile)
        }
        if lines.contains(where: { matchesPattern($0, pattern: #"^##\s+Question\s*\d+"#) }) {
            return parseStyleB(lines: lines, sourceFile: sourceFile)
        }
        return parseStyleA(lines: lines, sourceFile: sourceFile)
    }

    private func parseStyleC(lines: [String], sourceFile: String) -> ImportParse {
        struct Builder {
            var question: String
            var topicHint: String
            var answerLines: [String] = []
            var isFollowUp = false
            var parent: String?
        }
        let questionRe = makeRegex(#"^###\s+Question\s*\d+\s*[.:)\-–—]?\s*(.*)$"#)
        let headingRe = makeRegex(#"^##\s+(.*)$"#)
        let followUpRe = makeRegex(#"^\*Follow-up question:\s*(.+?)\*?\s*$"#)
        let partRe = makeRegex(#"^Part\s*\d+\s*[.\-–:]\s*"#)

        var topic = "General"
        var builders: [Builder] = []
        var current: Int?
        var lastMainQuestion: String?
        var attributed = 0
        var nonBlank = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                nonBlank += 1
            }
            if let groups = regexCaptures(questionRe, line) {
                let text = (groups.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    builders.append(Builder(question: text, topicHint: topic))
                    current = builders.count - 1
                    lastMainQuestion = text
                    attributed += 1
                }
                continue
            }
            if let groups = regexCaptures(headingRe, line) {
                let text = (groups.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text != "Welcome" {
                    var next = text
                    if let range = regexMatchRange(partRe, next),
                       range.location == 0,
                       let swiftRange = Range(range, in: next) {
                        next = String(next[swiftRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if !next.isEmpty {
                        topic = next
                    }
                }
                continue
            }
            if let groups = regexCaptures(followUpRe, line) {
                let text = (groups.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, let parent = lastMainQuestion {
                    builders.append(Builder(question: text, topicHint: topic, isFollowUp: true, parent: parent))
                    current = builders.count - 1
                    attributed += 1
                }
                continue
            }
            guard let index = current else { continue }
            if line.hasPrefix(">") {
                var content = String(line.dropFirst())
                if content.hasPrefix(" ") {
                    content = String(content.dropFirst())
                }
                builders[index].answerLines.append(content.trimmed.isEmpty ? "" : content)
                attributed += 1
            } else if trimmed.isEmpty {
                builders[index].answerLines.append("")
            } else if trimmed.hasPrefix("#") {
                continue
            } else {
                builders[index].answerLines.append(line)
                attributed += 1
            }
        }

        var entries: [RawQA] = []
        for (index, builder) in builders.enumerated() {
            entries.append(RawQA(
                question: builder.question,
                answer: buildAnswerParagraphs(builder.answerLines),
                topicHint: builder.topicHint,
                sourceFile: sourceFile,
                sourceIndex: index,
                isFollowUp: builder.isFollowUp,
                parentQuestionText: builder.parent
            ))
        }
        return finishParse(entries: entries, attributed: attributed, nonBlank: nonBlank)
    }

    private func parseStyleB(lines: [String], sourceFile: String) -> ImportParse {
        struct Builder {
            var question: String
            var topicHint: String
            var bodyLines: [String] = []
        }
        let headingRe = makeRegex(#"^(#{1,6})\s+(.*)$"#)
        let questionHeadRe = makeRegex(#"^Question\s*\d+"#)
        let questionStripRe = makeRegex(#"^Question\s*\d+\s*[.:)\-–—]?\s*"#)

        var topic = "General"
        var builders: [Builder] = []
        var current: Int?
        var attributed = 0
        var nonBlank = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                nonBlank += 1
            }
            if let groups = regexCaptures(headingRe, line), groups.count == 2 {
                let level = groups[0]
                let text = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if regexMatches(questionHeadRe, text) {
                    var question = ""
                    if let colon = text.firstIndex(of: ":") {
                        question = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let range = regexMatchRange(questionStripRe, text),
                              range.location == 0,
                              let swiftRange = Range(range, in: text) {
                        question = String(text[swiftRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        question = text
                    }
                    if !question.isEmpty {
                        builders.append(Builder(question: question, topicHint: topic))
                        current = builders.count - 1
                        attributed += 1
                    } else {
                        current = nil
                    }
                } else {
                    if (level == "#" || level == "##"), !text.isEmpty {
                        topic = text
                    }
                    current = nil
                }
                continue
            }
            if let index = current {
                builders[index].bodyLines.append(line)
                if !trimmed.isEmpty {
                    attributed += 1
                }
            }
        }

        var entries: [RawQA] = []
        for (index, builder) in builders.enumerated() {
            var body = builder.bodyLines
            while let first = body.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body.removeFirst()
            }
            if let first = body.first {
                let marker = first.trimmingCharacters(in: .whitespacesAndNewlines)
                if marker == "**Answer:**" || marker == "Answer:" {
                    body.removeFirst()
                }
            }
            entries.append(RawQA(
                question: builder.question,
                answer: buildAnswerParagraphs(body),
                topicHint: builder.topicHint,
                sourceFile: sourceFile,
                sourceIndex: index
            ))
        }
        return finishParse(entries: entries, attributed: attributed, nonBlank: nonBlank)
    }

    private func parseStyleA(lines: [String], sourceFile: String) -> ImportParse {
        struct Builder {
            var question: String
            var topicHint: String
            var answerLines: [String] = []
        }
        let headingRe = makeRegex(#"^##\s+(.*)$"#)
        let boldRe = makeRegex(#"^\s*\d+[.)]\s+\*\*(.+?)\*\*\s*$"#)
        let plainRe = makeRegex(#"^\s*\d+[.)]\s+(.+)$"#)

        var topic = "General"
        var builders: [Builder] = []
        var current: Int?
        var open = false
        var attributed = 0
        var nonBlank = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                nonBlank += 1
            }
            if let groups = regexCaptures(headingRe, line) {
                let text = (groups.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    topic = text
                }
                open = false
                continue
            }
            var questionText: String?
            if let groups = regexCaptures(boldRe, line) {
                questionText = (groups.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let groups = regexCaptures(plainRe, line) {
                questionText = (groups.first ?? "").replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let found = questionText {
                if !found.isEmpty {
                    builders.append(Builder(question: found, topicHint: topic))
                    current = builders.count - 1
                    open = true
                    attributed += 1
                } else {
                    open = false
                }
                continue
            }
            guard open, let index = current else { continue }
            if trimmed.isEmpty {
                builders[index].answerLines.append("")
            } else if line.hasPrefix(" ") || line.hasPrefix("\t") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                builders[index].answerLines.append(stripBulletLine(line))
                attributed += 1
            } else {
                open = false
            }
        }

        var entries: [RawQA] = []
        for (index, builder) in builders.enumerated() {
            entries.append(RawQA(
                question: builder.question,
                answer: buildAnswerParagraphs(builder.answerLines),
                topicHint: builder.topicHint,
                sourceFile: sourceFile,
                sourceIndex: index
            ))
        }
        return finishParse(entries: entries, attributed: attributed, nonBlank: nonBlank)
    }

    private func finishParse(entries: [RawQA], attributed: Int, nonBlank: Int) -> ImportParse {
        let coverage = Double(attributed) / Double(max(1, nonBlank))
        let unknown = entries.count < 3 || coverage < 0.2
        return ImportParse(entries: entries, coverage: coverage, isUnknownFormat: unknown)
    }
}

private func makeRegex(_ pattern: String) -> NSRegularExpression? {
    try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
}

private func matchesPattern(_ line: String, pattern: String) -> Bool {
    line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}

private func regexMatches(_ expression: NSRegularExpression?, _ text: String) -> Bool {
    guard let expression else { return false }
    let range = NSRange(text.startIndex..., in: text)
    return expression.firstMatch(in: text, range: range) != nil
}

private func regexCaptures(_ expression: NSRegularExpression?, _ line: String) -> [String]? {
    guard let expression else { return nil }
    let full = NSRange(line.startIndex..., in: line)
    guard let match = expression.firstMatch(in: line, range: full) else { return nil }
    return (1..<match.numberOfRanges).map { i in
        let range = match.range(at: i)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return "" }
        return String(line[swiftRange])
    }
}

private func regexMatchRange(_ expression: NSRegularExpression?, _ text: String) -> NSRange? {
    guard let expression else { return nil }
    let full = NSRange(text.startIndex..., in: text)
    guard let match = expression.firstMatch(in: text, range: full) else { return nil }
    return match.range(at: 0)
}

private func buildAnswerParagraphs(_ lines: [String]) -> String {
    var paragraphs: [[String]] = []
    var current: [String] = []
    for line in lines {
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
        .joined(separator: "\n\n")
}

private func stripBulletLine(_ line: String) -> String {
    var text = line
    while text.hasPrefix(" ") || text.hasPrefix("\t") {
        text = String(text.dropFirst())
    }
    if text.hasPrefix("-") || text.hasPrefix("*") {
        text = String(text.dropFirst())
        if text.hasPrefix(" ") {
            text = String(text.dropFirst())
        }
    }
    return text
}
