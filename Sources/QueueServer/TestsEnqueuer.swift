import BalancingBucketQueue
import CommonTestModels
import DateProvider
import Foundation
import EmceeLogging
import MetricsRecording
import MetricsExtensions
import QueueModels
import ScheduleStrategy

public final class TestsEnqueuer {
    private let bucketGenerator: BucketGenerator
    private let bucketSplitInfo: BucketSplitInfo
    private let dateProvider: DateProvider
    private let enqueueableBucketReceptor: EnqueueableBucketReceptor
    private let hostname: String
    private let logger: ContextualLogger
    private let version: Version
    private let specificMetricRecorderProvider: SpecificMetricRecorderProvider

    public init(
        bucketGenerator: BucketGenerator,
        bucketSplitInfo: BucketSplitInfo,
        dateProvider: DateProvider,
        enqueueableBucketReceptor: EnqueueableBucketReceptor,
        hostname: String,
        logger: ContextualLogger,
        version: Version,
        specificMetricRecorderProvider: SpecificMetricRecorderProvider
    ) {
        self.bucketGenerator = bucketGenerator
        self.bucketSplitInfo = bucketSplitInfo
        self.dateProvider = dateProvider
        self.enqueueableBucketReceptor = enqueueableBucketReceptor
        self.logger = logger
        self.hostname = hostname
        self.version = version
        self.specificMetricRecorderProvider = specificMetricRecorderProvider
    }
    
    public func enqueue(
        configuredTestEntries: [ConfiguredTestEntry],
        testSplitter: TestSplitter,
        prioritizedJob: PrioritizedJob
    ) throws {
        let buckets = bucketGenerator.generateBuckets(
            configuredTestEntries: configuredTestEntries,
            splitInfo: bucketSplitInfo,
            testSplitter: testSplitter
        )
        try enqueueableBucketReceptor.enqueue(buckets: buckets, prioritizedJob: prioritizedJob)
        
        try specificMetricRecorderProvider.specificMetricRecorder(
            analyticsConfiguration: prioritizedJob.analyticsConfiguration
        ).capture(
            EnqueueTestsMetric(
                version: version,
                queueHost: hostname,
                numberOfTests: configuredTestEntries.count,
                timestamp: dateProvider.currentDate()
            ),
            EnqueueBucketsMetric(
                version: version,
                queueHost: hostname,
                numberOfBuckets: buckets.count,
                timestamp: dateProvider.currentDate()
            )
        )
        
        logger.trace("Enqueued \(buckets.count) buckets for job '\(prioritizedJob)'")
        for bucket in buckets {
            logger.trace("-- \(bucket.bucketId) with payload \(bucket.payloadContainer)")
        }
    }
}
