import Testing
@testable import InterviewHelper

private func fixtures() -> [MatchableEntry] {
    [
        MatchableEntry(
            id: "weak-unowned",
            question: "What is the difference between weak and unowned references in Swift?",
            answer: "Weak references are optional and nil out on deallocation; unowned references are non-optional and expected to always have a value during their lifetime.",
            keywords: ["weak", "unowned", "ARC", "memory"],
            topicName: "Memory Management"
        ),
        MatchableEntry(
            id: "mvc-mvvm",
            question: "What is MVC and how does it compare to MVVM?",
            answer: "MVC separates Model, View and Controller, while MVVM introduces a ViewModel that exposes bindable view state.",
            keywords: ["mvc", "mvvm", "architecture"],
            topicName: "Architecture"
        ),
        MatchableEntry(
            id: "viewdidload",
            question: "When is viewDidLoad called in a view controller lifecycle?",
            answer: "viewDidLoad is called once after the controller's view is loaded into memory.",
            keywords: ["viewDidLoad", "lifecycle", "UIKit"],
            topicName: "UIKit"
        )
    ]
}

@Test func weakUnownedQueryRanksWeakFirst() {
    let matcher = TopicMatcher()
    let results = matcher.rank(
        query: "what is the difference between weak and unowned references",
        entries: fixtures()
    )
    #expect(!results.isEmpty)
    #expect(results.first?.entry.id == "weak-unowned")
}

@Test func mvcQueryRanksMvcFirst() {
    let matcher = TopicMatcher()
    let results = matcher.rank(
        query: "Explain MVC and MVVM architecture differences",
        entries: fixtures()
    )
    #expect(!results.isEmpty)
    #expect(results.first?.entry.id == "mvc-mvvm")
}

@Test func emptyQueryReturnsEmpty() {
    let matcher = TopicMatcher()
    #expect(matcher.rank(query: "", entries: fixtures()).isEmpty)
    #expect(matcher.rank(query: "   ", entries: fixtures()).isEmpty)
    #expect(matcher.rank(query: "what is the", entries: fixtures()).isEmpty)
}

@Test func emptyEntriesReturnsEmpty() {
    let matcher = TopicMatcher()
    #expect(matcher.rank(query: "what is weak", entries: []).isEmpty)
}

@Test func gibberishQueryBelowThreshold() {
    let matcher = TopicMatcher()
    let results = matcher.rank(query: "xqzt blorpt fnord wibble", entries: fixtures())
    #expect(results.isEmpty)
}

@Test func shouldSwapLogic() {
    #expect(!TopicMatcher.shouldSwap(currentScore: 0.5, newScore: 0.55, currentStale: false))
    #expect(TopicMatcher.shouldSwap(currentScore: 0.5, newScore: 0.7, currentStale: false))
    #expect(TopicMatcher.shouldSwap(currentScore: 0.9, newScore: 0.5, currentStale: true))
    #expect(!TopicMatcher.shouldSwap(currentScore: 0.9, newScore: 0.95, currentStale: false))
}
