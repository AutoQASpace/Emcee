import Foundation
import EmceeLogging
import ProcessController

public class ProcessControllerWrappingTestRunnerInvocation: TestRunnerInvocation, TestRunnerRunningInvocation {
    
    private let processController: ProcessController
    private let onCancel: () -> ()

    public init(
        processController: ProcessController,
        onCancel: @escaping () -> () = {}
    ) {
        self.processController = processController
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
        processController.terminateAndForceKillIfNeeded()
        onCancel()
    }
    
    public var pidInfo: PidInfo {
        PidInfo(pid: processController.processId, name: processController.processName)
    }
    
    public func wait() {
        processController.waitForProcessToDie()
    }
}
