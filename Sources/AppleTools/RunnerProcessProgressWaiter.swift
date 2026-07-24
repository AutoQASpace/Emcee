import EmceeLogging
import Foundation
import PathLib

/// Waits for the test runner host process (xcodebuild) to exit on its own after its result
/// stream reading has ended. The process finalizes the xcresult bundle at the very end of
/// its lifetime, so it must not be killed while it shows signs of file activity. Kills only
/// a process whose activity stalled (silence) or which outlived the absolute hard cap.
public final class RunnerProcessProgressWaiter {
    private let logger: ContextualLogger
    private let maximumSilenceDuration: TimeInterval
    private let hardCap: TimeInterval
    private let pollInterval: TimeInterval

    public init(
        logger: ContextualLogger,
        maximumSilenceDuration: TimeInterval,
        hardCap: TimeInterval,
        pollInterval: TimeInterval = 5
    ) {
        self.logger = logger
        self.maximumSilenceDuration = maximumSilenceDuration
        self.pollInterval = pollInterval
        if hardCap < maximumSilenceDuration {
            logger.warning("bucketShutdownHardCap (\(hardCap)) is below silence duration (\(maximumSilenceDuration)), clamping to silence")
            self.hardCap = maximumSilenceDuration
        } else {
            self.hardCap = hardCap
        }
    }

    public func waitForExit(
        isProcessRunning: () -> Bool,
        progressMarker: () -> String,
        killProcess: () -> ()
    ) {
        let startedAt = Date()
        var lastProgressAt = startedAt
        var lastMarker = progressMarker()

        while isProcessRunning() {
            let now = Date()
            if now.timeIntervalSince(startedAt) >= hardCap {
                logger.warning("Test runner process outlived hard cap (\(hardCap) sec), killing it")
                killProcess()
                return
            }
            let marker = progressMarker()
            if marker != lastMarker {
                lastMarker = marker
                lastProgressAt = now
            } else if now.timeIntervalSince(lastProgressAt) >= maximumSilenceDuration {
                logger.warning("Test runner process shows no file activity for \(maximumSilenceDuration) sec, killing it")
                killProcess()
                return
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }
}

/// Snapshot of observable file activity; any change of the marker counts as progress.
public enum FileActivityMarker {
    public static func marker(paths: [AbsolutePath]) -> String {
        let fileManager = FileManager()
        var parts = [String]()
        for path in paths {
            parts.append(describe(path: path.pathString, fileManager: fileManager))
            // неглубокий обход каталога (xcresult): записи первого уровня + Data/
            if let firstLevel = try? fileManager.contentsOfDirectory(atPath: path.pathString) {
                for entry in firstLevel.sorted() {
                    parts.append(describe(path: path.appending(entry).pathString, fileManager: fileManager))
                }
                let dataDir = path.appending("Data").pathString
                if let dataEntries = try? fileManager.contentsOfDirectory(atPath: dataDir) {
                    parts.append("\(dataDir):count=\(dataEntries.count)")
                }
            }
        }
        return parts.joined(separator: "|")
    }

    private static func describe(path: String, fileManager: FileManager) -> String {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return "\(path):absent"
        }
        let size = (attributes[.size] as? Int) ?? -1
        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(path):\(size):\(mtime)"
    }
}
