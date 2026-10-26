import Dispatch
import Foundation
import EmceeLogging
import RunnerModels
import Tmp

public class DefaultOnDemandSimulatorPool: OnDemandSimulatorPool {
    private let logger: ContextualLogger
    private let simulatorControllerProvider: SimulatorControllerProvider
    private let syncQueue = DispatchQueue(label: "ru.avito.OnDemandSimulatorPool")
    private let tempFolder: TemporaryFolder
    private var pools = [OnDemandSimulatorPoolKey: SimulatorPool]()
    
    public init(
        logger: ContextualLogger,
        simulatorControllerProvider: SimulatorControllerProvider,
        tempFolder: TemporaryFolder
    ) {
        self.logger = logger
        self.simulatorControllerProvider = simulatorControllerProvider
        self.tempFolder = tempFolder
    }
    
    deinit {
        deleteSimulators()
    }
    
    public func pool(key: OnDemandSimulatorPoolKey) throws -> SimulatorPool {
        let (pool, otherPools) = try syncQueue.sync { () -> (SimulatorPool, [SimulatorPool]) in
            let otherPools = pools.filter { $0.key != key }.map { $0.value }
            if let existingPool = pools[key] {
                logger.debug("Got SimulatorPool for key \(key)")
                return (existingPool, otherPools)
            } else {
                let pool = try DefaultSimulatorPool(
                    developerDir: key.developerDir,
                    logger: logger,
                    simulatorControllerProvider: simulatorControllerProvider,
                    tempFolder: tempFolder,
                    testDestination: key.testDestination
                )
                pools[key] = pool
                logger.debug("Created SimulatorPool for key \(key)")
                return (pool, otherPools)
            }
        }
        
        // Simulators of other destinations stay booted for automaticSimulatorShutdown after a bucket,
        // so with several destinations on one worker they pile up. Shut down the idle ones (busy ones are not in the pool).
        for otherPool in otherPools {
            otherPool.shutdownIdleSimulators(reason: "switching to \(key.testDestination)")
        }
        return pool
    }
    
    public func enumeratePools(iterator: (OnDemandSimulatorPoolKey, SimulatorPool) -> ()) {
        for (key, value) in syncQueue.sync(execute: { pools }) {
            iterator(key, value)
        }
    }
}
