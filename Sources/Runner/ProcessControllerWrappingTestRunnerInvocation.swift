import Foundation
import EmceeLogging
import ProcessController

public class ProcessControllerWrappingTestRunnerInvocation: TestRunnerInvocation, TestRunnerRunningInvocation {
    
    private let processController: ProcessController
    private let onCancel: () -> ()
    private let logger: ContextualLogger

    public init(
        processController: ProcessController,
        logger: ContextualLogger,
        onCancel: @escaping () -> () = {}
    ) {
        self.processController = processController
        self.logger = logger
        self.onCancel = onCancel
    }

    public func startExecutingTests() throws -> TestRunnerRunningInvocation {
        try processController.start()
        return self
    }

    public func cancel() {
        // Аварийное завершение (таймауты тишины/длинного теста): убиваем host-процесс
        // сигналом напрямую по pid (см. CLT DefaultProcessController.send(signal:)),
        // затем зачищаем приложения внутри симулятора.
        let pid = processController.processId
        let name = processController.processName
        logger.debug("cancel(): killing test runner host process (pid \(pid), name '\(name)')")
        processController.terminateAndForceKillIfNeeded()
        logger.debug("cancel(): host process pid \(pid) ('\(name)') killed; starting in-simulator app cleanup")
        onCancel()
        logger.debug("cancel(): in-simulator app cleanup finished for host pid \(pid) ('\(name)')")
    }

    public func performPostRunCleanup() {
        let pid = processController.processId
        logger.debug("postRunCleanup(): host process pid \(pid) already exited; running in-simulator app cleanup")
        onCancel()
        logger.debug("postRunCleanup(): in-simulator app cleanup finished for host pid \(pid)")
    }

    public var pidInfo: PidInfo {
        PidInfo(pid: processController.processId, name: processController.processName)
    }

    public func wait() {
        processController.waitForProcessToDie()
    }
}
