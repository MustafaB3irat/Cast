import XCTest

final class SetupTests: XCTestCase {
    func testContextualSceneControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-scene-controls"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Live mode"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Actions"].exists)
        XCTAssertTrue(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Actions"].isEnabled, "Tracking loss must disable physical actions")
        XCTAssertLessThan(app.buttons["Go live"].frame.minY, app.buttons["Actions"].frame.minY)
        app.buttons["Live uses microphone & scene data"].tap()
        XCTAssertTrue(app.staticTexts["While Live is on"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testVisualCharacterPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-character-picker"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Who’s joining?"].waitForExistence(timeout: 15))
        let add = app.buttons["Spawn character"]
        XCTAssertTrue(add.isEnabled)
        XCTAssertEqual(add.label, "Add Felipe")
        let carousel = app.scrollViews["Character carousel"]
        carousel.swipeLeft()
        XCTAssertTrue(app.buttons["Look Alfred"].isSelected)
        XCTAssertEqual(add.label, "Add Alfred")
        let name = app.textFields["Their name"]
        name.tap()
        name.typeText("Pip")
        XCTAssertTrue(add.isEnabled)
        app.keyboards.buttons["Done"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Visual character picker"
        attachment.lifetime = .keepAlways
        addAttachment(attachment)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Who’s joining?"].exists)
    }

    private func addAttachment(_ attachment: XCTAttachment) { add(attachment) }

    func testTapPinchAndRotationEditSelectedCharacter() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Characters"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Character preview · use an iPhone for AR"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.52)).tap()
        let transform = app.staticTexts["Selected transform"]
        XCTAssertTrue(transform.waitForExistence(timeout: 5))
        let initial = transform.label
        app.pinch(withScale: 1.2, velocity: 1)
        XCTAssertNotEqual(transform.label, initial, "Pinch must change the selected character’s scale")
        let resized = transform.label
        app.rotate(.pi / 6, withVelocity: 1)
        XCTAssertNotEqual(transform.label, resized, "Two-finger rotation must change yaw")
        XCTAssertTrue(app.buttons["Adjust"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Selected character after pinch and twist"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.staticTexts["Positioning"].exists)
        app.buttons["Ready"].tap()
        XCTAssertFalse(transform.exists)
        XCTAssertFalse(app.buttons["Go live"].exists)
        XCTAssertTrue(app.staticTexts["Add a character to get started"].exists)
    }

    func testCharacterNamesAndConnectionSetupAreAccessible() {
        let app = XCUIApplication()
        app.launch()
        let characters = app.buttons["Characters"]
        XCTAssertTrue(characters.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Actions"].exists)
        XCTAssertFalse(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Go live"].exists)
        XCTAssertTrue(app.staticTexts["Add a character to get started"].exists)
        characters.tap()
        XCTAssertTrue(app.navigationBars["Your cast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit Milo"].exists)
        XCTAssertTrue(app.buttons["Edit Nova"].exists)
        app.buttons["Delete Milo"].tap()
        XCTAssertTrue(app.buttons["Delete character"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Edit Milo"].exists)
        app.buttons["Edit Milo"].tap()
        XCTAssertEqual(app.textFields.matching(identifier: "Name").count, 1)
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.secureTextFields["OpenAI API key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No API key saved"].exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["Go live"].exists)
    }
}
