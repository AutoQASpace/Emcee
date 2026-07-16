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
        // interruptAndForceKillIfNeeded() шлёт SIGINT по process-group через kill(-pid),
        // но запись стартует с setStartsNewProcessGroup(false) — группы с pgid == pid нет,
        // поэтому групповой SIGINT уходит в ESRCH (no-op), simctl recordVideo не получает
        // сигнал и не финализирует mp4. Бьём SIGINT напрямую по PID, чтобы запись корректно
        // закрылась и файл дописался. SIGKILL тут нельзя — обрежет недописанный mp4.
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
        // Групповой kill(-pid) при setStartsNewProcessGroup(false) уходит в ESRCH (no-op) —
        // процесс simctl recordVideo выживает и держит симулятор. Поэтому бьём напрямую по PID.
        // НО не жёстким SIGKILL: хард-убийство recordVideo посреди захвата рвёт клиентские
        // ресурсы IOSurface/GPU и подозревается в kernel-panic paravirt-GPU-драйвера
        // (mutex race @lock_mtx.c). Завершаем МЯГКО, как stopRecording: SIGINT напрямую по PID
        // (запись корректно закрывается и отпускает GPU-ресурсы), ждём выхода, и только если
        // завис — добиваем SIGKILL. Файл всё равно удаляем (это отмена, не сохранение).
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
