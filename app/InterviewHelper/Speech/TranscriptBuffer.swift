import Foundation

public actor TranscriptBuffer {
    public struct Segment: Sendable {
        public var text: String
        public var date: Date
        public var isFinal: Bool

        public init(text: String, date: Date, isFinal: Bool) {
            self.text = text
            self.date = date
            self.isFinal = isFinal
        }
    }

    public var segments: [Segment] = []
    private static let cap = 200

    public init() {}

    public func append(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = segments.last, !last.isFinal,
           trimmed.hasPrefix(last.text) || trimmed.contains(last.text) {
            segments[segments.count - 1].text = trimmed
            segments[segments.count - 1].isFinal = isFinal
        } else {
            segments.append(Segment(text: trimmed, date: Date(), isFinal: isFinal))
        }
        if segments.count > Self.cap {
            segments.removeFirst(segments.count - Self.cap)
        }
    }

    public func windowText(maxAge: TimeInterval = 60, maxChars: Int = 2000) -> String {
        guard maxChars > 0 else { return "" }
        let now = Date()
        let joined = segments
            .filter { now.timeIntervalSince($0.date) < maxAge }
            .map(\.text)
            .joined(separator: " ")
        return String(joined.suffix(maxChars))
    }

    public func clear() {
        segments.removeAll()
    }

    public var count: Int {
        segments.count
    }
}
