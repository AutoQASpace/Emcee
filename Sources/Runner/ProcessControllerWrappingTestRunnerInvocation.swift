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
        // Сначала убиваем host-процесс xcodebuild/xcrun, затем выполняем
        // переданную доочистку (терминирование приложений внутри симулятора).
        // Без этого зависший процесс/приложение переживает освобождение сима
        // и конкурирует со следующим bucket'ом на том же симуляторе.
        //
        // Диагностика: явно логируем pid убиваемого host-процесса до и после kill.
        // `terminateAndForceKillIfNeeded()` шлёт сигнал по process group (`kill(-pid)`),
        // поэтому в посмертном разборе этот лог позволяет сверить убиваемый pid с pid
        // воркера и доказательно исключить, что наш kill задевает сам процесс воркера.
        let pid = processController.processId
        let name = processController.processName
        logger.debug("cancel(): force-killing test runner host process group (pid \(pid), name '\(name)')")
        processController.terminateAndForceKillIfNeeded()
        logger.debug("cancel(): host process pid \(pid) ('\(name)') force-killed; starting in-simulator app cleanup")
        onCancel()
        logger.debug("cancel(): in-simulator app cleanup finished for host pid \(pid) ('\(name)')")
    }
    
    public var pidInfo: PidInfo {
        PidInfo(pid: processController.processId, name: processController.processName)
    }
    
    public func wait() {
        processController.waitForProcessToDie()
    }
}
