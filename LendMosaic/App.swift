import SwiftUI
@main struct LendMosaicApp:App {
  @State private var gate = LaunchGateManager(configuration: LaunchGateConfiguration(containerID: "iCloud.com.taskstudio.lendmosaic", recordName: "C8019EAF-8453-4B6E-9088-E9BF25ED7357", timeout: .seconds(2)))
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            if ProcessInfo.processInfo.arguments.contains("--reset-data") { try? FileManager.default.removeItem(at:URL.documentsDirectory.appending(path:"records.json")); UserDefaults.standard.removeObject(forKey:"language");UserDefaults.standard.removeObject(forKey:"appearance") }
            if let language=ProcessInfo.processInfo.environment["TEST_LANGUAGE"] {UserDefaults.standard.set(language,forKey:"language")}
            if let theme=ProcessInfo.processInfo.environment["TEST_THEME"] {UserDefaults.standard.set(theme,forKey:"appearance")}
        }
    }
    var body:some Scene {WindowGroup { LaunchGateRoot(manager: gate) { ProductRoot() } }}
}
