import DateProviderTestHelpers
import EmceeLogging
import EmceeLoggingTestHelpers
import Foundation
import Logging
import QueueCommunicationTestHelpers
import QueueModels
@testable import QueueServer
import WorkerAlivenessProvider
import XCTest

final class SilentWorkerAutoKickstartPollerTests: XCTestCase {
    private lazy var worker1 = WorkerId("worker1")
    private lazy var worker2 = WorkerId("worker2")
    private lazy var startDate = Date(timeIntervalSince1970: 1_000_000)
    private lazy var dateProvider = DateProviderFixture(startDate)
    private lazy var workerAlivenessProvider = WorkerAlivenessProviderImpl(
        logger: .noOp,
        workerPermissionProvider: FakeWorkerPermissionProvider()
    )
    private lazy var starter = RecordingOnDemandWorkerStarter()
    private lazy var logHandler = FakeLoggerHandle()
    private lazy var settings = SilentWorkerAutoKickstartSettings(
        silenceThreshold: 300,
        maxAttemptsPerWorker: 2,
        cooldown: 120
    )

    func test___silent_worker___not_kickstarted_before_threshold() {
        makeSilent(worker1)
        // worker2 жив, иначе сработает защита от массового молчания
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 299)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [])
    }

    func test___silent_worker___kickstarted_once_threshold_passed() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [worker1])
    }

    func test___still_silent_worker___not_kickstarted_again_within_cooldown() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 119)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [worker1])
    }

    func test___still_silent_worker___kickstarted_again_after_cooldown() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 120)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [worker1, worker1])
    }

    func test___attempts_exhausted___worker_is_not_kickstarted_anymore() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 120)
        poller.performTick()
        advance(by: 3600)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [worker1, worker1])
    }

    func test___worker_recovered_and_silent_again___threshold_counts_from_new_silence() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 200)
        markAlive(worker1)
        poller.performTick()
        advance(by: 50)
        workerAlivenessProvider.setWorkerIsSilent(workerId: worker1)
        poller.performTick()
        advance(by: 299)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [])
    }

    func test___attempts___are_not_reset_when_worker_recovers() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        for _ in 0..<3 {
            poller.performTick()
            advance(by: 300)
            poller.performTick()
            markAlive(worker1)
            poller.performTick()
            workerAlivenessProvider.setWorkerIsSilent(workerId: worker1)
        }

        XCTAssertEqual(starter.startedWorkerIds, [worker1, worker1])
    }

    func test___kickstart_in_flight___not_started_again_after_cooldown() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        var pendingKickstarts = [() -> Void]()
        let poller = createPoller(kickstartExecutor: { pendingKickstarts.append($0) })

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 120)
        poller.performTick()

        XCTAssertEqual(pendingKickstarts.count, 1)
    }

    func test___finished_kickstart___allows_next_attempt_after_cooldown() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        var pendingKickstarts = [() -> Void]()
        let poller = createPoller(kickstartExecutor: { pendingKickstarts.append($0) })

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        pendingKickstarts.removeFirst()()
        advance(by: 120)
        poller.performTick()

        XCTAssertEqual(pendingKickstarts.count, 1)
    }

    func test___disabled_silent_worker___not_kickstarted() {
        makeSilent(worker1)
        workerAlivenessProvider.disableWorker(workerId: worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [])
    }

    func test___all_registered_workers_silent___nobody_kickstarted() {
        makeSilent(worker1)
        makeSilent(worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [])
    }

    func test___workers_never_registered___kickstarted_after_threshold() {
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [worker1, worker2])
    }

    func test___log___fired_with_attempt_number() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 120)
        poller.performTick()

        XCTAssertEqual(
            logMessages(containing: "auto-kickstart fired"),
            [
                "auto-kickstart fired for worker1 (attempt 1/2)",
                "auto-kickstart fired for worker1 (attempt 2/2)",
            ]
        )
    }

    func test___failed_start___logged_and_counted_as_attempt() {
        starter.error = TestError()
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 120)
        poller.performTick()
        advance(by: 120)
        poller.performTick()

        XCTAssertEqual(starter.startedWorkerIds, [worker1, worker1])
        XCTAssertEqual(
            logMessages(containing: "auto-kickstart failed"),
            [
                "auto-kickstart failed for worker1 (attempt 1/2): test error",
                "auto-kickstart failed for worker1 (attempt 2/2): test error",
            ]
        )
    }

    func test___attempts_exhausted___gave_up_logged_once() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        for _ in 0..<5 {
            advance(by: 300)
            poller.performTick()
        }

        XCTAssertEqual(logMessages(containing: "auto-kickstart gave up").count, 1)
        XCTAssertEqual(
            logMessages(containing: "auto-kickstart gave up").first?.hasPrefix("auto-kickstart gave up for worker1 after 2 attempts"),
            true
        )
    }

    func test___all_registered_workers_silent___skip_logged_once_per_episode() {
        makeSilent(worker1)
        makeSilent(worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 300)
        poller.performTick()
        advance(by: 30)
        poller.performTick()

        XCTAssertEqual(
            logMessages(containing: "auto-kickstart skipped"),
            ["auto-kickstart skipped: all 2 registered workers are silent"]
        )
    }

    func test___candidate___logged_once_and_recovery_logged() {
        makeSilent(worker1)
        workerAlivenessProvider.didRegisterWorker(workerId: worker2)
        let poller = createPoller()

        poller.performTick()
        advance(by: 30)
        poller.performTick()
        markAlive(worker1)
        poller.performTick()

        XCTAssertEqual(
            logMessages(containing: "auto-kickstart candidate"),
            [
                "auto-kickstart candidate worker1 (silent)",
                "auto-kickstart candidate worker1 recovered",
            ]
        )
    }

    // MARK: - Helpers

    private func createPoller(
        kickstartExecutor: @escaping (@escaping () -> Void) -> Void = { $0() }
    ) -> SilentWorkerAutoKickstartPoller {
        SilentWorkerAutoKickstartPoller(
            dateProvider: dateProvider,
            kickstartExecutor: kickstartExecutor,
            logger: ContextualLogger(logger: Logging.Logger(label: "test", factory: { [logHandler] _ in logHandler }), addedMetadata: [:]),
            onDemandWorkerStarter: starter,
            settings: settings,
            workerAlivenessProvider: workerAlivenessProvider,
            workerIds: [worker1, worker2]
        )
    }

    private func makeSilent(_ workerId: WorkerId) {
        workerAlivenessProvider.didRegisterWorker(workerId: workerId)
        workerAlivenessProvider.setWorkerIsSilent(workerId: workerId)
    }

    private func markAlive(_ workerId: WorkerId) {
        workerAlivenessProvider.set(bucketIdsBeingProcessed: [], workerId: workerId)
    }

    private func logMessages(containing text: String) -> [String] {
        logHandler.logCalls.map { $0.message }.filter { $0.contains(text) }
    }

    private func advance(by interval: TimeInterval) {
        dateProvider.result = dateProvider.result.addingTimeInterval(interval)
    }
}

private final class RecordingOnDemandWorkerStarter: OnDemandWorkerStarter {
    var startedWorkerIds = [WorkerId]()
    var error: Error?

    func start(workerId: WorkerId) throws {
        startedWorkerIds.append(workerId)
        if let error = error {
            throw error
        }
    }
}

private struct TestError: Error, CustomStringConvertible {
    var description: String { "test error" }
}
