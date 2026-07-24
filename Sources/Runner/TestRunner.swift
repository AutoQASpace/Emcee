import BuildArtifacts
import DeveloperDirLocator
import Foundation
import EmceeLogging
import ProcessController
import RunnerModels
import SimulatorPoolModels
import Tmp
import PathLib

public protocol TestRunnerRunningInvocation {
    var pidInfo: PidInfo { get }
    func cancel()
    func wait()

    /// Cleanup for the normal end-of-bucket path: the host process is already dead by now,
    /// only auxiliary cleanup (in-simulator apps) must happen here. No killing.
    func performPostRunCleanup()
}

public extension TestRunnerRunningInvocation {
    func performPostRunCleanup() {}
}

public protocol TestRunnerInvocation {
    func startExecutingTests() throws -> TestRunnerRunningInvocation
}

public protocol TestRunner {
    func additionalEnvironment(
        testRunnerWorkingDirectory: AbsolutePath
    ) -> [String: String]
    
    func prepareTestRun(
        buildArtifacts: IosBuildArtifacts,
        developerDirLocator: DeveloperDirLocator,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        testContext: TestContext,
        testRunnerStream: TestRunnerStream,
        testTimeoutConfiguration: TestTimeoutConfiguration
    ) throws -> TestRunnerInvocation
}
