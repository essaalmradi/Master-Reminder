import XCTest
@testable import ReminderCore

final class ResourceBundleTests: XCTestCase {
    func testInstalledMacAppLoadsResourcesFromContentsResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Master Reminder.app")
        let resource = app.appendingPathComponent("Contents/Resources/MasterReminder_ReminderCore.bundle")
        try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "test.masterreminder.resources", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.masterreminder.fixture", "CFBundlePackageType": "BNDL"], format: .xml, options: 0).write(to: resource.appendingPathComponent("Info.plist"))
        try "bundled".write(to: resource.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let application = try XCTUnwrap(Bundle(url: app))
        let found = try XCTUnwrap(AppResources.installedBundle(in: application))
        let text = try String(contentsOf: XCTUnwrap(found.url(forResource: "fixture", withExtension: "txt")), encoding: .utf8)
        XCTAssertEqual(text, "bundled")
        XCTAssertTrue(found.bundleURL.resolvingSymlinksInPath().path.hasPrefix(app.resolvingSymlinksInPath().path + "/Contents/Resources/"))
    }
    func testMissingInstalledResourcesAreReportedWithoutBuildPathFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Empty.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.masterreminder.empty", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let application = try XCTUnwrap(Bundle(url: app))
        XCTAssertNil(AppResources.installedBundle(in: application))
    }
}
