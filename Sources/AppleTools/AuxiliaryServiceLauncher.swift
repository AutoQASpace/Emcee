import Darwin
import EmceeLogging
import Foundation
import PathLib
import ProcessController
import ResourceLocationResolver
import RunnerModels

/// A process listening on a TCP port.
public struct AuxiliaryServicePortOwner: Equatable {
    public let pid: Int32
    /// Executable path of the process, nil if it could not be determined
    /// (e.g. the binary was deleted under a running process by a redeploy or cache eviction).
    public let executablePath: String?
    /// Process name; survives deletion of the executable.
    public let processName: String?

    public init(pid: Int32, executablePath: String?, processName: String? = nil) {
        self.pid = pid
        self.executablePath = executablePath
        self.processName = processName
    }
}

/// Finds and signals the process that listens on a port. Behind a protocol for unit tests.
public protocol AuxiliaryServicePortInspector {
    func listeningProcess(port: UInt16) -> AuxiliaryServicePortOwner?
    func sendSignal(_ signal: Int32, pid: Int32)
}

public enum AuxiliaryServiceLaunchDecision: Equatable {
    /// Port is free: start the binary.
    case start
    /// Port is held by the very same binary: nothing to do.
    case keepRunning(pid: Int32)
    /// Port is held by another build of this service: kill it and start ours.
    case replace(pid: Int32, executablePath: String)
    /// Port is held by something that is not this service (or path is unknown): don't touch it.
    case foreignProcess(pid: Int32, executablePath: String?)

    public static func decide(
        owner: AuxiliaryServicePortOwner?,
        expectedBinaryPath: AbsolutePath,
        binaryName: String
    ) -> AuxiliaryServiceLaunchDecision {
        guard let owner = owner else { return .start }
        guard let ownerPath = owner.executablePath else {
            if owner.processName == binaryName {
                return .replace(pid: owner.pid, executablePath: "<deleted> \(binaryName)")
            }
            return .foreignProcess(pid: owner.pid, executablePath: nil)
        }
        if canonical(ownerPath) == canonical(expectedBinaryPath.pathString) {
            return .keepRunning(pid: owner.pid)
        }
        if AbsolutePath(ownerPath).lastComponent == binaryName {
            return .replace(pid: owner.pid, executablePath: ownerPath)
        }
        return .foreignProcess(pid: owner.pid, executablePath: ownerPath)
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Starts auxiliary services (e.g. deeplink_bridge) on the worker and replaces outdated instances.
///
/// One instance per worker process: both simulator slots run buckets concurrently, and the
/// "who holds the port → kill → start" sequence must not interleave between them.
public final class AuxiliaryServiceLauncher {
    public static let shared = AuxiliaryServiceLauncher(portInspector: LsofAuxiliaryServicePortInspector())

    private let portInspector: AuxiliaryServicePortInspector
    private let lock = NSLock()
    /// Keeps controllers (and their output pipes) alive for the lifetime of the worker.
    private var spawnedControllers: [ProcessController] = []

    private let portReleaseTimeout: TimeInterval
    private let listenTimeout: TimeInterval
    private let pollInterval: TimeInterval

    public init(
        portInspector: AuxiliaryServicePortInspector,
        portReleaseTimeout: TimeInterval = 5,
        listenTimeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.2
    ) {
        self.portInspector = portInspector
        self.portReleaseTimeout = portReleaseTimeout
        self.listenTimeout = listenTimeout
        self.pollInterval = pollInterval
    }

    public func ensureRunning(
        services: [AuxiliaryService],
        resourceLocationResolver: ResourceLocationResolver,
        processControllerProvider: ProcessControllerProvider,
        logger: ContextualLogger
    ) {
        guard !services.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        for service in services {
            ensureRunning(
                service: service,
                resourceLocationResolver: resourceLocationResolver,
                processControllerProvider: processControllerProvider,
                logger: logger
            )
        }
    }

    private func ensureRunning(
        service: AuxiliaryService,
        resourceLocationResolver: ResourceLocationResolver,
        processControllerProvider: ProcessControllerProvider,
        logger: ContextualLogger
    ) {
        // Never log `service.location` itself: the URL carries JFrog credentials.
        guard let location = service.location else {
            logger.warning("Auxiliary service '\(service.key)' has no location, skipping it")
            return
        }

        let binaryPath: AbsolutePath
        do {
            binaryPath = try resourceLocationResolver.resolvePath(resourceLocation: location).directlyAccessibleResourcePath()
        } catch {
            logger.warning("Auxiliary service '\(service.key)' failed to resolve binary: \(Self.redactingCredentials("\(error)")). Skipping it; tests relying on this service may fail, but the worker stays alive.")
            return
        }

        let decision = AuxiliaryServiceLaunchDecision.decide(
            owner: portInspector.listeningProcess(port: service.port),
            expectedBinaryPath: binaryPath,
            binaryName: service.effectiveBinaryName
        )

        switch decision {
        case .keepRunning(let pid):
            logger.debug("Auxiliary service '\(service.key)' already running (pid \(pid)) from \(binaryPath)")
            return
        case .foreignProcess(let pid, let executablePath):
            logger.error("Auxiliary service '\(service.key)' port \(service.port) held by foreign pid \(pid) (\(executablePath ?? "unknown executable")), not touching it")
            return
        case .replace(let pid, let executablePath):
            logger.warning("Auxiliary service '\(service.key)' replacing pid \(pid) running \(executablePath) with \(binaryPath)")
            guard stop(pid: pid, port: service.port) else {
                logger.error("Auxiliary service '\(service.key)' port \(service.port) not released by pid \(pid) after SIGKILL, skipping start")
                return
            }
        case .start:
            break
        }

        start(service: service, binaryPath: binaryPath, processControllerProvider: processControllerProvider, logger: logger)
    }

    private func start(
        service: AuxiliaryService,
        binaryPath: AbsolutePath,
        processControllerProvider: ProcessControllerProvider,
        logger: ContextualLogger
    ) {
        logger.debug("Starting auxiliary service '\(service.key)' at \(binaryPath)")
        do {
            let controller = try processControllerProvider.createProcessController(
                subprocess: Subprocess(arguments: [binaryPath])
            )
            try controller.start()
            spawnedControllers.append(controller)
        } catch {
            // Отсутствующий/битый бинарь опционального aux-сервиса НЕ должен ронять слот:
            // исключение из run() выносит слот, а за ним и весь пул. Логируем и продолжаем.
            logger.warning("Failed to start auxiliary service '\(service.key)' at \(binaryPath): \(error). Skipping it; tests relying on this service may fail, but the worker stays alive.")
            return
        }

        if waitUntil(timeout: listenTimeout, { self.portInspector.listeningProcess(port: service.port) != nil }) {
            let pid = portInspector.listeningProcess(port: service.port)?.pid
            logger.info("Auxiliary service '\(service.key)' started (pid \(pid.map { "\($0)" } ?? "?")) from \(binaryPath)")
        } else {
            logger.warning("Auxiliary service '\(service.key)' did not start listening on port \(service.port) within \(Int(listenTimeout))s")
        }
    }

    /// SIGTERM, wait for the port to be released, then SIGKILL. Returns true if the port is free.
    private func stop(pid: Int32, port: UInt16) -> Bool {
        portInspector.sendSignal(SIGTERM, pid: pid)
        if waitUntil(timeout: portReleaseTimeout, { self.portInspector.listeningProcess(port: port) == nil }) {
            return true
        }
        portInspector.sendSignal(SIGKILL, pid: pid)
        return waitUntil(timeout: portReleaseTimeout, { self.portInspector.listeningProcess(port: port) == nil })
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    static func redactingCredentials(_ text: String) -> String {
        text.replacingOccurrences(of: "://[^/@\\s]+@", with: "://***@", options: .regularExpression)
    }
}

/// `lsof` finds the listener, `proc_pidpath` gives its executable.
public final class LsofAuxiliaryServicePortInspector: AuxiliaryServicePortInspector {
    public init() {}

    public func listeningProcess(port: UInt16) -> AuxiliaryServicePortOwner? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        guard let pid = output.split(whereSeparator: \.isNewline).compactMap({ Int32($0) }).first else {
            return nil
        }
        return AuxiliaryServicePortOwner(
            pid: pid,
            executablePath: Self.executablePath(pid: pid),
            processName: Self.processName(pid: pid)
        )
    }

    public func sendSignal(_ signal: Int32, pid: Int32) {
        _ = kill(pid, signal)
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
