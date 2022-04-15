import AppleTools
import DateProvider
import Foundation
import MetricsRecording
import MetricsExtensions
import PathLib
import ProcessController
import QueueModels
import SimulatorPool
import SimulatorPoolModels
import Tmp

public final class SimulatorStateMachineActionExecutorProviderImpl: SimulatorStateMachineActionExecutorProvider {
    private let dateProvider: DateProvider
    private let hostname: String
    private let processControllerProvider: ProcessControllerProvider
    private let simulatorSetPathDeterminer: SimulatorSetPathDeterminer
    private let version: Version
    private let globalMetricRecorder: GlobalMetricRecorder

    public init(
        dateProvider: DateProvider,
        hostname: String,
        processControllerProvider: ProcessControllerProvider,
        simulatorSetPathDeterminer: SimulatorSetPathDeterminer,
        version: Version,
        globalMetricRecorder: GlobalMetricRecorder
    ) {
        self.dateProvider = dateProvider
        self.hostname = hostname
        self.processControllerProvider = processControllerProvider
        self.simulatorSetPathDeterminer = simulatorSetPathDeterminer
        self.version = version
        self.globalMetricRecorder = globalMetricRecorder
    }
    
    public func simulatorStateMachineActionExecutor(
    ) throws -> SimulatorStateMachineActionExecutor {
        let simulatorSetPath = try simulatorSetPathDeterminer.simulatorSetPathSuitableForTestRunnerTool()
        
        let simulatorStateMachineActionExecutor = SimctlBasedSimulatorStateMachineActionExecutor(
            processControllerProvider: processControllerProvider,
            simulatorSetPath: simulatorSetPath
        )
        
        return MetricSupportingSimulatorStateMachineActionExecutor(
            dateProvider: dateProvider,
            delegate: simulatorStateMachineActionExecutor,
            version: version,
            globalMetricRecorder: globalMetricRecorder,
            hostname: hostname
        )
    }
}
