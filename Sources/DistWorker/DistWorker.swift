import AtomicModels
import AutomaticTermination
import EmceeDI
import DateProvider
import DeveloperDirLocator
import Dispatch
import DistWorkerModels
import EmceeLogging
import EventBus
import FileSystem
import Foundation
import LocalHostDeterminer
import LogStreaming
import Metrics
import MetricsExtensions
import PathLib
import PluginManager
import QueueClient
import QueueModels
import RESTMethods
import RESTServer
import RequestSender
import ResourceLocationResolver
import Runner
import RunnerModels
import Scheduler
import SimulatorPool
import SocketModels
import SynchronousWaiter
import Tmp
import Timer
import Types
import UniqueIdentifierGenerator
import WorkerCapabilities

public final class DistWorker: SchedulerDataSource, SchedulerDelegate {
    private let di: DI
    private let callbackQueue = DispatchQueue(
        label: "DistWorker.callbackQueue",
        qos: .default,
        attributes: .concurrent,
        target: .global()
    )
    private let currentlyBeingProcessedBucketsTracker = DefaultCurrentlyBeingProcessedBucketsTracker()
    private let dateProvider: DateProvider
    private let fileSystem: FileSystem
    private let httpRestServer: HTTPRESTServer
    private let logEntrySender: LogEntrySender
    private let resourceLocationResolver: ResourceLocationResolver
    private let tempFolder: TemporaryFolder
    private let version: Version
    private let workerId: WorkerId
    private let logger: ContextualLogger
    private var payloadSignature = Either<PayloadSignature, DistWorkerError>.error(DistWorkerError.missingPayloadSignature)
    
    private enum ReducedBucketFetchResult: Equatable {
        case result(SchedulerBucket?)
        case checkAgain(after: TimeInterval)
    }
    
    public init(
        di: DI,
        logEntrySender: LogEntrySender,
        resourceLocationResolver: ResourceLocationResolver,
        tempFolder: TemporaryFolder,
        version: Version,
        workerId: WorkerId
    ) throws {
        self.di = di
        self.dateProvider = try di.get()
        self.fileSystem = try di.get()
        self.logEntrySender = logEntrySender
        self.logger = try di.get(ContextualLogger.self)
        self.httpRestServer = HTTPRESTServer(
            automaticTerminationController: StayAliveTerminationController(),
            logger: logger,
            portProvider: AnyAvailablePortProvider(),
            useOnlyIPv4: false
        )
        self.resourceLocationResolver = resourceLocationResolver
        self.tempFolder = tempFolder
        self.version = version
        self.workerId = workerId
    }
    
    public func start(
        completion: @escaping () -> ()
    ) throws {
        httpRestServer.add(
            handler: RESTEndpointOf(
                CurrentlyProcessingBucketsEndpoint(
                    currentlyBeingProcessedBucketsTracker: currentlyBeingProcessedBucketsTracker,
                    logger: logger
                )
            )
        )

        try di.get(WorkerRegisterer.self).registerWithServer(
            workerId: workerId,
            workerCapabilities: try di.get(WorkerCapabilitiesProvider.self).workerCapabilities(),
            workerRestAddress: SocketAddress(
                host: LocalHostDeterminer.currentHostAddress,
                port: try httpRestServer.start()
            ),
            callbackQueue: callbackQueue
        ) { [weak self] result in
            defer {
                completion()
            }
            guard let strongSelf = self else { return }
            do {
                let workerConfiguration = try result.dematerialize()
                
                try strongSelf.di.get(GlobalMetricRecorder.self).set(
                    analyticsConfiguration: workerConfiguration.globalAnalyticsConfiguration
                )
                if let kibanaConfiguration = workerConfiguration.globalAnalyticsConfiguration.kibanaConfiguration {
                    try strongSelf.di.get(LoggingSetup.self).set(kibanaConfiguration: kibanaConfiguration)
                }
                
                strongSelf.payloadSignature = .success(workerConfiguration.payloadSignature)
                strongSelf.logger.trace("Registered with server. Worker configuration: \(workerConfiguration)")
                
                try strongSelf.di.get(LoggingSetup.self).add(
                    loggerHandler: SendLogsToQueueLoggerHandler(
                        logEntrySender: strongSelf.logEntrySender,
                        logger: strongSelf.logger1
                    )
                )

                _ = try strongSelf.runTests(
                    workerConfiguration: workerConfiguration
                )
                strongSelf.logger.trace("Dist worker has finished")
            } catch {
                strongSelf.logger.error("Caught unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Private Stuff
    
    private func runTests(
        workerConfiguration: WorkerConfiguration
    ) throws {
        let scheduler = Scheduler(
            di: di,
            dateProvider: dateProvider,
            fileSystem: fileSystem,
            logger: logger,
            resourceLocationResolver: resourceLocationResolver,
            schedulerDataSource: self,
            schedulerDelegate: self,
            tempFolder: tempFolder,
            version: version,
            workerConfiguration: workerConfiguration
        )
        try scheduler.run()
    }
    
    // MARK: - Callbacks
    
    private func nextBucketFetchResult() throws -> ReducedBucketFetchResult {
        return try currentlyBeingProcessedBucketsTracker.perform { tracker -> ReducedBucketFetchResult in
            let callbackWaiter: CallbackWaiter<Either<BucketFetchResult, Error>> = try di.get(Waiter.self).createCallbackWaiter()
            
            try di.get(BucketFetcher.self).fetch(
                payloadSignature: try payloadSignature.dematerialize(),
                workerCapabilities: try di.get(WorkerCapabilitiesProvider.self).workerCapabilities(),
                workerId: workerId,
                callbackQueue: callbackQueue
            ) { response in callbackWaiter.set(result: response) }
            
            let result = try callbackWaiter.wait(timeout: .infinity, description: "Fetch next bucket").dematerialize()

            switch result {
            case .checkLater(let after):
                logger.trace("Server asked to fetch again after \(after) seconds")
                return .checkAgain(after: after)
            case .bucket(let fetchedBucket):
                logger.trace("Received \(fetchedBucket.bucketId)")
                tracker.willProcess(bucketId: fetchedBucket.bucketId)
                return .result(
                    SchedulerBucket(
                        analyticsConfiguration: fetchedBucket.analyticsConfiguration,
                        bucketId: fetchedBucket.bucketId,
                        bucketPayloadContainer: fetchedBucket.payloadContainer
                    )
                )
            }
        }
    }
    
    public func nextBucket() -> SchedulerBucket? {
        while true {
            do {
                let fetchResult = try nextBucketFetchResult()
                switch fetchResult {
                case .result(let result):
                    return result
                case .checkAgain(let after):
                    try di.get(Waiter.self).wait(
                        pollPeriod: 1.0,
                        timeout: after,
                        description: "Pause before fetching bucket"
                    )
                }
            } catch {
                logger.error("Failed to fetch next bucket: \(error)")
                return nil
            }
        }
    }
    
    public func scheduler(
        _ sender: Scheduler,
        obtainedBucketResult bucketResult: BucketResult,
        forBucket bucket: SchedulerBucket
    ) {
        logger.trace("Obtained result for bucket \(bucket.bucketId): \(bucketResult)")
        didReceive(bucketResult: bucketResult, bucketId: bucket.bucketId)
    }
    
    private func didReceive(
        bucketResult: BucketResult,
        bucketId: BucketId
    ) {
        do {
            try di.get(BucketResultSender.self).send(
                bucketId: bucketId,
                bucketResult: bucketResult,
                workerId: workerId,
                payloadSignature: try payloadSignature.dematerialize(),
                callbackQueue: callbackQueue,
                completion: { [currentlyBeingProcessedBucketsTracker, logger] (result: Either<BucketId, Error>) in
                    defer {
                        currentlyBeingProcessedBucketsTracker.didProcess(bucketId: bucketId)
                    }
                    
                    do {
                        let acceptedBucketId = try result.dematerialize()
                        guard bucketId == acceptedBucketId else {
                            throw DistWorkerError.unexpectedAcceptedBucketId(
                                actual: acceptedBucketId,
                                expected: bucketId
                            )
                        }
                        logger.trace("Successfully sent test run result for bucket \(bucketId)")
                    } catch {
                        logger.error("Server response for results of bucket \(bucketId) has error: \(error)")
                    }
                }
            )
        } catch {
            logger.error("Failed to send test run result for bucket \(bucketId): \(error)")
        }
    }
}
