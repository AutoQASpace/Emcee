import DateProvider
import Foundation
import EmceeLogging
import MetricsRecording
import MetricsExtensions
import PathLib
import QueueModels
import SimulatorPoolModels
import Types

public final class MetricSupportingSimulatorStateMachineActionExecutor: SimulatorStateMachineActionExecutor {
    let delegate: SimulatorStateMachineActionExecutor
    private let dateProvider: DateProvider
    private let version: Version
    private let globalMetricRecorder: GlobalMetricRecorder
    private let hostname: String
    
    public init(
        dateProvider: DateProvider,
        delegate: SimulatorStateMachineActionExecutor,
        version: Version,
        globalMetricRecorder: GlobalMetricRecorder,
        hostname: String
    ) {
        self.dateProvider = dateProvider
        self.delegate = delegate
        self.version = version
        self.globalMetricRecorder = globalMetricRecorder
        self.hostname = hostname
    }
    
    public func performCreateSimulatorAction(
        environment: [String: String],
        simDeviceType: SimDeviceType,
        simRuntime: SimRuntime,
        timeout: TimeInterval
    ) throws -> Simulator {
        return try measure(
            action: .create,
            deviceType: simDeviceType,
            runtime: simRuntime,
            hostname: hostname,
            work: {
                try delegate.performCreateSimulatorAction(
                    environment: environment,
                    simDeviceType: simDeviceType,
                    simRuntime: simRuntime,
                    timeout: timeout
                )
            }
        )
    }
    
    public func performBootSimulatorAction(
        environment: [String: String],
        simulator: Simulator,
        timeout: TimeInterval
    ) throws {
        try measure(
            action: .boot,
            deviceType: simulator.simDeviceType,
            runtime: simulator.simRuntime,
            hostname: hostname,
            work: {
                try delegate.performBootSimulatorAction(
                    environment: environment,
                    simulator: simulator,
                    timeout: timeout
                )
            }
        )
    }
    
    public func performShutdownSimulatorAction(
        environment: [String: String],
        simulator: Simulator,
        timeout: TimeInterval
    ) throws {
        try measure(
            action: .shutdown,
            deviceType: simulator.simDeviceType,
            runtime: simulator.simRuntime,
            hostname: hostname,
            work: {
                try delegate.performShutdownSimulatorAction(
                    environment: environment,
                    simulator: simulator,
                    timeout: timeout
                )
            }
        )
    }
    
    public func performDeleteSimulatorAction(
        environment: [String: String],
        simulator: Simulator,
        timeout: TimeInterval
    ) throws {
        try measure(
            action: .delete,
            deviceType: simulator.simDeviceType,
            runtime: simulator.simRuntime,
            hostname: hostname,
            work: {
                try delegate.performDeleteSimulatorAction(
                    environment: environment,
                    simulator: simulator,
                    timeout: timeout
                )
            }
        )
    }
    
    private func measure<T>(
        action: SimulatorDurationMetric.Action,
        deviceType: SimDeviceType,
        runtime: SimRuntime,
        hostname: String,
        work: () throws -> T
    ) throws -> T {
        let result: Either<T, Error>
        let startTime = Date()
        do {
            result = Either.success(try work())
        } catch {
            result = Either.error(error)
        }
        
        globalMetricRecorder.capture(
            SimulatorDurationMetric(
                action: action,
                host: hostname,
                deviceType: deviceType,
                runtime: runtime,
                isSuccessful: result.isSuccess,
                duration: dateProvider.currentDate().timeIntervalSince(startTime),
                version: version,
                timestamp: dateProvider.currentDate()
            )
        )
        
        return try result.dematerialize()
    }
}
