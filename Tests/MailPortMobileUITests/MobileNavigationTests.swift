import XCTest

final class MobileNavigationTests: XCTestCase {
    @MainActor func testAccountCreationAndServiceNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--mailport-ui-test"]
        app.launch()
        let add = app.buttons["Add Account"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["Name, such as Work"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Demo " + String(UUID().uuidString.prefix(4)))
        let accountName = name.value as! String
        app.buttons["Add"].tap()
        let mailTitle = app.navigationBars[accountName + " · Mail"]
        XCTAssertTrue(mailTitle.waitForExistence(timeout: 10), "Creating an account opens its Mail view on a compact screen")
        // On phones Back returns to the account sidebar. On larger windows the
        // sidebar remains visible, or can be revealed with its toolbar control.
        if !app.buttons["Open Service"].firstMatch.isHittable {
            let back = mailTitle.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        let open = app.buttons["Open Service"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("YouTube")
        app.buttons["YouTube"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[accountName + " · YouTube"].waitForExistence(timeout: 10))
        app.buttons["More"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Files you download from this view appear here."].exists)
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let skip = app.switches["youtubeAutoSkipAds"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertEqual(skip.value as? String, "0")
        // SwiftUI exposes the whole labelled row as a switch; tap its thumb.
        skip.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let enabled = NSPredicate(format: "value == %@", "1")
        expectation(for: enabled, evaluatedWith: skip)
        waitForExpectations(timeout: 5)
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["youtubeAutoSkipAds"].value as? String, "1")
        app.buttons["Done"].tap()
    }
}
