import Foundation
import Testing
@testable import LendMosaic

private struct Service: AppConfigServing {
    var model = AppConfigModel(theme: "dark", themeData: nil)
    var fails = false
    var delay: Duration = .zero
    func fetch() async throws -> AppConfigModel {
        // Deliberately ignore cancellation to exercise late responses.
        if delay > .zero {
            let delay = delay
            await Task.detached { try? await Task.sleep(for: delay) }.value
        }
        if fails { throw Failure() }
        return model
    }
    struct Failure: Error {}
}
@MainActor private final class Launcher: ExternalURLLaunching {
    var calls = 0
    var success: Bool
    init(_ success: Bool = true) { self.success = success }
    func open(_ url: URL) async -> Bool { calls += 1; return success }
}
@Test func ascii85() throws {
    #expect(String(data: try Ascii85Decoder.decode("<~87cURD_*#TDfTZ)+T~>"), encoding: .utf8) == "Hello, world!")
    #expect(try Ascii85Decoder.decode("z") == Data([0,0,0,0]))
    #expect(try Ascii85Decoder.decode("").isEmpty)
    #expect(try Ascii85Decoder.decode("!!") == Data([0]))
    for input in ["!", "uuuuu", "!z", "<~abc", "y", "~~~~~", "é"] {
        #expect(throws: (any Error).self) { try Ascii85Decoder.decode(input) }
    }
}
@Test func urls() {
    #expect(URLValidator.validate("https://example.com/a?q=b") != nil)
    #expect(URLValidator.decode("https://example.com/a?q=b")?.absoluteString == "https://example.com/a?q=b")
    for value in ["", "http://example.com", "javascript:alert(1)", "https:///", "https://u:p@example.com", "https://example.com/ a", "https://example.com\n", "file:///tmp/x", "https://example.com:0"] {
        #expect(URLValidator.validate(value) == nil)
        #expect(URLValidator.decode(value) == nil)
    }
    #expect(URLValidator.decode("BQS?8F#ks-AU%X#E,9)<@rH2")?.host == "example.com")
    #expect(URLValidator.decode("rr") == nil) // Non-UTF8 decoded byte.
}
@MainActor @Test func decisions() async throws {
    for (theme, data, expected) in [("dark", "BQS?8F#ks-AU%X#E,9)<@rH2", 0), ("light", "BQS?8F#ks-AU%X#E,9)<@rH2", 1), ("light", "https://example.com/a?q=b", 1), ("light", "http://example.com", 0), ("light", "", 0), ("light", nil, 0), ("light", "invalid", 0), ("other", "BQS?8F#ks-AU%X#E,9)<@rH2", 0)] as [(String, String?, Int)] {
        for success in [true, false] {
            let launcher = Launcher(success)
            let gate = LaunchGateManager(service: Service(model: .init(theme: theme, themeData: data)), launcher: launcher)
            #expect(gate.isCovering)
            gate.start(); gate.start()
            try await Task.sleep(for: .milliseconds(20))
            #expect(!gate.isCovering)
            #expect(launcher.calls == expected)
            gate.start() // Simulate browser return/root recreation.
            #expect(!gate.isCovering)
            #expect(launcher.calls == expected)
        }
    }
}
@MainActor @Test func failureAndDeadline() async throws {
    let launcher = Launcher()
    let failed = LaunchGateManager(service: Service(fails: true), launcher: launcher)
    failed.start()
    try await Task.sleep(for: .milliseconds(20))
    #expect(!failed.isCovering)
    let slow = LaunchGateManager(service: Service(model: .init(theme: "light", themeData: "BQS?8F#ks-AU%X#E,9)<@rH2"), delay: .milliseconds(120)), launcher: launcher, timeout: .milliseconds(15), requestTimeout: .milliseconds(25), retryDelays: [.seconds(1)])
    slow.start()
    try await Task.sleep(for: .milliseconds(60))
    #expect(!slow.isCovering)
    #expect(launcher.calls == 0)
    slow.start()
    try await Task.sleep(for: .milliseconds(150))
    #expect(!slow.isCovering)
    #expect(launcher.calls == 0)
    slow.cancel()
    let cancelled = LaunchGateManager(service: Service(), launcher: launcher)
    cancelled.cancel(); cancelled.start()
    #expect(!cancelled.isCovering)
    #expect(LaunchGateConfiguration(containerID: "test", recordName: "test").timeout == .seconds(8))
}

private actor CountingService: AppConfigServing {
    private(set) var calls = 0
    func fetch() async throws -> AppConfigModel {
        calls += 1
        return .init(theme: "light", themeData: "BQS?8F#ks-AU%X#E,9)<@rH2")
    }
}
@MainActor private final class InspectingLauncher: ExternalURLLaunching {
    weak var gate: LaunchGateManager?
    var calls = 0
    var callbackFinished = false
    func open(_ url: URL) async -> Bool {
        calls += 1
        #expect(!Task.isCancelled)
        #expect(gate?.isCovering == false)
        #expect(gate?.hasAttemptedOpen == true)
        gate?.start() // Reentrant activation must not restart the gate.
        try? await Task.sleep(for: .milliseconds(80))
        callbackFinished = true
        return false
    }
}
@MainActor @Test func requestOnceAndClearBeforeOpenCompletion() async throws {
    let service = CountingService()
    let launcher = InspectingLauncher()
    let gate = LaunchGateManager(service: service, launcher: launcher)
    launcher.gate = gate
    for _ in 0..<10 { gate.start() }
    let deadline = ContinuousClock.now + .seconds(2)
    while !launcher.callbackFinished && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(launcher.callbackFinished)
    #expect(await service.calls == 1)
    #expect(launcher.calls == 1)
    #expect(!gate.isCovering)
    gate.start()
    #expect(launcher.calls == 1)
}
@Test func configurationAndDecoderBoundaries() throws {
    #expect(LaunchGateConfiguration.defaultTimeout == .seconds(8))
    for duration in [Duration.zero, .seconds(-1)] {
        #expect(LaunchGateConfiguration(containerID: "test", recordName: "test", timeout: duration).timeout == .seconds(8))
    }
    #expect(LaunchGateConfiguration(containerID: "test", recordName: "test", timeout: .seconds(3)).timeout == .seconds(3))
    #expect(try Ascii85Decoder.decode(" <~ z ~> \n") == Data([0,0,0,0]))
    #expect(throws: (any Error).self) { try Ascii85Decoder.decode(String(repeating: " ", count: 32769)) }
    for value in ["https://example.com/%", "https://example.com/%GG", "https://example.com/\\path", "https://:443", "https://example.com:65536"] {
        #expect(URLValidator.validate(value) == nil)
    }
}
#if canImport(CloudKit)
import CloudKit
@Test func cloudKitRecordFields() throws {
    let record = CKRecord(recordType: "AppConfig")
    record["Theme"] = "dark"
    #expect(try CloudKitConfigService.parse(record).theme == "dark")
    #expect(try CloudKitConfigService.parse(record).themeData == nil)
    record["Theme"] = "light"
    record["ThemeDataDesc"] = ""
    #expect(try CloudKitConfigService.parse(record).themeData == "")
    record["ThemeDataDesc"] = "BQS?8F#ks-AU%X#E,9)<@rH2"
    #expect(URLValidator.decode(try CloudKitConfigService.parse(record).themeData) != nil)
    record["ThemeDataDesc"] = "https://example.com/welcome"
    #expect(URLValidator.decode(try CloudKitConfigService.parse(record).themeData)?.absoluteString == "https://example.com/welcome")
    record["ThemeDataDesc"] = 42
    #expect(throws: (any Error).self) { try CloudKitConfigService.parse(record) }
    record["ThemeDataDesc"] = nil
    record["Theme"] = 42
    #expect(throws: (any Error).self) { try CloudKitConfigService.parse(record) }
    record["Theme"] = nil
    #expect(throws: (any Error).self) { try CloudKitConfigService.parse(record) }
    let wrong = CKRecord(recordType: "Other")
    wrong["Theme"] = "dark"
    #expect(throws: (any Error).self) { try CloudKitConfigService.parse(wrong) }
}
#endif

#if canImport(CloudKit)
@Test func invalidCloudConfigurationFailsWithoutNetwork() async {
    for configuration in [
        LaunchGateConfiguration(containerID: "", recordName: "config"),
        LaunchGateConfiguration(containerID: "wrong", recordName: "config"),
        LaunchGateConfiguration(containerID: "iCloud.example", recordName: " ")
    ] {
        do {
            _ = try await CloudKitConfigService(configuration: configuration).fetch()
            Issue.record("Invalid configuration must fail before a CloudKit request")
        } catch { }
    }
}
#endif

#if canImport(CloudKit) && CLOUDKIT_UNSIGNED_BUILD
@Test func unsignedBuildReturnsSigningErrorBeforeOpeningContainer() async {
    let configuration = LaunchGateConfiguration(containerID: "iCloud.example", recordName: "config")
    await #expect(throws: CloudKitConfigService.CloudKitSigningUnavailable.self) {
        try await CloudKitConfigService(configuration: configuration).fetch()
    }
}
#endif

private actor FirstNetworkRequestFails: AppConfigServing {
    private(set) var calls = 0
    func fetch() async throws -> AppConfigModel {
        calls += 1
        if calls == 1 { throw URLError(.notConnectedToInternet) }
        return .init(theme: "light", themeData: "BQS?8F#ks-AU%X#E,9)<@rH2")
    }
}

@MainActor @Test func permissionRecoveryWaitsForActiveScene() async throws {
    let service = FirstNetworkRequestFails()
    let launcher = Launcher()
    let gate = LaunchGateManager(service: service, launcher: launcher, retryDelays: [.milliseconds(80)])
    gate.start()
    gate.sceneDidChange(isActive: false, isBackground: false)
    try await Task.sleep(for: .milliseconds(120))
    #expect(await service.calls == 1)
    #expect(launcher.calls == 0)
    #expect(!gate.isCovering)

    gate.sceneDidChange(isActive: true, isBackground: false)
    try await Task.sleep(for: .milliseconds(40))
    #expect(await service.calls == 2)
    #expect(launcher.calls == 1)
}

@MainActor @Test func deferredLinkReopensAfterEveryBackgroundReturn() async throws {
    let service = Service(model: .init(theme: "light", themeData: "BQS?8F#ks-AU%X#E,9)<@rH2"), delay: .milliseconds(55))
    let launcher = Launcher()
    let gate = LaunchGateManager(service: service, launcher: launcher, timeout: .milliseconds(15))
    gate.start()
    gate.sceneDidChange(isActive: false, isBackground: true)
    try await Task.sleep(for: .milliseconds(450))
    #expect(!gate.isCovering)
    #expect(launcher.calls == 0)

    gate.sceneDidChange(isActive: true, isBackground: false)
    try await Task.sleep(for: .milliseconds(30))
    #expect(launcher.calls == 1)

    gate.sceneDidChange(isActive: false, isBackground: false)
    gate.sceneDidChange(isActive: true, isBackground: false)
    try await Task.sleep(for: .milliseconds(20))
    #expect(launcher.calls == 1) // A prompt or interruption alone does not count as a return.

    gate.sceneDidChange(isActive: false, isBackground: true)
    gate.sceneDidChange(isActive: true, isBackground: false)
    try await Task.sleep(for: .milliseconds(30))
    #expect(launcher.calls == 2)

    gate.sceneDidChange(isActive: false, isBackground: true)
    gate.sceneDidChange(isActive: true, isBackground: false)
    try await Task.sleep(for: .milliseconds(20))
    #expect(launcher.calls == 3)
}

@MainActor private final class DelayedReturnLauncher: ExternalURLLaunching {
    private var firstOpen: CheckedContinuation<Bool, Never>?
    private(set) var calls = 0

    func open(_ url: URL) async -> Bool {
        calls += 1
        if calls == 1 {
            return await withCheckedContinuation { firstOpen = $0 }
        }
        return true
    }

    func completeFirstOpen(_ success: Bool) {
        firstOpen?.resume(returning: success)
        firstOpen = nil
    }
}

@MainActor @Test func returningBeforeOpenCallbackWaitsForSuccess() async throws {
    for didOpen in [true, false] {
        let launcher = DelayedReturnLauncher()
        let gate = LaunchGateManager(service: CountingService(), launcher: launcher)
        gate.start()
        let deadline = ContinuousClock.now + .seconds(1)
        while launcher.calls == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(launcher.calls == 1)
        gate.sceneDidChange(isActive: false, isBackground: true)
        gate.sceneDidChange(isActive: true, isBackground: false)
        #expect(launcher.calls == 1)
        launcher.completeFirstOpen(didOpen)
        try await Task.sleep(for: .milliseconds(40))
        #expect(launcher.calls == (didOpen ? 2 : 1))
    }
}


private actor RetryingConfigService: AppConfigServing {
    private(set) var calls = 0
    private(set) var returnedStaleLink = false

    func fetch() async throws -> AppConfigModel {
        calls += 1
        if calls == 1 {
            await Task.detached { try? await Task.sleep(for: .milliseconds(200)) }.value
            returnedStaleLink = true
            return .init(theme: "light", themeData: "BQS?8F#ks-AU%X#E,9)<@rH2")
        }
        if calls < 7 { throw URLError(.notConnectedToInternet) }
        return .init(theme: "dark", themeData: nil)
    }
}

@MainActor @Test func retriesPastPreviousLimitAndDiscardsTimedOutResult() async throws {
    let service = RetryingConfigService()
    let launcher = Launcher()
    let gate = LaunchGateManager(service: service, launcher: launcher,
                                 requestTimeout: .milliseconds(40), retryDelays: [.milliseconds(15)])
    gate.start()
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        let calls = await service.calls
        let returned = await service.returnedStaleLink
        if calls >= 7 && returned { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await service.calls == 7)
    #expect(await service.returnedStaleLink)
    #expect(launcher.calls == 0)
    #expect(!gate.isCovering)
    gate.cancel()
}
