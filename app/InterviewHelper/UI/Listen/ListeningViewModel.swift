import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class ListeningViewModel {
    struct FeedItem: Sendable, Hashable, Identifiable {
        var id: String
        var entryID: String
        var text: String
        var isAI: Bool
    }

    var cards: [ScoredEntry] = []
    var feed: [FeedItem] = []
    var transcriptPreview: String = ""
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
    private var currentTopID: String?
    private var currentTopScore: Double = 0
    private var currentTopDate: Date?
    private var emptySince: Date?
    private var lastAIFire: Date?
    private var lastTalkAt: Date?
    private var lastFedEntryID: String?

    init(context: ModelContext, settings: AppSettings, transcriber: Transcriber = Transcriber()) {
        self.context = context
        self.settings = settings
        self.transcriber = transcriber
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

    func toggle() {
        if isListening { stopListening() } else { startListening() }
    }

    private func startListening() {
        // Outer task holds self weakly so inner [weak self] captures agree
        // (and a dismissed view aborts the start instead of leaking).
        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            await strongSelf.transcriber.requestAuthorization()
            guard strongSelf.transcriber.authState == .granted else {
                strongSelf.errorMessage = "Microphone and speech recognition access is required. Allow access in Settings → Apps → Interview Helper, then try again."
                return
            }
            strongSelf.refreshIndex(context: strongSelf.context)
            await strongSelf.buffer.clear()
            strongSelf.aiAnswer = nil
            strongSelf.aiBusy = false
            strongSelf.emptySince = Date()
            strongSelf.errorMessage = nil
            strongSelf.feed = []
            strongSelf.lastFedEntryID = nil
            strongSelf.lastTalkAt = Date()
            strongSelf.showStop = false
            let started = strongSelf.transcriber.start(onResult: { [weak self] text, isFinal in
                Task { @MainActor [weak self] in
                    await self?.receivedTranscript(text, isFinal: isFinal)
                }
            })
            guard started else {
                strongSelf.errorMessage = strongSelf.transcriber.lastError ?? "Could not start listening."
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
            // Stop appears only after 2s of silence, hides the moment talk resumes.
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
    }

    private func receivedTranscript(_ text: String, isFinal: Bool) async {
        lastTalkAt = Date()
        if showStop { showStop = false }
        await buffer.append(text, isFinal: isFinal)
        transcriptPreview = await buffer.windowText(maxAge: settings.windowSeconds, maxChars: 2000)
        await matchNow()
    }

    func matchNow() async {
        let window = await buffer.windowText(maxAge: settings.windowSeconds, maxChars: 2000)
        transcriptPreview = window
        if window.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let matcher = TopicMatcher(threshold: settings.matchThreshold, limit: 3)
        let ranked = matcher.rank(query: window, entries: index)
        if let top = ranked.first {
            let topID = "\(top.entry.id)"
            if currentTopID == nil || cards.isEmpty {
                applyTop(id: topID, score: top.score, ranked: ranked)
            } else if topID == currentTopID {
                cards = ranked
                currentTopScore = top.score
                currentTopDate = Date()
                emptySince = nil
                aiTask?.cancel()
                if aiAnswer != nil { aiAnswer = nil }
            } else {
                let stale = currentTopDate.map { Date().timeIntervalSince($0) > 15 } ?? true
                if TopicMatcher.shouldSwap(currentScore: currentTopScore, newScore: top.score, currentStale: stale) {
                    applyTop(id: topID, score: top.score, ranked: ranked)
                }
            }
        } else {
            if emptySince == nil { emptySince = Date() }
        }
        maybeTriggerAI()
    }

    private func applyTop(id: String, score: Double, ranked: [ScoredEntry]) {
        cards = ranked
        currentTopID = id
        currentTopScore = score
        currentTopDate = Date()
        emptySince = nil
        aiTask?.cancel()
        if aiAnswer != nil { aiAnswer = nil }
        appendFeed(entryID: id, text: feedText(for: ranked.first?.entry), isAI: false)
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
        if cards.isEmpty == false { return }
        if settings.aiFallbackEnabled == false { return }
        if aiBusy { return }
        if aiAnswer != nil { return }
        let emptyFor = emptySince.map { Date().timeIntervalSince($0) } ?? 0
        if emptyFor < 5 { return }
        if let last = lastAIFire, Date().timeIntervalSince(last) < 10 { return }
        guard let llm = settings.makeLLM() else { return }
        aiBusy = true
        lastAIFire = Date()
        aiTask?.cancel()
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiBusy = false }
            let seed = SourceRegistry.loadSeed(bundle: .main)
            let registry = SourceRegistry(seed: seed, customHosts: self.settings.customSourceHosts)
            let window = await self.buffer.windowText(maxAge: self.settings.windowSeconds, maxChars: 2000)
            do {
                let answer = try await llm.answer(transcript: window, nearMiss: nil, allowedHosts: Array(registry.allowedHosts), topic: nil)
                if Task.isCancelled { return }
                if self.cards.isEmpty {
                    self.aiAnswer = answer
                    self.appendFeed(entryID: "ai-\(UUID().uuidString)", text: answer.text, isAI: true)
                }
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
            await matchNow()
        }
    }

    func saveAIAnswer(topic name: String) async {
        guard let answer = aiAnswer else { return }
        let trimmed = transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
