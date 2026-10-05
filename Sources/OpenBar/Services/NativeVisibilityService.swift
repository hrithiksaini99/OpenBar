import Foundation
@preconcurrency import MenuBarBridge

@MainActor
protocol NativeVisibilityLease: AnyObject {
    func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String],
                  completion: @escaping @MainActor (Result<Void, Error>) -> Void)
    @discardableResult func invalidate() -> Error?
}

@MainActor
protocol NativeVisibilityBackend: AnyObject {
    var isAvailable: Bool { get }
    func makeLease() -> any NativeVisibilityLease
}

@MainActor
private final class RuntimeNativeVisibilityBackend: NativeVisibilityBackend {
    var isAvailable: Bool { OBNativeVisibilityIsAvailable() }
    func makeLease() -> any NativeVisibilityLease { RuntimeLease() }

    private final class RuntimeLease: NativeVisibilityLease {
        private let token = OBNativeVisibilityToken()

        func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String],
                      completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
            token.activate(allowedSystemItems: allowedSystemItems.map(NSNumber.init(value:)),
                           allowedBundleIdentifiers: allowedBundleIdentifiers) { error in
                // The shim explicitly dispatches every callback to the main queue.
                MainActor.assumeIsolated {
                    completion(error.map { .failure($0) } ?? .success(()))
                }
            }
        }

        func invalidate() -> Error? { token.invalidate() }
    }
}

enum NativeVisibilityError: LocalizedError {
    case unavailable
    case missingBundleIdentity
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable: "This macOS build does not provide the native menu bar visibility service. All items remain visible."
        case .missingBundleIdentity: "Run the OpenBar application bundle so macOS can keep its recovery control visible."
        case .timedOut: "macOS did not confirm menu bar hiding in time. OpenBar has cancelled the visibility request."
        }
    }
}

/// Owns the only visibility restriction. Cancelling, revealing, timing out, or
/// replacing a request invalidates stale assertions before they can win a race.
@MainActor
final class NativeVisibilityService {
    // A broader empirical allow-list also preserves Screen Mirroring, which
    // is absent from the upstream 0..<64 list on some macOS 27 configurations.
    // These are private identifiers; future system items require revalidation.
    static let systemItemsToKeep = Array(0..<65535)

    private let backend: any NativeVisibilityBackend
    private let ownBundleIdentifier: String?
    private let activationTimeout: Duration
    private let allowedSystemItems: [Int]
    private var generation: UInt64 = 0
    private var assertion: (any NativeVisibilityLease)?
    private var pending: Request?
    private var cleanupRetries: [any NativeVisibilityLease] = []
    private(set) var lastRestorationError: Error?

    var isAvailable: Bool { backend.isAvailable && ownBundleIdentifier?.isEmpty == false }
    var isActive: Bool { assertion != nil || !cleanupRetries.isEmpty }

    init(backend: (any NativeVisibilityBackend)? = nil,
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         activationTimeout: Duration = .seconds(3),
         allowedSystemItems: [Int] = NativeVisibilityService.systemItemsToKeep) {
        self.backend = backend ?? RuntimeNativeVisibilityBackend()
        self.ownBundleIdentifier = ownBundleIdentifier
        self.activationTimeout = activationTimeout
        self.allowedSystemItems = allowedSystemItems
    }

    func activate(allowing bundleIdentifiers: Set<String>) async throws {
        try Task.checkCancellation()
        guard backend.isAvailable else { reveal(); throw NativeVisibilityError.unavailable }
        guard let ownBundleIdentifier, !ownBundleIdentifier.isEmpty else {
            reveal()
            throw NativeVisibilityError.missingBundleIdentity
        }
        generation &+= 1
        let currentGeneration = generation
        cancelPending()
        let allowed = bundleIdentifiers.union([ownBundleIdentifier]).filter { !$0.isEmpty }.sorted()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let request = Request(lease: backend.makeLease(), continuation: continuation)
                pending = request
                request.timeoutTask = Task { [weak self, weak request] in
                    do { try await Task.sleep(for: self?.activationTimeout ?? .seconds(3)) }
                    catch { return }
                    guard let self, let request, currentGeneration == generation,
                          pending === request else { return }
                    finishFailure(request, error: NativeVisibilityError.timedOut)
                }
                request.lease.activate(allowedSystemItems: allowedSystemItems,
                                       allowedBundleIdentifiers: allowed) { [weak self, request] result in
                    guard let self else {
                        request.lease.invalidate()
                        request.finish(.failure(CancellationError()))
                        return
                    }
                    guard currentGeneration == generation, pending === request else {
                        cleanUp(request.lease)
                        request.finish(.failure(CancellationError()))
                        return
                    }
                    switch result {
                    case .success:
                        let old = assertion
                        assertion = request.lease
                        pending = nil
                        if let old, let error = cleanUp(old) {
                            finishFailure(request, error: error)
                            return
                        }
                        request.finish(.success(()))
                    case .failure(let error):
                        finishFailure(request, error: error)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, currentGeneration == generation else { return }
                reveal()
            }
        }
        try Task.checkCancellation()
        // Show All can run after the callback resumes this continuation but
        // before this task next receives the main actor. Do not report a stale
        // success to its caller even when that caller did not cancel its Task.
        guard currentGeneration == generation, assertion != nil else { throw CancellationError() }
    }

    /// Immediate Show All and shutdown path; also retries any exceptional cleanup.
    func reveal() {
        generation &+= 1
        lastRestorationError = nil
        let retries = cleanupRetries
        cleanupRetries.removeAll()
        for lease in retries { cleanUp(lease) }
        cancelPending()
        if let assertion {
            self.assertion = nil
            cleanUp(assertion)
        }
    }

    private func cancelPending() {
        guard let request = pending else { return }
        pending = nil
        cleanUp(request.lease)
        request.finish(.failure(CancellationError()))
    }

    private func finishFailure(_ request: Request, error: Error) {
        pending = nil
        generation &+= 1
        cleanUp(request.lease)
        if let assertion {
            self.assertion = nil
            cleanUp(assertion)
        }
        request.finish(.failure(error))
    }

    @discardableResult private func cleanUp(_ lease: any NativeVisibilityLease) -> Error? {
        if let error = lease.invalidate() {
            lastRestorationError = error
            if !cleanupRetries.contains(where: { $0 === lease }) { cleanupRetries.append(lease) }
            return error
        } else {
            cleanupRetries.removeAll { $0 === lease }
            return nil
        }
    }

    private final class Request {
        let lease: any NativeVisibilityLease
        private var continuation: CheckedContinuation<Void, Error>?
        var timeoutTask: Task<Void, Never>?

        init(lease: any NativeVisibilityLease, continuation: CheckedContinuation<Void, Error>) {
            self.lease = lease
            self.continuation = continuation
        }

        func finish(_ result: Result<Void, Error>) {
            timeoutTask?.cancel()
            timeoutTask = nil
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }
}
