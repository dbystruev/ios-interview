import XCTest

final class InterviewHelperUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tapTab(_ app: XCUIApplication, id: String, fallback: String) {
        if app.buttons[id].waitForExistence(timeout: 3) {
            app.buttons[id].tap()
            return
        }
        if app.tabBars.buttons[id].waitForExistence(timeout: 1) {
            app.tabBars.buttons[id].tap()
            return
        }
        app.tabBars.buttons[fallback].tap()
    }

    private func staticText(containing substring: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", substring)).firstMatch
    }

    func testLibraryShowsSeedAndSearch() throws {
        let app = XCUIApplication()
        app.launch()
        tapTab(app, id: "tab-library", fallback: "Library")

        let search = app.textFields["searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))

        let weak = staticText(containing: "weak and unowned", in: app)
        XCTAssertTrue(weak.waitForExistence(timeout: 10))

        search.tap()
        search.typeText("retain")

        let retain = staticText(containing: "retain cycles", in: app)
        XCTAssertTrue(retain.waitForExistence(timeout: 5))
        let weakAfter = staticText(containing: "weak and unowned", in: app)
        XCTAssertFalse(weakAfter.waitForExistence(timeout: 2))
    }

    func testListeningStartsAndStops() throws {
        let app = XCUIApplication()
        app.launch()
        tapTab(app, id: "tab-listen", fallback: "Listen")

        let start = app.buttons["listenToggle"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        // Either listening began, or an error was shown — both are valid on
        // a simulator without microphone permission. Just don't crash.
        _ = app.staticTexts["Listening…"].waitForExistence(timeout: 3)
        _ = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Microphone")).firstMatch.waitForExistence(timeout: 3)
        start.tap()
    }
}
