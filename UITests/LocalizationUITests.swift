import XCTest
@MainActor final class LocalizationUITests:XCTestCase {
    var code="en"
    var words:[String:String]=[:]
    override func setUpWithError() throws {
        continueAfterFailure=false
        let candidate=(Locale.preferredLanguages.first ?? "en").replacingOccurrences(of:"_",with:"-")
        code=candidate.hasPrefix("pt") ? "pt-BR":candidate.components(separatedBy:"-")[0]
        if !["en","ja","ko","es","fr","de","pt-BR","it"].contains(code){code="en"}
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"LocalizationExpectedText",withExtension:"json"))
        words=try XCTUnwrap(JSONDecoder().decode([String:[String:String]].self,from:Data(contentsOf:url))[code],"Missing language expectations")
    }
    func t(_ key:String)->String {words[key]!}
    func launch(seed:Bool=true,theme:String="light",large:Bool=false)->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--ui-test","--reset-data"]+(seed ? ["--demo-data"]:[])
        app.launchEnvironment=["TEST_LANGUAGE":code,"TEST_THEME":theme]
        app.launchArguments += ["-AppleLanguages","(\(code))","-AppleLocale",code]
        if large {app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
        app.launch();XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:12));return app
    }
    func shot(_ name:String,_ app:XCUIApplication) {Thread.sleep(forTimeInterval:0.8);let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func tab(_ index:Int,_ app:XCUIApplication) {app.tabBars.buttons.element(boundBy:index).tap()}
    func openSample(_ app:XCUIApplication) { 
        let row=app.staticTexts["Trail camera"].firstMatch;XCTAssertTrue(row.waitForExistence(timeout:5));row.tap();XCTAssertTrue(app.buttons["editRecord"].waitForExistence(timeout:5))
    }
    func testStorePages() {
        let app=launch();XCTAssertTrue(app.staticTexts[t("On loan")].exists || app.navigationBars[t("On loan")].exists);shot("Home",app)
        tab(1,app);shot("Collection",app);tab(0,app)
        openSample(app);shot("Detail",app)
        let result=app.buttons["resultLink"];if !result.isHittable {app.swipeUp()};result.tap();XCTAssertTrue(app.navigationBars.firstMatch.exists);shot("Result",app)
        tab(2,app);XCTAssertTrue(app.staticTexts[t("Appearance")].waitForExistence(timeout:5));shot("Settings",app)
    }
    func testInvalidAndCreate() {
        let app=launch(seed:false); 
        XCTAssertTrue(app.staticTexts[t("No records yet")].waitForExistence(timeout:5));shot("Empty",app)
        app.buttons["addRecord"].tap();app.buttons["saveRecord"].tap();XCTAssertTrue(app.staticTexts["validationError"].waitForExistence(timeout:3));shot("Validation",app)
        let field=app.textFields["nameField"];field.tap();field.typeText("New record")
        let b=app.textFields["borrowerField"];b.tap();b.typeText("Alex");let c=app.textFields["categoryField"];c.tap();c.typeText("Tools")
        shot("Editor",app);app.buttons["saveRecord"].tap();XCTAssertTrue(app.staticTexts["New record"].waitForExistence(timeout:5))
    }
    func testEditRestartAndDelete() {
        let app=launch();openSample(app);app.buttons["editRecord"].tap();let field=app.textFields["nameField"];XCTAssertTrue(field.waitForExistence(timeout:4));field.tap();field.typeText(" revised");app.buttons["saveRecord"].tap();XCTAssertTrue(app.buttons["editRecord"].waitForExistence(timeout:4))
        app.terminate();app.launchArguments=["--ui-test"];app.launch();XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:12));
        let row=app.staticTexts["Trail camera revised"].firstMatch;XCTAssertTrue(row.waitForExistence(timeout:5));row.tap();let del=app.buttons["deleteRecord"];if !del.isHittable{app.swipeUp()};del.tap();app.buttons.matching(NSPredicate(format:"label == %@ AND identifier != %@",t("Delete"),"deleteRecord")).firstMatch.tap();XCTAssertTrue(row.waitForNonExistence(timeout:5))
    }
    func testPreferencesAndThemes() {
        let app=launch();tab(2,app)
        app.buttons["appearancePicker"].tap();app.buttons[t("Dark")].tap();shot("DarkSettings",app)
        app.buttons["appearancePicker"].tap();app.buttons[t("System")].tap();app.buttons["appearancePicker"].tap();app.buttons[t("Light")].tap()
        app.buttons["languagePicker"].tap();app.buttons["日本語"].tap();XCTAssertTrue(app.staticTexts["外観"].waitForExistence(timeout:4))
        app.terminate();app.launchEnvironment.removeValue(forKey:"TEST_LANGUAGE");app.launchEnvironment.removeValue(forKey:"TEST_THEME");app.launchArguments=["--ui-test"];app.launch();XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:12));tab(2,app);XCTAssertTrue(app.staticTexts["外観"].waitForExistence(timeout:4))
    }
    func testLargeDarkPages() {let app=launch(theme:"dark",large:true);shot("LargeDarkHome",app);shot("LargeDarkCollection",app);tab(2,app);shot("LargeDarkSettings",app)}
    func testReturnAndUndo(){let app=launch();openSample(app);app.buttons["returnItem"].tap();app.buttons.matching(NSPredicate(format:"label == %@ AND identifier != %@",t("Mark returned"),"returnItem")).firstMatch.tap();XCTAssertTrue(app.buttons["undoReturn"].waitForExistence(timeout:4));shot("ReturnedItem",app);app.buttons["undoReturn"].tap();XCTAssertTrue(app.buttons["returnItem"].waitForExistence(timeout:4))}
}
