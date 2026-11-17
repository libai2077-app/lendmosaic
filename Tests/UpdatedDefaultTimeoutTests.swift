import Foundation
import Testing
@testable import LendMosaic

// Hold a valid light response beyond the white-cover deadline.
private actor HeldConfigService: AppConfigServing {
    private var pending: CheckedContinuation<AppConfigModel, Never>?
    private(set) var calls = 0
    private(set) var returned = false

    func fetch() async throws -> AppConfigModel {
        calls += 1
        let model = await withCheckedContinuation { pending = $0 }
        returned = true
        return model
    }

    func release() {
        pending?.resume(returning: .init(
            theme: "light", themeData: "BQS?8F#ks-AU%X#E,9)<@rH2"
        ))
        pending = nil
    }
}

@MainActor private final class TimeoutLauncher: ExternalURLLaunching {
    private(set) var calls = 0
    func open(_ url: URL) async -> Bool {
        calls += 1
        return true
    }
}

@MainActor @Test func defaultEightSecondCoverRevealsNativeWhileReadingContinues() async {
    let service = HeldConfigService()
    let launcher = TimeoutLauncher()
    // Keep the default cover deadline and isolate it from the request deadline.
    let gate = LaunchGateManager(service: service, launcher: launcher, requestTimeout: .seconds(12))
    #expect(gate.isCovering)
    let clock = ContinuousClock()
    let started = clock.now
    gate.start()

    // Observe the actual timer, allowing one second for test-runner scheduling.
    while gate.isCovering && clock.now - started < .seconds(9) {
        try? await Task.sleep(for: .milliseconds(5))
    }
    let elapsed = clock.now - started
    #expect(elapsed >= .seconds(8))
    #expect(elapsed < .seconds(9))
    #expect(!gate.isCovering) // Root adapters reveal the existing native content.
    #expect(gate.hasStarted)
    #expect(!gate.hasAttemptedOpen)
    #expect(launcher.calls == 0)
    #expect(await service.calls == 1)
    #expect(await service.returned == false) // Native fallback precedes the response.

    // Release the otherwise valid redirect only after native fallback.
    await service.release()
    let responseDeadline = clock.now + .seconds(1)
    while !(await service.returned) && clock.now < responseDeadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(await service.returned)
    // Allow the manager to consume the resumed request and any queued launch work.
    try? await Task.sleep(for: .milliseconds(100))
    #expect(!gate.isCovering)
    #expect(gate.hasAttemptedOpen)
    #expect(launcher.calls == 1)

    // Returning/reattaching a root cannot reset the completed launch.
    gate.start()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await service.calls == 1)
    #expect(!gate.isCovering)
    #expect(launcher.calls == 1)
}
