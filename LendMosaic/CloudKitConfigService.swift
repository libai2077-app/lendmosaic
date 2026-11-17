#if canImport(CloudKit)
import CloudKit
public struct CloudKitConfigService: AppConfigServing {
    private let configuration: LaunchGateConfiguration
    public init(configuration: LaunchGateConfiguration) { self.configuration = configuration }
    public func fetch() async throws -> AppConfigModel {
        guard configuration.containerID.hasPrefix("iCloud."),
              configuration.containerID.count > "iCloud.".count,
              !configuration.containerID.contains(where: { $0.isWhitespace }),
              !configuration.recordName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvalidRecord()
        }
        #if CLOUDKIT_UNSIGNED_BUILD
        // CKContainer requires iCloud entitlements, which unsigned builds lack.
        throw CloudKitSigningUnavailable()
        #else
        let database = CKContainer(identifier: configuration.containerID).publicCloudDatabase
        let record = try await database.record(for: CKRecord.ID(recordName: configuration.recordName))
        return try Self.parse(record)
        #endif
    }
    static func parse(_ record: CKRecord) throws -> AppConfigModel {
        guard record.recordType == "AppConfig", let theme = record["Theme"] as? String,
              record["ThemeDataDesc"] == nil || record["ThemeDataDesc"] is String else { throw InvalidRecord() }
        return AppConfigModel(theme: theme, themeData: record["ThemeDataDesc"] as? String)
    }
    private struct InvalidRecord: Error {}
    struct CloudKitSigningUnavailable: Error {}
}
#endif
