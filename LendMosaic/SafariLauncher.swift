#if canImport(UIKit)
import UIKit
@MainActor public struct SafariLauncher: ExternalURLLaunching {
    public init() {}
    public func open(_ url: URL) async -> Bool {
        guard URLValidator.validate(url.absoluteString) != nil else { return false }
        return await UIApplication.shared.open(url, options: [:])
    }
}
#endif
