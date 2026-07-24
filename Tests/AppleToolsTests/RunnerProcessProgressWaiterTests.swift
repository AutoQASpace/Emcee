import AppleTools
import EmceeLogging
import Foundation
import XCTest

final class RunnerProcessProgressWaiterTests: XCTestCase {
    private let logger = ContextualLogger.noOp

    private func makeWaiter(silence: TimeInterval, hardCap: TimeInterval) -> RunnerProcessProgressWaiter {
        RunnerProcessProgressWaiter(
            logger: logger,
            maximumSilenceDuration: silence,
            hardCap: hardCap,
            pollInterval: 0.02
        )
    }

    func test___process_exits_on_its_own___no_kill() {
        var running = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { running = false }
        var killed = false

        makeWaiter(silence: 5, hardCap: 10).waitForExit(
            isProcessRunning: { running },
            progressMarker: { "constant" },
            killProcess: { killed = true }
        )

        XCTAssertFalse(killed)
    }

    func test___no_progress_beyond_silence___kills() {
        var killed = false

        makeWaiter(silence: 0.1, hardCap: 10).waitForExit(
            isProcessRunning: { !killed },
            progressMarker: { "frozen" },
            killProcess: { killed = true }
        )

        XCTAssertTrue(killed)
    }

    func test___continuous_progress___survives_silence_but_hits_hard_cap() {
        var killed = false
        var counter = 0

        makeWaiter(silence: 0.15, hardCap: 0.5).waitForExit(
            isProcessRunning: { !killed },
            progressMarker: { counter += 1; return "tick-\(counter)" },
            killProcess: { killed = true }
        )

        XCTAssertTrue(killed)
    }

    func test___hard_cap_below_silence___is_clamped_to_silence() {
        // ждать дольше silence процесс с прогрессом должен, даже если cap задан меньше
        var killed = false
        let startedAt = Date()
        var counter = 0

        makeWaiter(silence: 0.3, hardCap: 0.05).waitForExit(
            isProcessRunning: { !killed && Date().timeIntervalSince(startedAt) < 0.2 },
            progressMarker: { counter += 1; return "tick-\(counter)" },
            killProcess: { killed = true }
        )

        XCTAssertFalse(killed, "cap должен быть клампнут до silence: процесс с прогрессом дожил до своего выхода")
    }
}
