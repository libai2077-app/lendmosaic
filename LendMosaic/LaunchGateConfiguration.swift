import Foundation
public struct LaunchGateConfiguration: Sendable {
    public static let defaultTimeout: Duration = .seconds(8)
    public let containerID: String
    public let recordName: String
    public let timeout: Duration
    public init(containerID: String, recordName: String, timeout: Duration = LaunchGateConfiguration.defaultTimeout) {
        self.containerID = containerID
        self.recordName = recordName
        self.timeout = timeout > .zero ? timeout : Self.defaultTimeout
    }
}
