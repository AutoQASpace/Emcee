import AutomaticTermination
import DateProviderTestHelpers
import DistWorkerModels
import DistWorkerModelsTestHelpers
import Foundation
import MetricsExtensions
import MetricsTestHelpers
import PortDeterminer
import QueueCommunicationTestHelpers
import QueueModels
import QueueServer
import QueueServerTestHelpers
import RequestSender
import ScheduleStrategy
import UniqueIdentifierGeneratorTestHelpers
import WorkerAlivenessProvider
import WorkerCapabilities
import XCTest

final class QueueServerAutoKickstartTests: XCTestCase {
    private let workerId: WorkerId = "workerId"

    func test___enabled_auto_kickstart___running_queue_ticks_with_configured_interval() throws {
        // Первый тик таймер делает сразу при старте; второй kickstart возможен только на следующем тике.
        let kickstarted = expectation(description: "\(workerId) kickstarted on two ticks")
        kickstarted.expectedFulfillmentCount = 2
        let server = createServer(
            settings: SilentWorkerAutoKickstartSettings(silenceThreshold: 0, maxAttemptsPerWorker: 2, cooldown: 0, pollInterval: 0.1),
            starter: CallbackOnDemandWorkerStarter { [workerId] startedWorkerId in
                XCTAssertEqual(startedWorkerId, workerId)
                kickstarted.fulfill()
            }
        )

        _ = try server.start()

        wait(for: [kickstarted], timeout: 5)
    }

    private func createServer(
        settings: SilentWorkerAutoKickstartSettings?,
        starter: OnDemandWorkerStarter
    ) -> QueueServerImpl {
        let workerConfigurations = FixedWorkerConfigurations()
        workerConfigurations.add(workerId: workerId, configuration: WorkerConfigurationFixtures.workerConfiguration)
        return QueueServerImpl(
            automaticTerminationController: AutomaticTerminationControllerFactory(
                automaticTerminationPolicy: .stayAlive
            ).createAutomaticTerminationController(),
            autoupdatingWorkerPermissionProvider: FakeAutoupdatingWorkerPermissionProvider(),
            bucketGenerator: BucketGeneratorImpl(uniqueIdentifierGenerator: FixedValueUniqueIdentifierGenerator()),
            bucketSplitInfo: BucketSplitInfo(numberOfWorkers: 1, numberOfParallelBuckets: 1),
            checkAgainTimeInterval: .infinity,
            dateProvider: DateProviderFixture(),
            emceeVersion: "emceeVersion",
            localPortDeterminer: LocalPortDeterminer(logger: .noOp, portRange: 49152...65535),
            logger: .noOp,
            globalMetricRecorder: GlobalMetricRecorderImpl(),
            specificMetricRecorderProvider: NoOpSpecificMetricRecorderProvider(),
            onDemandWorkerStarter: starter,
            payloadSignature: PayloadSignature(value: "payloadSignature"),
            queueServerLock: NeverLockableQueueServerLock(),
            requestSenderProvider: DefaultRequestSenderProvider(logger: .noOp),
            uniqueIdentifierGenerator: FixedValueUniqueIdentifierGenerator(),
            workerAlivenessProvider: WorkerAlivenessProviderImpl(
                logger: .noOp,
                workerPermissionProvider: FakeWorkerPermissionProvider()
            ),
            workerCapabilitiesStorage: WorkerCapabilitiesStorageImpl(),
            workerConfigurations: workerConfigurations,
            workerIds: [workerId],
            workersToUtilizeService: FakeWorkersToUtilizeService(),
            useOnlyIPv4: false,
            silentWorkerAutoKickstartSettings: settings
        )
    }
}

private final class CallbackOnDemandWorkerStarter: OnDemandWorkerStarter {
    private let onStart: (WorkerId) -> Void

    init(onStart: @escaping (WorkerId) -> Void) {
        self.onStart = onStart
    }

    func start(workerId: WorkerId) throws {
        onStart(workerId)
    }
}
