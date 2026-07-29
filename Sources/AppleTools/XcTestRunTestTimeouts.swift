import Foundation

/// Native XCTest per-test timeouts (xctestrun keys TestTimeoutsEnabled /
/// DefaultTestExecutionTimeAllowance / MaximumTestExecutionTimeAllowance).
///
/// When enabled, XCTest itself fails a test that exceeds its allowance: the verdict is a
/// readable "exceeded execution time allowance" failure with a spindump attachment, the
/// runner is restarted and the REMAINING tests of the bucket continue to run. This is the
/// primary defense against tests hanging forever (e.g. an unbounded loop in test code with
/// a responsive app, which neither the simulator watchdog nor stream silence can catch).
///
/// Apple rounds allowances UP to full minutes: 270 requested → 300 effective.
public struct XcTestRunTestTimeouts: Equatable {
    /// Allowance applied to every test that does not override it, seconds.
    public let defaultExecutionTimeAllowance: Int

    /// Upper bound for per-test overrides via XCTestCase.executionTimeAllowance, seconds.
    public let maximumExecutionTimeAllowance: Int

    public init(
        defaultExecutionTimeAllowance: Int,
        maximumExecutionTimeAllowance: Int
    ) {
        self.defaultExecutionTimeAllowance = defaultExecutionTimeAllowance
        self.maximumExecutionTimeAllowance = maximumExecutionTimeAllowance
    }
}
