import XCTest

final class PhoneUITests: XCTestCase {
    @MainActor func testPrayerHasMuezzinAndCanBeMuted() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-data"]; app.launch()
        XCTAssertTrue(app.buttons["new-reminder"].waitForExistence(timeout: 15)); app.buttons["new-reminder"].tap()
        XCTAssertTrue(app.buttons["category-prayer"].waitForExistence(timeout: 5)); app.buttons["category-prayer"].tap()
        let sound = app.buttons["audio.settings"]
        for _ in 0..<4 where !sound.isHittable { app.swipeUp() }
        XCTAssertTrue(sound.waitForExistence(timeout: 5)); sound.tap()
        XCTAssertTrue(app.buttons["audio.muezzin"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "iPhone-sound-picker"; screenshot.lifetime = .keepAlways; add(screenshot)
        let row = app.switches["audio.enabled"]
        XCTAssertTrue(row.exists)
        // SwiftUI exposes the labelled Form row and its native UISwitch separately.
        // Tapping the row centre hits its label; target the actual switch control.
        let toggle = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["audio.muezzin"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        let muted = XCTAttachment(screenshot: app.screenshot()); muted.name = "iPhone-silent-reminder"; muted.lifetime = .keepAlways; add(muted)
        toggle.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["audio.muezzin"].waitForExistence(timeout: 5))
    }
    @MainActor func testGuidedCreationPersistsAcrossLaunch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-data"]; app.launch()
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
        XCTAssertTrue(save.waitForExistence(timeout: 5)); for _ in 0..<4 where !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertTrue(app.buttons["new-reminder"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.staticTexts["اختبار الهاتف"].waitForExistence(timeout: 10))
        // Alarm authorization and ringing are deliberately excluded from simulator UI tests.
    }
}
