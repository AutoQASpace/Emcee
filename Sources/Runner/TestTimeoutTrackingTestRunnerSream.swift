import AtomicModels
import DateProvider
import Foundation
import EmceeLogging
import EmceeTypes
import RunnerModels
import Timer

public final class TestTimeoutTrackingTestRunnerSream: TestRunnerStream {
    struct LastStartedTestInfo {
        let testName: TestName
        let testStartedAt: DateSince1970ReferenceDate
    }

    private let dateProvider: DateProvider
    private let detectedLongRunningTest: (TestName, DateSince1970ReferenceDate) -> ()
    private let detectedStuckTest: (TestName) -> ()
    private let lastStartedTestInfo = AtomicValue<LastStartedTestInfo?>(nil)
    private let longRunningTestReported = AtomicValue<Bool>(false)
    private let logger: () -> ContextualLogger
    private let maximumTestDuration: TimeInterval
    private let stuckTestGracePeriod: TimeInterval
    private let pollPeriod: DispatchTimeInterval
    private var testHangTrackingTimer: DispatchBasedTimer?

    /// How long past `maximumTestDuration` a test may keep running before the stuck-test
    /// fallback fires. Must exceed the native XCTest allowance headroom: the allowance equals
    /// `maximumTestDuration` rounded UP to a full minute (≤ +59 sec), so 120 sec guarantees
    /// the native timeout (readable verdict, bucket continues) always gets the first shot,
    /// and the fallback only ever fires when the native mechanism is dead or disabled.
    public static let defaultStuckTestGracePeriod: TimeInterval = 120

    public init(
        dateProvider: DateProvider,
        detectedLongRunningTest: @escaping (TestName, DateSince1970ReferenceDate) -> (),
        detectedStuckTest: @escaping (TestName) -> (),
        logger: @escaping () -> ContextualLogger,
        maximumTestDuration: TimeInterval,
        stuckTestGracePeriod: TimeInterval = TestTimeoutTrackingTestRunnerSream.defaultStuckTestGracePeriod,
        pollPeriod: DispatchTimeInterval
    ) {
        self.dateProvider = dateProvider
        self.detectedLongRunningTest = detectedLongRunningTest
        self.detectedStuckTest = detectedStuckTest
        self.logger = logger
        self.maximumTestDuration = maximumTestDuration
        self.stuckTestGracePeriod = stuckTestGracePeriod
        self.pollPeriod = pollPeriod
    }

    public func openStream() {}

    public func testStarted(testName: TestName) {
        startMonitoringForHangs(testName: testName)
    }

    public func caughtException(testException: TestException) {}

    public func logCaptured(entry: TestLogEntry) {}

    public func testStopped(testStoppedEvent: TestStoppedEvent) {
        stopMonitoringForHangs(testStoppedEvent: testStoppedEvent)
    }

    public func closeStream() {
        stopTimer()
    }

    private func startMonitoringForHangs(testName: TestName) {
        lastStartedTestInfo.set(
            LastStartedTestInfo(testName: testName, testStartedAt: dateProvider.dateSince1970ReferenceDate())
        )
        longRunningTestReported.set(false)

        testHangTrackingTimer = DispatchBasedTimer.startedTimer(repeating: pollPeriod, leeway: pollPeriod) { [weak self] timer in
            guard let strongSelf = self else { return timer.stop() }
            guard let lastStartedTestInfo = strongSelf.lastStartedTestInfo.currentValue() else { return timer.stop() }

            let elapsed = strongSelf.dateProvider.currentDate().timeIntervalSince(lastStartedTestInfo.testStartedAt.date)
            if elapsed > strongSelf.maximumTestDuration, !strongSelf.longRunningTestReported.currentValue() {
                strongSelf.longRunningTestReported.set(true)
                strongSelf.didDetectLongRunningTest(lastStartedTestInfo: lastStartedTestInfo)
            }
            if elapsed > strongSelf.maximumTestDuration + strongSelf.stuckTestGracePeriod {
                strongSelf.didDetectStuckTest(lastStartedTestInfo: lastStartedTestInfo)
                timer.stop()
            }
        }

        logger().debug("Started monitoring duration of test \(testName)")
    }

    private func stopMonitoringForHangs(testStoppedEvent: TestStoppedEvent) {
        stopTimer()
        logger().debug("Stopped monitoring duration of test \(testStoppedEvent.testName), test finished with result \(testStoppedEvent.result)")
    }

    private func didDetectLongRunningTest(lastStartedTestInfo: LastStartedTestInfo) {
        logger().warning("Detected a long running test: \(lastStartedTestInfo.testName) was running for more than \(LoggableDuration(maximumTestDuration)), test started at: \(LoggableDate(lastStartedTestInfo.testStartedAt.date))")

        detectedLongRunningTest(lastStartedTestInfo.testName, lastStartedTestInfo.testStartedAt)
    }

    private func didDetectStuckTest(lastStartedTestInfo: LastStartedTestInfo) {
        logger().warning("Test \(lastStartedTestInfo.testName) is still running \(LoggableDuration(stuckTestGracePeriod)) past its maximum duration \(LoggableDuration(maximumTestDuration)) — native test timeout did not take effect")

        detectedStuckTest(lastStartedTestInfo.testName)
    }

    private func stopTimer() {
        lastStartedTestInfo.set(nil)
        testHangTrackingTimer?.stop()
        testHangTrackingTimer = nil
    }
}
