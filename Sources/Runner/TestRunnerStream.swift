import Foundation
import RunnerModels

public protocol TestRunnerStream {
    func openStream()
    func testStarted(testName: TestName)
    func caughtException(testException: TestException)
    func logCaptured(entry: TestLogEntry)
    func testStopped(testStoppedEvent: TestStoppedEvent)
    func closeStream()

    /// Reading of the runner's result stream has ended while the runner process may still
    /// be alive (e.g. stream parse failure). No further events can arrive; event-based
    /// silence watchdogs must stand down — file-based progress guarding takes over.
    func streamReadingAborted()
}

public extension TestRunnerStream {
    func streamReadingAborted() {}
}
