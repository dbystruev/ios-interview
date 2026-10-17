import Foundation
import Observation
import SwiftData
import UIKit

@MainActor @Observable
final class ListeningViewModel {
    struct FeedItem: Sendable, Hashable, Identifiable {
        var id: String
        var entryID: String
        var text: String
        var isAI: Bool
    }

    /// What is being said right now — single scrolling line while talking.
    var currentUtterance: String = ""
    /// Completed phrases after pauses — shown when nothing is being said.
    var lastSaidPhrases: String = ""

    var feed: [FeedItem] = []
    var isListening: Bool = false
    var showStop = false
    var aiAnswer: GeneratedAnswer?
    var aiBusy: Bool = false
    var errorMessage: String?

    private let context: ModelContext
    private let settings: AppSettings
    private let transcriber: Transcriber
    private let buffer = TranscriptBuffer()

    private var index: [MatchableEntry] = []
    private var matchTask: Task<Void, Never>?
    private var stopWatchTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var lastTalkAt: Date?
    private var lastFedEntryID: String?
    private var lastMatchTime: Date?

    init(context: ModelContext, settings: AppSettings, transcriber: Transcriber = Transcriber()) {
        self.context = context
        self.settings = settings
        self.transcriber = transcriber
    }

    func toggle() {
        if isListening { stopListening() } else { startListening() }
    }

    private func startListening() {
        // Keep the screen on while the app is actively working.
        UIApplication.shared.isIdleTimerDisabled = true

        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            await strongSelf.transcriber.requestAuthorization()
            guard strongSelf.transcriber.authState == .granted else {
                strongSelf.errorMessage = "Microphone and speech recognition access is required. Allow access in Settings → Apps → Interview Helper, then try again."
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            strongSelf.refreshIndex(context: strongSelf.context)
            await strongSelf.buffer.clear()
            strongSelf.aiAnswer = nil
            strongSelf.aiBusy = false
            strongSelf.errorMessage = nil
            strongSelf.currentUtterance = ""
            strongSelf.lastSaidPhrases = ""
            strongSelf.feed = []
            strongSelf.lastFedEntryID = nil
            strongSelf.lastTalkAt = Date()
            strongSelf.lastMatchTime = nil
            strongSelf.showStop = false

            let started = strongSelf.transcriber.start(onResult: { [weak self] text, isFinal in
                Task { @MainActor [weak self] in
                    await self?.receivedTranscript(text, isFinal: isFinal)
                }
            })
            guard started else {
                strongSelf.errorMessage = strongSelf.transcriber.lastError ?? "Could not start listening."
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            strongSelf.isListening = true

            strongSelf.matchTask?.cancel()
            strongSelf.matchTask = Task { @MainActor [weak self] in
                while let strong = self, strong.isListening {
                    try? await Task.sleep(for: .seconds(2))
                    if Task.isCancelled { break }
                    await strong.matchNow()
                }
            }

            strongSelf.stopWatchTask?.cancel()
            strongSelf.stopWatchTask = Task { @MainActor [weak self] in
                while let strong = self, strong.isListening {
                    try? await Task.sleep(for: .seconds(0.5))
                    if Task.isCancelled { break }
                    let silentFor = Date().timeIntervalSince(strong.lastTalkAt ?? Date())
                    let shouldShow = silentFor >= 2
                    if strong.showStop != shouldShow { strong.showStop = shouldShow }
                }
            }
        }
    }

    private func stopListening() {
        matchTask?.cancel()
        matchTask = nil
        stopWatchTask?.cancel()
        stopWatchTask = nil
        showStop = false
        aiTask?.cancel()
        transcriber.stop()
        isListening = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func receivedTranscript(_ text: String, isFinal: Bool) async {
        lastTalkAt = Date()
        if showStop { showStop = false }

        if isFinal {
            lastSaidPhrases = (lastSaidPhrases + " " + text).trimmingCharacters(in: .whitespacesAndNewlines)
            currentUtterance = ""
        } else {
            currentUtterance = text
        }

        await buffer.append(text, isFinal: isFinal)
        await matchNow()
    }

    private func matchNow() async {
        // Match against what is being said right now — short and clean.
        let text = currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let matcher = TopicMatcher(threshold: settings.matchThreshold, limit: 3)
        let ranked = matcher.rank(query: text, entries: index)

        if let top = ranked.first {
            let topID = "\(top.entry.id)"
            if lastFedEntryID != topID {
                lastFedEntryID = topID
                appendFeed(entryID: topID, text: feedText(for: top.entry), isAI: false)
            }
            lastMatchTime = Date()
        } else {
            lastMatchTime = nil
        }
        maybeTriggerAI()
    }

    /// Answers only — newest last. Same entry re-matching appends nothing.
    private func appendFeed(entryID: String, text: String, isAI: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isAI, lastFedEntryID == entryID { return }
        if !isAI { lastFedEntryID = entryID }
        feed.append(FeedItem(id: UUID().uuidString, entryID: entryID, text: trimmed, isAI: isAI))
        if feed.count > 30 { feed.removeFirst(feed.count - 30) }
    }

    private func feedText(for entry: MatchableEntry?) -> String {
        guard let entry else { return "" }
        return entry.answer.isEmpty ? entry.question : entry.answer
    }

    private func maybeTriggerAI() {
        if settings.aiFallbackEnabled == false { return }
        if aiBusy { return }
        if aiAnswer != nil { return }
        guard let lastMatch = lastMatchTime, Date().timeIntervalSince(lastMatch) >= 5 else { return }
        guard let llm = settings.makeLLM() else { return }
        aiBusy = true
        lastMatchTime = Date()
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiBusy = false }
            let seed = SourceRegistry.loadSeed(bundle: .main)
            let registry = SourceRegistry(seed: seed, customHosts: self.settings.customSourceHosts)
            let window = self.currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let answer = try await llm.answer(transcript: window, nearMiss: nil, allowedHosts: Array(registry.allowedHosts), topic: nil)
                if Task.isCancelled { return }
                self.aiAnswer = answer
                self.appendFeed(entryID: "ai-\(UUID().uuidString)", text: answer.text, isAI: true)
            } catch {
                if Task.isCancelled { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func injectTestTranscript(_ text: String) {
        lastTalkAt = Date()
        showStop = false
        Task {
            refreshIndex(context: context)
            await buffer.append(text, isFinal: true)
            currentUtterance = text
            lastSaidPhrases = text
            await matchNow()
        }
    }

    func saveAIAnswer(topic name: String) async {
        guard let answer = aiAnswer else { return }
        let trimmed = currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = trimmed.isEmpty ? "Live interview question" : String(trimmed.prefix(200))
        let keywords = KeywordSuggest.suggest(from: question + " " + answer.text, limit: 8)
        let normalized = NormalizedQA(
            question: question,
            answer: answer.text,
            topic: name,
            keywords: keywords,
            citations: answer.citations,
            sourceFile: "live",
            sourceIndex: 0,
            isFollowUp: false,
            parentQuestionText: "",
            isAIGenerated: true,
            needsReview: false
        )
        let service = MergeService(modelContext: context, nearDuplicateThreshold: 0.8, allowedHosts: [], llm: nil)
        _ = await service.importEntries([normalized])
        aiAnswer = nil
        refreshIndex(context: context)
    }

    func refreshIndex(context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<QAEntry>())) ?? []
        index = entries.map { entry in
            MatchableEntry(
                id: "\(entry.persistentModelID)",
                question: entry.question,
                answer: entry.hasAnswer ? entry.answer : "",
                keywords: entry.keywords,
                topicName: entry.topic?.name ?? "General"
            )
        }
    }
}
