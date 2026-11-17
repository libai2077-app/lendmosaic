import XCTest
import CloudKit
@testable import LendMosaic
@MainActor final class GateTests:XCTestCase {
    func testRecordTypeAndFieldTypes() throws {
        let record=CKRecord(recordType:"AppConfig")
        record["Theme"]="dark" as CKRecordValue
        XCTAssertEqual(try CloudKitConfigService.parse(record).theme,"dark")
        record["ThemeDataDesc"]=NSNumber(value:7)
        XCTAssertThrowsError(try CloudKitConfigService.parse(record))
        record["ThemeDataDesc"]=nil
        record["Theme"]=NSNumber(value:1)
        XCTAssertThrowsError(try CloudKitConfigService.parse(record))
        let wrong=CKRecord(recordType:"Other");wrong["Theme"]="dark" as CKRecordValue
        XCTAssertThrowsError(try CloudKitConfigService.parse(wrong))
    }
    func testPackagedConfigurationMatchesAppIdentity() throws {
        let url=try XCTUnwrap(Bundle.main.url(forResource:"LaunchGateConfig",withExtension:"json"))
        let value=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        XCTAssertEqual(value["container_id"] as? String,"iCloud."+(Bundle.main.bundleIdentifier ?? ""))
        XCTAssertEqual(value["record_name"] as? String,"C8019EAF-8453-4B6E-9088-E9BF25ED7357")
        XCTAssertEqual(value["timeout_seconds"] as? Int,2)
        XCTAssertEqual(value["request_policy"] as? String,"foreground_exponential_backoff_until_success_or_permanent_error");XCTAssertEqual(value["request_timeout_seconds"] as? Int,2)
    }

    func testRenamedCloudFieldDoesNotReadOldKey() throws {
        let record=CKRecord(recordType:"AppConfig")
        record["Theme"]="light" as CKRecordValue
        record["ThemeData"]="https://www.apple.com/old" as CKRecordValue
        XCTAssertNil(try CloudKitConfigService.parse(record).themeData)
        record["ThemeDataDesc"]="https://www.apple.com/new" as CKRecordValue
        XCTAssertEqual(try CloudKitConfigService.parse(record).themeData,"https://www.apple.com/new")
    }
}
