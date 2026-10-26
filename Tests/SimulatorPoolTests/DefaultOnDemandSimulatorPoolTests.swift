@testable import SimulatorPool
import DeveloperDirModels
import SimulatorPoolModels
import SimulatorPoolTestHelpers
import Tmp
import TestHelpers
import XCTest

final class DefaultOnDemandSimulatorPoolTests: XCTestCase {

    lazy var tempFolder = assertDoesNotThrow { try TemporaryFolder() }
    lazy var simulatorControllerProvider = FakeSimulatorControllerProvider { _ -> SimulatorController in
        FakeSimulatorController(
            simulator: SimulatorFixture.simulator(),
            developerDir: .current
        )
    }
    lazy var onDemandPool = DefaultOnDemandSimulatorPool(
        logger: .noOp,
        simulatorControllerProvider: simulatorControllerProvider,
        tempFolder: tempFolder
    )
    let keyA = OnDemandSimulatorPoolKey(
        developerDir: .current,
        testDestination: TestDestinationFixtures.testDestination
    )
    lazy var keyB = OnDemandSimulatorPoolKey(
        developerDir: .current,
        testDestination: assertDoesNotThrow { try TestDestination(deviceType: "other device", runtime: "12.0") }
    )

    func test___idle_simulator_of_other_destination___is_shut_down___on_switch() throws {
        let controller = try allocateAndFree(key: keyA)

        _ = try onDemandPool.pool(key: keyB)

        XCTAssertTrue(controller.didCallShutdown)
        XCTAssertFalse(controller.didCallDelete)
    }

    func test___busy_simulator_of_other_destination___is_not_shut_down() throws {
        let controller = try allocate(key: keyA)
        
        _ = try onDemandPool.pool(key: keyB)
        
        XCTAssertFalse(controller.didCallShutdown)
    }
    
    func test___simulator___is_not_shut_down___when_destination_does_not_change() throws {
        let controller = try allocateAndFree(key: keyA)
        
        _ = try onDemandPool.pool(key: keyA)
        
        XCTAssertFalse(controller.didCallShutdown)
    }
    
    func test___already_shut_down_simulator___is_not_shut_down_again() throws {
        let controller = try allocateAndFree(key: keyA)
        _ = try onDemandPool.pool(key: keyB)
        controller.didCallShutdown = false
        
        _ = try onDemandPool.pool(key: keyB)
        
        XCTAssertFalse(controller.didCallShutdown)
    }
    
    func test___reused_simulator___is_shut_down_again___on_next_switch() throws {
        let controller = try allocateAndFree(key: keyA)
        _ = try onDemandPool.pool(key: keyB)
        XCTAssertTrue(try allocateAndFree(key: keyA) === controller)
        controller.didCallShutdown = false
        
        _ = try onDemandPool.pool(key: keyB)
        
        XCTAssertTrue(controller.didCallShutdown)
    }
    
    private func allocate(key: OnDemandSimulatorPoolKey) throws -> FakeSimulatorController {
        let controller = try onDemandPool.pool(key: key).allocateSimulatorController()
        guard let fakeController = controller as? FakeSimulatorController else {
            throw ErrorForTestingPurposes(text: "Unexpected type of controller")
        }
        return fakeController
    }

    private func allocateAndFree(key: OnDemandSimulatorPoolKey) throws -> FakeSimulatorController {
        let controller = try allocate(key: key)
        try onDemandPool.pool(key: key).free(simulatorController: controller)
        return controller
    }
}
