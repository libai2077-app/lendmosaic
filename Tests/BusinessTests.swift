import XCTest
@testable import LendMosaic
@MainActor final class BusinessTests:XCTestCase {
    func file()->URL {URL.temporaryDirectory.appending(path:UUID().uuidString).appending(path:"records.json")}
    func testEmptyRepository() {let r=Repository<[String]>(initial:[],url:file());XCTAssertTrue(r.value.isEmpty);XCTAssertFalse(r.readFailed)}
    func testAtomicWriteAndRead() {let u=file();let r=Repository<[String]>(initial:[],url:u);XCTAssertTrue(r.update(["a"]));XCTAssertEqual(Repository<[String]>(initial:[],url:u).value,["a"])}
    func testCorruptReadDoesNotOverwrite() throws {let u=file();try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);let bytes=Data("broken".utf8);try bytes.write(to:u);let r=Repository<[String]>(initial:[],url:u);XCTAssertTrue(r.readFailed);XCTAssertFalse(r.update(["replacement"]));XCTAssertEqual(try Data(contentsOf:u),bytes)}
    func testWriteFailureKeepsMemory() throws {let u=file();try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try Data().write(to:u);let r=Repository<[String]>(initial:[],url:u.appending(path:"child"));XCTAssertFalse(r.update(["a"]));XCTAssertTrue(r.value.isEmpty);XCTAssertNotNil(r.error)}
    func testLanguageResolution() {XCTAssertEqual(Languages.resolve("system",preferred:["zh-Hans"]),"en");XCTAssertEqual(Languages.resolve("system",preferred:["pt-PT"]),"pt-BR");XCTAssertEqual(Languages.resolve("it",preferred:["en"]),"it");for code in Languages.codes{XCTAssertEqual(Languages.resolve("system",preferred:[code]),code)}}
    func testEightCompiledLanguages() throws {XCTAssertEqual(Languages.codes.count,8);for code in Languages.codes{let path=try XCTUnwrap(Bundle.main.path(forResource:code,ofType:"lproj"));let b=try XCTUnwrap(Bundle(path:path));let text=b.localizedString(forKey:"Appearance",value:nil,table:"Localizable");XCTAssertFalse(text.isEmpty);if code != "en"{XCTAssertNotEqual(text,"Appearance")}}}
    func testExportRoundTrip() throws {let r=Repository<[String]>(initial:["a","b"],url:file());XCTAssertEqual(try JSONDecoder().decode([String].self,from:r.encoded()),["a","b"])}

 func sample()->Loan{Loan(name:"Drill",borrower:"Alex",category:"Tools",lent:Date(timeIntervalSince1970:1000),due:Date(timeIntervalSince1970:200000))}
 func testReturnPersistsAndCannotRepeat(){let u=file();let m=LendModel(url:u);let p=sample();_ = m.save(p);let date=Date(timeIntervalSince1970:300000);XCTAssertTrue(m.returnItem(p.id,at:date));XCTAssertFalse(m.returnItem(p.id,at:date));XCTAssertTrue(m.active.isEmpty);XCTAssertEqual(LendModel(url:u).history[0].returned,date)}
 func testUndoReturnPreservesDates(){let m=LendModel(url:file());let p=sample();_ = m.save(p);_ = m.returnItem(p.id);XCTAssertTrue(m.reopen(p.id));XCTAssertEqual(m.active[0].due,p.due);XCTAssertTrue(m.history.isEmpty)}
 func testInvalidDateOrder(){var p=sample();p.due=p.lent.addingTimeInterval(-1);XCTAssertFalse(p.valid);p.due=p.lent;p.returned=p.lent.addingTimeInterval(-1);XCTAssertFalse(p.valid)}
 func testCannotReturnBeforeLending(){let m=LendModel(url:file());let p=sample();_ = m.save(p);XCTAssertFalse(m.returnItem(p.id,at:p.lent.addingTimeInterval(-1)));XCTAssertEqual(m.active.count,1)}
 func testDueTodayUsesCalendar(){let day=Calendar.current.startOfDay(for:Date());var p=sample();p.due=day.addingTimeInterval(3600);XCTAssertEqual(p.days(at:day.addingTimeInterval(70000)),0);XCTAssertEqual(p.status(at:day),"Due today")}
 func testActiveSortedByDue(){let m=LendModel(url:file());var a=sample();var b=sample();a.due=Date(timeIntervalSince1970:500000);b.due=Date(timeIntervalSince1970:300000);_ = m.save(a);_ = m.save(b);XCTAssertEqual(m.active.first?.id,b.id)}
 func testRequiredBorrowerAndCategory(){var p=sample();p.borrower=" ";XCTAssertFalse(p.valid);p.borrower="A";p.category="";XCTAssertFalse(p.valid)}
 func testCRUDPersists(){let u=file();let m=LendModel(url:u);var p=sample();_ = m.save(p);p.name="Changed";_ = m.save(p);XCTAssertEqual(LendModel(url:u).records[0].name,"Changed");m.delete(p);XCTAssertTrue(LendModel(url:u).records.isEmpty)}
 func testSeedDoesNotReplace(){let m=LendModel(url:file());_ = m.save(sample());m.seed();XCTAssertEqual(m.records.count,1)}

 func testRejectPartialOrGroupedNumericInput(){UserDefaults.standard.set("en",forKey:"language");defer{UserDefaults.standard.removeObject(forKey:"language")};XCTAssertNil(decimal("1.2.3"));XCTAssertNil(decimal("1,234"));XCTAssertEqual(decimal("1.25"),1.25)}
 func testFutureLendingRejected(){var p=sample();p.lent=Date().addingTimeInterval(86400);p.due=p.lent.addingTimeInterval(86400);XCTAssertFalse(p.valid)}
 func testThemeLabelsAcrossEightLanguages() throws {for code in Languages.codes {let path=try XCTUnwrap(Bundle.main.path(forResource:code,ofType:"lproj"));let bundle=try XCTUnwrap(Bundle(path:path));for key in ["Light","Dark"] {let value=bundle.localizedString(forKey:key,value:key,table:"Localizable");XCTAssertFalse(value.isEmpty);if code != "en"{XCTAssertNotEqual(value,key)}}}}
 func testCommaLocaleAcceptsKeyboardDotWithoutGrouping(){UserDefaults.standard.set("de",forKey:"language");defer{UserDefaults.standard.removeObject(forKey:"language")};XCTAssertEqual(decimal("1,25"),1.25);XCTAssertEqual(decimal("1.25"),1.25);XCTAssertNil(decimal("1.234,56"))}
}
