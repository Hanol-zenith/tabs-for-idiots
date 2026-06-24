import XCTest

final class TabsForIdiotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSongListLoads() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Tabs for Idiots"].exists)
    }
}
