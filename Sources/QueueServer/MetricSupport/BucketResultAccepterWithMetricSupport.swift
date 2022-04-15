import BalancingBucketQueue
import BucketQueue
import BucketQueueModels
import CommonTestModels
import DateProvider
import Foundation
import Graphite
import EmceeLogging
import MetricsRecording
import MetricsExtensions
import QueueModels

public class BucketResultAcceptorWithMetricSupport: BucketResultAcceptor {
    private let bucketResultAcceptor: BucketResultAcceptor
    private let dateProvider: DateProvider
    private let jobStateProvider: JobStateProvider
    private let hostname: String
    private let logger: ContextualLogger
    private let specificMetricRecorderProvider: SpecificMetricRecorderProvider
    private let statefulBucketQueue: StatefulBucketQueue
    private let version: Version

    public init(
        bucketResultAcceptor: BucketResultAcceptor,
        dateProvider: DateProvider,
        jobStateProvider: JobStateProvider,
        hostname: String,
        logger: ContextualLogger,
        specificMetricRecorderProvider: SpecificMetricRecorderProvider,
        statefulBucketQueue: StatefulBucketQueue,
        version: Version
    ) {
        self.bucketResultAcceptor = bucketResultAcceptor
        self.dateProvider = dateProvider
        self.jobStateProvider = jobStateProvider
        self.hostname = hostname
        self.logger = logger
        self.specificMetricRecorderProvider = specificMetricRecorderProvider
        self.statefulBucketQueue = statefulBucketQueue
        self.version = version
    }
    
    public func accept(
        bucketId: BucketId,
        bucketResult: BucketResult,
        workerId: WorkerId
    ) throws -> BucketQueueAcceptResult {
        let acceptResult = try bucketResultAcceptor.accept(
            bucketId: bucketId,
            bucketResult: bucketResult,
            workerId: workerId
        )
        
        sendMetrics(acceptResult: acceptResult)
        
        return acceptResult
    }
    
    private func sendMetrics(
        acceptResult: BucketQueueAcceptResult
    ) {
        let jobStates = jobStateProvider.allJobStates
        let queueStateMetricGatherer = QueueStateMetricGatherer(
            dateProvider: dateProvider,
            queueHost: hostname,
            version: version
        )
        
        let queueStateMetrics = queueStateMetricGatherer.metrics(
            jobStates: jobStates,
            runningQueueState: statefulBucketQueue.runningQueueState
        )
        
        let bucketResultMetrics: [GraphiteMetric]
        
        switch acceptResult.bucketResultToCollect {
        case .testingResult(let testingResult):
            bucketResultMetrics = testingResultMetrics(
                testingResult: testingResult,
                dequeuedBucket: acceptResult.dequeuedBucket
            )
        }
        
        do {
            let specificMetricRecorder = try specificMetricRecorderProvider.specificMetricRecorder(
                analyticsConfiguration: acceptResult.dequeuedBucket.enqueuedBucket.bucket.analyticsConfiguration
            )
            specificMetricRecorder.capture(bucketResultMetrics + queueStateMetrics)
            if let persistentMetricsJobId = acceptResult.dequeuedBucket.enqueuedBucket.bucket.analyticsConfiguration.persistentMetricsJobId {
                specificMetricRecorder.capture(
                    BucketProcessingDurationMetric(
                        queueHost: hostname,
                        version: version,
                        persistentMetricsJobId: persistentMetricsJobId,
                        duration: dateProvider.currentDate().timeIntervalSince(acceptResult.dequeuedBucket.enqueuedBucket.enqueueTimestamp)
                    )
                )

            }
        } catch {
            logger.error("Failed to send metrics: \(error)")
        }
    }
    
    private func testingResultMetrics(
        testingResult: TestingResult,
        dequeuedBucket: DequeuedBucket
    ) -> [GraphiteMetric] {
        let testTimeToStartMetrics: [TimeToStartTestMetric] = testingResult.unfilteredResults.flatMap { testEntryResult -> [TimeToStartTestMetric] in
            testEntryResult.testRunResults.map { testRunResult in
                let timeToStart = testRunResult.startTime.date.timeIntervalSince(dequeuedBucket.enqueuedBucket.enqueueTimestamp)
                return TimeToStartTestMetric(
                    testEntry: testEntryResult.testEntry,
                    version: version,
                    queueHost: hostname,
                    timeToStartTest: timeToStart,
                    timestamp: dateProvider.currentDate()
                )
            }
        }
        return testTimeToStartMetrics
    }
}
