import XCTest
@testable import OpenBar

@MainActor
private final class ControlledVisibilityBackend: NativeVisibilityBackend {
    var isAvailable = true
    var leases: [ControlledLease] = []

    func makeLease() -> any NativeVisibilityLease {
        let lease = ControlledLease()
        leases.append(lease)
        return lease
    }

    final class ControlledLease: NativeVisibilityLease {
        private(set) var systemItems: [Int] = []
        private(set) var bundles: [String] = []
        private(set) var invalidations = 0
        var invalidationError: Error?
        var completion: (@MainActor (Result<Void, Error>) -> Void)?

        func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String],
                      completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
            systemItems = allowedSystemItems
            bundles = allowedBundleIdentifiers
            self.completion = completion
        }

        func invalidate() -> Error? {
            invalidations += 1
            return invalidationError
        }
    }
}

final class NativeVisibilityServiceTests: XCTestCase {
    @MainActor private func waitForRequests(_ count: Int, backend: ControlledVisibilityBackend) async {
        for _ in 0..<100 where backend.leases.count < count { await Task.yield() }
        XCTAssertEqual(backend.leases.count, count)
    }

    @MainActor func testActivationPreservesOwnIdentityAndEntireSystemAllowList() async throws {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar")
        let task = Task { try await service.activate(allowing: ["com.kept", "", "com.openbar"]) }
        await waitForRequests(1, backend: backend)
        XCTAssertEqual(backend.leases[0].bundles, ["com.kept", "com.openbar"])
        XCTAssertEqual(backend.leases[0].systemItems, Array(0..<256))
        backend.leases[0].completion?(.success(()))
        try await task.value
        XCTAssertTrue(service.isActive)
        service.reveal()
        XCTAssertFalse(service.isActive)
        XCTAssertEqual(backend.leases[0].invalidations, 1)
    }

    @MainActor func testShowAllCancelsPendingRequestAndInvalidatesLateSuccess() async {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar")
        let task = Task { try await service.activate(allowing: []) }
        await waitForRequests(1, backend: backend)
        service.reveal()
        do { try await task.value; XCTFail("Show All must cancel the pending request") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(backend.leases[0].invalidations, 1)
        backend.leases[0].completion?(.success(()))
        XCTAssertEqual(backend.leases[0].invalidations, 2)
        XCTAssertFalse(service.isActive)
    }

    @MainActor func testShowAllBetweenSuccessCallbackAndTaskResumptionRejectsStaleSuccess() async {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar")
        let task = Task { try await service.activate(allowing: []) }
        await waitForRequests(1, backend: backend)
        backend.leases[0].completion?(.success(()))
        service.reveal()
        do { try await task.value; XCTFail("A reveal before task resumption must revoke success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(service.isActive)
    }

    @MainActor func testTaskCancellationRestoresImmediatelyAndRejectsLateCompletion() async {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar")
        let task = Task { try await service.activate(allowing: []) }
        await waitForRequests(1, backend: backend)
        task.cancel()
        do { try await task.value; XCTFail("Cancellation must finish without framework completion") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertGreaterThanOrEqual(backend.leases[0].invalidations, 1)
        backend.leases[0].completion?(.success(()))
        XCTAssertFalse(service.isActive)
    }

    @MainActor func testTimeoutRestoresActiveAndPendingRestrictions() async throws {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar",
                                              activationTimeout: .milliseconds(30))
        let first = Task { try await service.activate(allowing: ["com.first"]) }
        await waitForRequests(1, backend: backend)
        backend.leases[0].completion?(.success(()))
        try await first.value
        let second = Task { try await service.activate(allowing: ["com.second"]) }
        await waitForRequests(2, backend: backend)
        do { try await second.value; XCTFail("Unanswered activation must time out") }
        catch { XCTAssertTrue(error is NativeVisibilityError) }
        XCTAssertFalse(service.isActive)
        XCTAssertEqual(backend.leases[0].invalidations, 1)
        XCTAssertEqual(backend.leases[1].invalidations, 1)
        backend.leases[1].completion?(.success(()))
        XCTAssertEqual(backend.leases[1].invalidations, 2)
    }

    @MainActor func testSupersededActivationCannotOverwriteNewerSuccessfulRequest() async throws {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar")
        let first = Task { try await service.activate(allowing: ["com.first"]) }
        await waitForRequests(1, backend: backend)
        let second = Task { try await service.activate(allowing: ["com.second"]) }
        await waitForRequests(2, backend: backend)
        backend.leases[1].completion?(.success(()))
        try await second.value
        do { try await first.value; XCTFail("Superseded request must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        backend.leases[0].completion?(.success(()))
        XCTAssertTrue(service.isActive)
        XCTAssertEqual(backend.leases[0].invalidations, 2)
        XCTAssertEqual(backend.leases[1].invalidations, 0)
        service.reveal()
    }

    @MainActor func testCleanupExceptionsKeepHandleForRetry() async throws {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: "com.openbar")
        let task = Task { try await service.activate(allowing: []) }
        await waitForRequests(1, backend: backend)
        backend.leases[0].completion?(.success(()))
        try await task.value
        backend.leases[0].invalidationError = NSError(domain: "cleanup", code: 1)
        service.reveal()
        XCTAssertNotNil(service.lastRestorationError)
        XCTAssertTrue(service.isActive, "Unconfirmed restoration must retain the assertion")
        backend.leases[0].invalidationError = nil
        service.reveal()
        XCTAssertNil(service.lastRestorationError)
        XCTAssertFalse(service.isActive)
        XCTAssertEqual(backend.leases[0].invalidations, 2)
    }

    @MainActor func testMissingIdentityNeverStartsAnAssertion() async {
        let backend = ControlledVisibilityBackend()
        let service = NativeVisibilityService(backend: backend, ownBundleIdentifier: nil)
        XCTAssertFalse(service.isAvailable)
        do { try await service.activate(allowing: []); XCTFail("Missing app identity must fail open") }
        catch { XCTAssertTrue(error is NativeVisibilityError) }
        XCTAssertTrue(backend.leases.isEmpty)
    }
}
