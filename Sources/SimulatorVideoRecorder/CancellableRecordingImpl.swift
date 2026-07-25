import Foundation
import EmceeLogging
import PathLib
import ProcessController

class CancellableRecordingImpl: CancellableRecording {
    private let outputPath: AbsolutePath
    private let recordingProcess: ProcessController

    public init(
        outputPath: AbsolutePath,
        recordingProcess: ProcessController
    ) {
        self.outputPath = outputPath
        self.recordingProcess = recordingProcess
    }
    
    func stopRecording() -> AbsolutePath {
        // Шлём SIGINT напрямую по PID: simctl recordVideo корректно финализирует mp4 по SIGINT.
        // SIGKILL нельзя — обрежет недописанный файл. (Исторический контекст: до CLT-фикса
        // f77f0c0 групповой kill(-pid) в ProcessController был ESRCH no-op; сейчас доставка
        // сигналов работает, прямой kill здесь остаётся как независимый от обвязки путь.)
        let pid = recordingProcess.processId
        if pid > 0 {
            kill(pid, SIGINT)

            // Ждём, пока simctl допишет файл и завершится. Bounded-таймаут на случай,
            // если SIGINT не сработал, — только ПОСЛЕ него добиваем SIGKILL (битый файл
            // лучше отсутствия процесса-зомби, держащего симулятор).
            let deadline = Date().addingTimeInterval(15)
            while recordingProcess.isProcessRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if recordingProcess.isProcessRunning {
                kill(pid, SIGKILL)
            }
        }
        recordingProcess.waitForProcessToDie()
        return outputPath
    }
    
    func cancelRecording() {
        // Отмена записи: мягкий SIGINT (recordVideo отпускает GPU-ресурсы и выходит),
        // bounded-ожидание, SIGKILL — только зависшему. Файл затем удаляется (это отмена).
        // Жёсткий SIGKILL посреди захвата подозревался в деградации paravirt-GPU стека.
        let pid = recordingProcess.processId
        if pid > 0 {
            kill(pid, SIGINT)

            let deadline = Date().addingTimeInterval(15)
            while recordingProcess.isProcessRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if recordingProcess.isProcessRunning {
                kill(pid, SIGKILL)
            }
        }
        recordingProcess.waitForProcessToDie()

        let fileManager = FileManager()
        if fileManager.fileExists(atPath: outputPath.pathString) {
            try? fileManager.removeItem(atPath: outputPath.pathString)
        }
    }
}
