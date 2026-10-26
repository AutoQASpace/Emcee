import DeveloperDirModels
import Dispatch
import Foundation
import EmceeLogging
import ResourceLocationResolver
import RunnerModels
import SimulatorPoolModels
import Tmp

public final class DefaultSimulatorPool: SimulatorPool, CustomStringConvertible {
    private let developerDir: DeveloperDir
    private let logger: ContextualLogger
    private let simulatorControllerProvider: SimulatorControllerProvider
    private let tempFolder: TemporaryFolder
    private let testDestination: TestDestination
    private var controllers = [SimulatorController]()
    private var idleShutdownControllerIds = Set<ObjectIdentifier>()
    private let syncQueue = DispatchQueue(label: "DefaultSimulatorPool.syncQueue")
    
    public var description: String {
        return "<\(type(of: self)): '\(testDestination.deviceType)'+'\(testDestination.runtime)'>"
    }
    
    public init(
        developerDir: DeveloperDir,
        logger: ContextualLogger,
        simulatorControllerProvider: SimulatorControllerProvider,
        tempFolder: TemporaryFolder,
        testDestination: TestDestination
    ) throws {
        self.developerDir = developerDir
        self.logger = logger
        self.simulatorControllerProvider = simulatorControllerProvider
        self.tempFolder = tempFolder
        self.testDestination = testDestination
    }
    
    deinit {
        deleteSimulators()
    }
    
    public func allocateSimulatorController() throws -> SimulatorController {
        return try syncQueue.sync {
            if let controller = controllers.popLast() {
                idleShutdownControllerIds.remove(ObjectIdentifier(controller as AnyObject))
                logger.debug("Allocated simulator: \(controller)")
                controller.simulatorBecameBusy()
                return controller
            }
            let controller = try simulatorControllerProvider.createSimulatorController(
                developerDir: developerDir,
                temporaryFolder: tempFolder,
                testDestination: testDestination
            )
            logger.debug("Allocated new simulator: \(controller)")
            controller.simulatorBecameBusy()
            return controller
        }
    }
    
    public func free(simulatorController: SimulatorController) {
        syncQueue.sync {
            controllers.append(simulatorController)
            logger.debug("Freed simulator: \(simulatorController)")
            simulatorController.simulatorBecameIdle()
        }
    }
    
    public func deleteSimulators() {
        syncQueue.sync {
            logger.debug("\(self): deleting simulators")
            controllers.forEach {
                do {
                    try $0.deleteSimulator()
                } catch {
                    logger.warning("Failed to delete simulator \($0): \(error). Skipping this error.")
                }
            }
        }
    }
    
    public func shutdownIdleSimulators(reason: String) {
        syncQueue.sync {
            controllers.forEach {
                let controllerId = ObjectIdentifier($0 as AnyObject)
                guard !idleShutdownControllerIds.contains(controllerId) else { return }
                do {
                    try $0.shutdownSimulator()
                    idleShutdownControllerIds.insert(controllerId)
                    logger.warning("idle simulator shut down on destination switch: \($0) in \(self), reason: \(reason)")
                } catch {
                    logger.warning("failed to shut down idle simulator on destination switch: \($0) in \(self), reason: \(reason), error: \(error). Skipping this error.")
                }
            }
        }
    }
}
