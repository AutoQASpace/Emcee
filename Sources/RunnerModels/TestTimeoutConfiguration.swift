import Foundation

public struct TestTimeoutConfiguration: Codable, Hashable {
    /** A maximum duration for a single test. */
    public let singleTestMaximumDuration: TimeInterval

    /** A maximum allowed duration for a test runner stdout/stderr to be silent. */
    public let testRunnerMaximumSilenceDuration: TimeInterval

    /// Absolute upper bound for waiting for the test runner host process to exit after its
    /// result stream reading has ended. Safety net against a process that keeps showing
    /// file activity forever. Must not undercut the silence criterion (clamped at use site).
    public let bucketShutdownHardCap: TimeInterval

    public static let defaultBucketShutdownHardCap: TimeInterval = 1800

    public init(
        singleTestMaximumDuration: TimeInterval,
        testRunnerMaximumSilenceDuration: TimeInterval,
        bucketShutdownHardCap: TimeInterval = TestTimeoutConfiguration.defaultBucketShutdownHardCap
    ) {
        self.singleTestMaximumDuration = singleTestMaximumDuration
        self.testRunnerMaximumSilenceDuration = testRunnerMaximumSilenceDuration
        self.bucketShutdownHardCap = bucketShutdownHardCap
    }

    enum CodingKeys: String, CodingKey {
        case singleTestMaximumDuration
        case testRunnerMaximumSilenceDuration
        case bucketShutdownHardCap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        singleTestMaximumDuration = try container.decode(TimeInterval.self, forKey: .singleTestMaximumDuration)
        testRunnerMaximumSilenceDuration = try container.decode(TimeInterval.self, forKey: .testRunnerMaximumSilenceDuration)
        bucketShutdownHardCap = try container.decodeIfPresent(TimeInterval.self, forKey: .bucketShutdownHardCap)
            ?? TestTimeoutConfiguration.defaultBucketShutdownHardCap
    }
}
