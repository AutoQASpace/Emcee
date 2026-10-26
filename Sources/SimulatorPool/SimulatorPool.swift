import DeveloperDirLocator
import Dispatch
import Foundation
import EmceeLogging
import ResourceLocationResolver
import SimulatorPoolModels
import RunnerModels

/**
 * Every 'borrow' must have a corresponding 'free' call, otherwise the next borrow will throw an error.
 * There is no blocking mechanisms, the assumption is that the callers will use up to numberOfSimulators of threads
 * to borrow and free the simulators.
 */
public protocol SimulatorPool {
    func allocateSimulatorController() throws -> SimulatorController
    func free(simulatorController: SimulatorController)
    func deleteSimulators()
    /// Shuts down (without deleting) simulators that are free at the moment of the call.
    /// Allocated simulators are not affected. A simulator already shut down by this method is skipped until it is allocated again.
    func shutdownIdleSimulators(reason: String)
}
