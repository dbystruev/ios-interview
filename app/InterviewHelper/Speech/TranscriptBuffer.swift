import Foundation
import OSLog

private let speechLog = Logger(subsystem: "com.hurated.interview", category: "speech")

/// Drops speech-recognition hallucinations: recognizers fed with non-speech
/// audio (room tone, music, noise) emit memorized-looking junk — code, markup,
/// URLs — that must never become transcript or match candidates.
public enum TranscriptSanitizer: Sendable {
    /// True when `text` carries no plausible spoken content.
    public static func isJunk(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // Markup / code can never be spoken content.
        if trimmed.contains("<") || trimmed.contains(">") { return true }
        let lower = trimmed.lowercased()
        for marker in ["http://", "https://", "www.", "src=", "href=", "<script", ".js", ".com/", ".net/", ".io/"] {
            if lower.contains(marker) { return true }
        }
        // Mostly symbols/digits, almost no letters (e.g. "12345", "***").
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let total = trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        if total > 0, Double(letters) / Double(total) < 0.5 { return true }
        return false
    }
}

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

    public private(set) var droppedJunk = 0

    public func append(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if TranscriptSanitizer.isJunk(trimmed) {
            droppedJunk += 1
            speechLog.debug("Dropped junk transcript segment (final=\(isFinal)): \(trimmed, privacy: .public)")
            return
        }
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
