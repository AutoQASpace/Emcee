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
import LoggingSetup
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
        resourceLocationResolver: ResourceLocationResolver,
        tempFolder: TemporaryFolder,
        version: Version,
        workerId: WorkerId
    ) throws {
        self.di = di
        self.dateProvider = try di.get()
        self.fileSystem = try di.get()
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
                
                if let globalAnalyticsConfiguration = workerConfiguration.globalAnalyticsConfiguration {
                    try strongSelf.di.get(GlobalMetricRecorder.self).set(
                        analyticsConfiguration: globalAnalyticsConfiguration
                    )
                    if let kibanaConfiguration = globalAnalyticsConfiguration.kibanaConfiguration {
                        try strongSelf.di.get(LoggingSetup.self).set(kibanaConfiguration: kibanaConfiguration)
                    }
                }
                
                strongSelf.payloadSignature = .success(workerConfiguration.payloadSignature)
                strongSelf.logger.debug("Registered with server. Worker configuration: \(workerConfiguration)")
                
                _ = try strongSelf.runTests(
                    workerConfiguration: workerConfiguration
                )
                strongSelf.logger.debug("Dist worker has finished")
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
                logger.debug("Server asked to wait for \(after) seconds and fetch next bucket again")
                return .checkAgain(after: after)
            case .bucket(let fetchedBucket):
                logger.debug("Received \(fetchedBucket.bucketId)")
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
    
    /// Сколько раз повторяем запрос бакета при транзиентных сетевых сбоях, прежде чем
    /// свернуть дорожку. Суммарный бэкофф (~1 мин) переживает короткие сетевые моргалки
    /// queue↔worker, но не висит вечно, если queue реально мёртв.
    private static let maxTransientFetchRetries = 5

    private static let transientURLErrorCodes: Set<Int> = [
        NSURLErrorNetworkConnectionLost,   // -1005 — наблюдалось в проде
        NSURLErrorTimedOut,                // -1001
        NSURLErrorCannotConnectToHost,     // -1004
        NSURLErrorNotConnectedToInternet,  // -1009
        NSURLErrorDNSLookupFailed,         // -1006
        NSURLErrorCannotFindHost,          // -1003
        NSURLErrorResourceUnavailable,     // -1008
    ]

    public func nextBucket() -> SchedulerBucket? {
        var consecutiveTransientFailures = 0
        while true {
            do {
                logger.debug("Fetching next bucket from server", workerId: workerId)
                let fetchResult = try nextBucketFetchResult()
                consecutiveTransientFailures = 0
                switch fetchResult {
                case .result(let result):
                    return result
                case .checkAgain(let after):
                    try di.get(Waiter.self).wait(timeout: after, description: "Pause before checking queue server again")
                }
            } catch {
                // Транзиентный сетевой сбой fetch'а (потеря соединения/таймаут) НЕ означает,
                // что работа кончилась. Если вернуть здесь nil, Scheduler.fetchAndRunBucket
                // трактует его как штатное завершение и НЕ перезапускает дорожку — воркер
                // безвозвратно теряет один симуляторный слот из N и до конца прогона работает
                // на сниженной мощности. Поэтому на транзиентных ошибках повторяем запрос с
                // бэкоффом, не покидая дорожку; nil отдаём только при фатальной ошибке или
                // исчерпании лимита (реально недоступный queue / конец прогона).
                if Self.isTransientNetworkError(error), consecutiveTransientFailures < Self.maxTransientFetchRetries {
                    consecutiveTransientFailures += 1
                    let backoff = TimeInterval(min(30, 1 << consecutiveTransientFailures)) // 2,4,8,16,30 c
                    logger.warning("Transient network error fetching next bucket (attempt \(consecutiveTransientFailures)/\(Self.maxTransientFetchRetries)), retrying in \(backoff)s, keeping simulator slot alive: \(error)")
                    try? di.get(Waiter.self).wait(timeout: backoff, description: "Backoff before retrying bucket fetch after transient network error")
                    continue
                }
                // Дорожка сворачивается: фатальная ошибка / исчерпан лимит ретраев / queue
                // недоступен. Логируем явно — это момент выпадения симуляторного слота из пула
                // (после него Scheduler не перезапустит дорожку, мощность воркера снизится).
                logger.error("Giving up fetching next bucket after \(consecutiveTransientFailures) transient failure(s); simulator slot is leaving the pool (worker capacity reduced for the rest of the run): \(error)")
                return nil
            }
        }
    }

    /// true для временных сетевых сбоев, на которых имеет смысл повторить запрос бакета.
    /// Ошибка приходит обёрнутой в `RequestSenderError` (см. `RequestSenderImpl`), поэтому
    /// разворачиваем обёртку и проверяем доменный `NSURLError`.
    private static func isTransientNetworkError(_ error: Error) -> Bool {
        if let requestSenderError = error as? RequestSenderError {
            switch requestSenderError {
            case .communicationError(let underlying), .cannotIssueRequest(let underlying):
                return isTransientNetworkError(underlying)
            default:
                return false
            }
        }
        var nsError: NSError? = error as NSError
        var depth = 0
        while let current = nsError, depth < 6 {
            if current.domain == NSURLErrorDomain, transientURLErrorCodes.contains(current.code) {
                return true
            }
            nsError = current.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }
    
    public func scheduler(
        _ sender: Scheduler,
        obtainedBucketResult bucketResult: BucketResult,
        forBucket bucket: SchedulerBucket
    ) {
        logger.debug("Obtained result for bucket \(bucket.bucketId): \(bucketResult)")
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
                        logger.debug("Successfully sent test run result for bucket \(bucketId)")
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
