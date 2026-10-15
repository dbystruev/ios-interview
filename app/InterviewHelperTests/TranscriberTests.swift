import XCTest
@testable import InterviewHelper

/// Regression tests for the TestFlight mic crash: starting the audio engine
/// must never trap, with or without microphone permission.
@MainActor
final class TranscriberTests: XCTestCase {
    func testStartWithoutPermissionDoesNotCrash() {
        let transcriber = Transcriber()
        let started = transcriber.start(onResult: { _, _ in })
        // Either the simulator has a usable input (started) or it refuses
        // cleanly with an error — but isListening must always agree.
        XCTAssertEqual(transcriber.isListening, started)
        if !started {
            XCTAssertNotNil(transcriber.lastError)
        }
        transcriber.stop()
        XCTAssertFalse(transcriber.isListening)
    }

    func testStopIsIdempotent() {
        let transcriber = Transcriber()
        transcriber.stop()
        transcriber.stop()
        XCTAssertFalse(transcriber.isListening)
    }

    func testInjectWithoutStartIsIgnored() {
        let transcriber = Transcriber()
        transcriber.injectTranscript("hello")
        XCTAssertFalse(transcriber.isListening)
    }
}
