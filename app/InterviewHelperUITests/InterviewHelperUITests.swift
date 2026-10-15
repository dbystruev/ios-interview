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

    func testListeningTypedTranscript() throws {
        let app = XCUIApplication()
        app.launch()
        tapTab(app, id: "tab-listen", fallback: "Listen")

        let field = app.textFields["typedTranscript"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("difference between weak and unowned references")
        app.buttons["matchButton"].tap()

        let card = staticText(containing: "weak and unowned", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
}
