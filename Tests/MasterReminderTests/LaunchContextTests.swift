import XCTest
import AppKit
import Carbon
@testable import MasterReminder

final class LaunchContextTests: XCTestCase {
    private func event(reason: AEKeyword? = nil, id: AEEventID = kAEOpenApplication) -> NSAppleEventDescriptor {
        let value = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: id,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let reason { value.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: keyAEPropData) }
        return value
    }
    func testDirectExecutableLaunchShowsUI() { XCTAssertFalse(LaunchContext.isBackgroundLaunch(nil)) }
    func testFinderLaunchShowsUI() { XCTAssertFalse(LaunchContext.isBackgroundLaunch(event())) }
    func testLoginItemLaunchStaysInBackground() { XCTAssertTrue(LaunchContext.isBackgroundLaunch(event(reason: keyAELaunchedAsLogInItem))) }
    func testServiceItemLaunchStaysInBackground() { XCTAssertTrue(LaunchContext.isBackgroundLaunch(event(reason: keyAELaunchedAsServiceItem))) }
    func testReopenIsNotBackgroundLaunch() { XCTAssertFalse(LaunchContext.isBackgroundLaunch(event(reason: keyAELaunchedAsLogInItem, id: kAEReopenApplication))) }
}
