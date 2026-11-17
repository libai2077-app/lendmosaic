import Foundation
public struct AppConfigModel: Sendable {
    public let theme: String
    public let themeData: String?
    public init(theme: String, themeData: String?) { self.theme = theme; self.themeData = themeData }
}
public protocol AppConfigServing: Sendable {
    func fetch() async throws -> AppConfigModel
}
@MainActor public protocol ExternalURLLaunching {
    func open(_ url: URL) async -> Bool
}
