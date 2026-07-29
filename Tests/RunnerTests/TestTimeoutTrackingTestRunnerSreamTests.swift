import DateProviderTestHelpers
import EmceeLogging
import Foundation
import Runner
import RunnerModels
import XCTest

final class TestTimeoutTrackingTestRunnerSreamTests: XCTestCase {
    lazy var testName = TestName(className: "class", methodName: "test")
    lazy var dateProvider = DateProviderFixture()
    
    func test___test_finished_in_time___does_not_invoke_timeout_call() {
        let timeoutCallInvoked = XCTestExpectation(description: "Test timeout detected")
        timeoutCallInvoked.isInverted = true
        
        let stream = TestTimeoutTrackingTestRunnerSream(
            dateProvider: dateProvider,
            detectedLongRunningTest: { _, _ in
                timeoutCallInvoked.fulfill()
            },
            detectedStuckTest: { _ in },
            logger: { .noOp },
            maximumTestDuration: 5,
            pollPeriod: .milliseconds(100)
        )
        
        stream.testStarted(testName: testName)
        stream.testStopped(testStoppedEvent: TestStoppedEvent(testName: testName, result: .success, testDuration: 1, testExceptions: [], logs: [], testStartTimestamp: 0))
        
        wait(for: [timeoutCallInvoked], timeout: 5)
    }
    
    func test___test_hang_test___invokes_timeout_call_only_once() {
        let timeoutCallInvoked = XCTestExpectation(description: "Test timeout detected only once")
        timeoutCallInvoked.isInverted = true
        timeoutCallInvoked.expectedFulfillmentCount = 2
        
        let stream = TestTimeoutTrackingTestRunnerSream(
            dateProvider: dateProvider,
            detectedLongRunningTest: { _, _ in
                timeoutCallInvoked.fulfill()
            },
            detectedStuckTest: { _ in },
            logger: { .noOp },
            maximumTestDuration: 1,
            pollPeriod: .milliseconds(100)
        )
        
        stream.testStarted(testName: testName)
        dateProvider.result += 100
        
        wait(for: [timeoutCallInvoked], timeout: 5)
    }
    
    func test___test_hang_test_is_not_invoked___when_stream_closes() {
        let timeoutCallInvoked = XCTestExpectation(description: "Test timeout shouldn't be called when stream closes")
        timeoutCallInvoked.isInverted = true
        
        let stream = TestTimeoutTrackingTestRunnerSream(
            dateProvider: dateProvider,
            detectedLongRunningTest: { _, _ in
                timeoutCallInvoked.fulfill()
            },
            detectedStuckTest: { _ in },
            logger: { .noOp },
            maximumTestDuration: 1,
            pollPeriod: .milliseconds(100)
        )
        
        stream.testStarted(testName: testName)
        dateProvider.result += 100
        stream.closeStream()
        
        wait(for: [timeoutCallInvoked], timeout: 5)
    }
    
    func test___stuck_test___invokes_stuck_call_after_grace_period() {
        let longRunningInvoked = XCTestExpectation(description: "Long running test detected")
        let stuckInvoked = XCTestExpectation(description: "Stuck test detected")
        
        let stream = TestTimeoutTrackingTestRunnerSream(
            dateProvider: dateProvider,
            detectedLongRunningTest: { _, _ in
                longRunningInvoked.fulfill()
            },
            detectedStuckTest: { _ in
                stuckInvoked.fulfill()
            },
            logger: { .noOp },
            maximumTestDuration: 1,
            stuckTestGracePeriod: 2,
            pollPeriod: .milliseconds(100)
        )
        
        stream.testStarted(testName: testName)
        dateProvider.result += 100
        
        wait(for: [longRunningInvoked, stuckInvoked], timeout: 5)
    }
    
    func test___long_running_test_within_grace___does_not_invoke_stuck_call() {
        let longRunningInvoked = XCTestExpectation(description: "Long running test detected")
        let stuckInvoked = XCTestExpectation(description: "Stuck test should not be detected within grace")
        stuckInvoked.isInverted = true
        
        let stream = TestTimeoutTrackingTestRunnerSream(
            dateProvider: dateProvider,
            detectedLongRunningTest: { _, _ in
                longRunningInvoked.fulfill()
            },
            detectedStuckTest: { _ in
                stuckInvoked.fulfill()
            },
            logger: { .noOp },
            maximumTestDuration: 1,
            stuckTestGracePeriod: 1000,
            pollPeriod: .milliseconds(100)
        )
        
        stream.testStarted(testName: testName)
        dateProvider.result += 100
        
        wait(for: [longRunningInvoked, stuckInvoked], timeout: 5)
    }
    
    func test___stuck_call_not_invoked___when_test_stops() {
        let stuckInvoked = XCTestExpectation(description: "Stuck test should not be detected after test stopped")
        stuckInvoked.isInverted = true
        
        let stream = TestTimeoutTrackingTestRunnerSream(
            dateProvider: dateProvider,
            detectedLongRunningTest: { _, _ in },
            detectedStuckTest: { _ in
                stuckInvoked.fulfill()
            },
            logger: { .noOp },
            maximumTestDuration: 1,
            stuckTestGracePeriod: 2,
            pollPeriod: .milliseconds(100)
        )
        
        stream.testStarted(testName: testName)
        stream.testStopped(testStoppedEvent: TestStoppedEvent(testName: testName, result: .success, testDuration: 1, testExceptions: [], logs: [], testStartTimestamp: 0))
        dateProvider.result += 100
        
        wait(for: [stuckInvoked], timeout: 5)
    }
}
