import Testing
@testable import InterviewHelper

@Test func growingPartialsMergeIntoSingleSegment() async {
    let buffer = TranscriptBuffer()
    await buffer.append("what is", isFinal: false)
    await buffer.append("what is weak", isFinal: false)
    await buffer.append("what is weak and unowned", isFinal: false)
    #expect(await buffer.count == 1)
    #expect(await buffer.segments.last?.text == "what is weak and unowned")
}

@Test func finalsAccumulate() async {
    let buffer = TranscriptBuffer()
    await buffer.append("first answer", isFinal: true)
    await buffer.append("second answer", isFinal: true)
    #expect(await buffer.count == 2)
}

@Test func blankAppendsIgnored() async {
    let buffer = TranscriptBuffer()
    await buffer.append("   ", isFinal: false)
    await buffer.append("", isFinal: true)
    #expect(await buffer.count == 0)
}

@Test func windowTextRespectsMaxAge() async throws {
    let buffer = TranscriptBuffer()
    await buffer.append("hello world", isFinal: true)
    #expect(await buffer.windowText() == "hello world")
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(await buffer.windowText(maxAge: 0.01) == "")
}

@Test func windowTextTailTruncatesToMaxChars() async {
    let buffer = TranscriptBuffer()
    await buffer.append("hello world", isFinal: true)
    #expect(await buffer.windowText(maxChars: 5) == "world")
}

@Test func clearResetsCount() async {
    let buffer = TranscriptBuffer()
    await buffer.append("something", isFinal: true)
    #expect(await buffer.count == 1)
    await buffer.clear()
    #expect(await buffer.count == 0)
}

@Test func segmentCapDropsOldest() async {
    let buffer = TranscriptBuffer()
    for i in 0..<205 {
        await buffer.append("final segment \(i)", isFinal: true)
    }
    #expect(await buffer.count == 200)
    #expect(await buffer.segments.first?.text == "final segment 5")
}
