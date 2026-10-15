import XCTest

final class PhoneUITests: XCTestCase {
    @MainActor func testGuidedCreationPersistsAcrossLaunch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["new-reminder"].waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "iPhone-home"; home.lifetime = .keepAlways; add(home)
        app.buttons["new-reminder"].tap()
        XCTAssertTrue(app.buttons["category-custom"].waitForExistence(timeout: 5))
        let wizard = XCTAttachment(screenshot: app.screenshot()); wizard.name = "iPhone-categories"; wizard.lifetime = .keepAlways; add(wizard)
        app.buttons["category-custom"].tap()
        let title = app.textFields["reminder-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("اختبار الهاتف")
        app.swipeUp()
        let save = app.buttons["save-reminder"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(app.buttons["new-reminder"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["اختبار الهاتف"].waitForExistence(timeout: 10))
        // Alarm authorization and ringing are deliberately excluded from simulator UI tests.
    }
}
