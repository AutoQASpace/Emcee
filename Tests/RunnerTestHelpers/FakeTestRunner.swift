import BuildArtifacts
import CommonTestModels
import DeveloperDirLocator
import EmceeLogging
import Foundation
import MetricsExtensions
import Runner
import RunnerModels
import PathLib

public final class FakeTestRunner: TestRunner {
    public var entriesToRun: [TestEntry]?
    public var errorToThrowOnRun: Error?
    public var testContext: AppleTestContext?
    
    public struct SomeError: Error, CustomStringConvertible {
        public let description = "some error happened"
        public init() {}
    }
    
    public init() {}

    // Configuration

    public static func testStartedHandlerForNormalEventStreaming() -> (TestName, TestRunnerStream) -> () {
        return { testName, testRunnerStream in
            testRunnerStream.testStarted(testName: testName)
        }
    }

    public static func testStoppedHandlerForNormalEventStreaming() -> (TestStoppedEvent, TestRunnerStream) -> () {
        return { testStoppedEvent, testRunnerStream in
            testRunnerStream.testStopped(
                testStoppedEvent: testStoppedEvent
            )
        }
    }
    
    public var onStreamOpen: (TestRunnerStream) -> () = {
        $0.openStream()
    }

    public var onTestStarted: (TestName, TestRunnerStream) -> () =
        FakeTestRunner.testStartedHandlerForNormalEventStreaming()

    public var onExecuteTest: (TestName) -> TestStoppedEvent.Result = { _ in .success }

    public var onTestStopped: (TestStoppedEvent, TestRunnerStream) -> () =
        FakeTestRunner.testStoppedHandlerForNormalEventStreaming()
    
    public var onStreamClose: (TestRunnerStream) -> () = {
        $0.closeStream()
    }

    public func disableTestStartedTestRunnerStreamEvents() {
        onTestStarted = { _, _ in }
    }

    public func disableTestStoppedTestRunnerStreamEvents() {
        onTestStopped = { _, _ in }
    }
    
    public func makeRunThrowErrors() {
        errorToThrowOnRun = SomeError()
    }

    // - TestRunner Protocol
    public var isRunCalled = false
    
    public func prepareTestRun(
        buildArtifacts: AppleBuildArtifacts,
        developerDirLocator: DeveloperDirLocator,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        specificMetricRecorder: SpecificMetricRecorder,
        testContext: AppleTestContext,
        testRunnerStream: TestRunnerStream,
        zippedResultBundleOutputPath: AbsolutePath?
    ) throws -> TestRunnerInvocation {
        isRunCalled = true

        self.entriesToRun = entriesToRun
        self.testContext = testContext
        
        if let errorToThrowOnRun = errorToThrowOnRun {
            throw errorToThrowOnRun
        }
        
        return FakeTestRunnerInvocation(
            entriesToRun: entriesToRun,
            testRunnerStream: testRunnerStream,
            testResultProvider: onExecuteTest,
            onStreamOpen: onStreamOpen,
            onTestStarted: onTestStarted,
            onTestStopped: onTestStopped,
            onStreamClose: onStreamClose
        )
    }
    
    public var isAdditionalEnvironmentCalled = false
    public var additionalEnvironmentReturns: [String: String] = [:]
    
    public func additionalEnvironment(testRunnerWorkingDirectory: TestRunnerWorkingDirectory) -> [String : String] {
        isAdditionalEnvironmentCalled = true
        return additionalEnvironmentReturns
    }
}
