import DateProvider
import EmceeLogging
import Foundation
import QueueModels
import Timer
import WorkerAlivenessProvider

public struct SilentWorkerAutoKickstartSettings: Equatable {
    public let silenceThreshold: TimeInterval
    public let maxAttemptsPerWorker: Int
    public let cooldown: TimeInterval
    public let pollInterval: TimeInterval

    public init(
        silenceThreshold: TimeInterval,
        maxAttemptsPerWorker: Int,
        cooldown: TimeInterval,
        pollInterval: TimeInterval = 30
    ) {
        self.silenceThreshold = silenceThreshold
        self.maxAttemptsPerWorker = maxAttemptsPerWorker
        self.cooldown = cooldown
        self.pollInterval = pollInterval
    }
}

public final class SilentWorkerAutoKickstartPoller {
    private let dateProvider: DateProvider
    private let kickstartExecutor: (@escaping () -> Void) -> Void
    private let logger: ContextualLogger
    private let onDemandWorkerStarter: OnDemandWorkerStarter
    private let settings: SilentWorkerAutoKickstartSettings
    private let workerAlivenessProvider: WorkerAlivenessProvider
    private let workerIds: [WorkerId]
    private var candidateSince = [WorkerId: Date]()
    private var lastAttemptAt = [WorkerId: Date]()
    private var attempts = [WorkerId: Int]()
    private var inFlight = Set<WorkerId>()
    private var gaveUp = Set<WorkerId>()
    private var isMassSilenceEpisode = false
    private var pollingTimer: DispatchBasedTimer?
    private let lock = NSLock()

    public init(
        dateProvider: DateProvider,
        kickstartExecutor: @escaping (@escaping () -> Void) -> Void,
        logger: ContextualLogger,
        onDemandWorkerStarter: OnDemandWorkerStarter,
        settings: SilentWorkerAutoKickstartSettings,
        workerAlivenessProvider: WorkerAlivenessProvider,
        workerIds: [WorkerId]
    ) {
        self.dateProvider = dateProvider
        self.kickstartExecutor = kickstartExecutor
        self.logger = logger
        self.onDemandWorkerStarter = onDemandWorkerStarter
        self.settings = settings
        self.workerAlivenessProvider = workerAlivenessProvider
        self.workerIds = workerIds
    }

    public func startPolling() {
        logger.info("auto-kickstart enabled: threshold \(Int(settings.silenceThreshold))s, max \(settings.maxAttemptsPerWorker) attempts per worker, cooldown \(Int(settings.cooldown))s")
        pollingTimer = DispatchBasedTimer.startedTimer(
            repeating: .milliseconds(Int(settings.pollInterval * 1000)),
            leeway: .seconds(1),
            handler: { [weak self] timer in
                guard let self = self else { return timer.stop() }
                self.performTick()
            }
        )
    }

    public func stopPolling() {
        pollingTimer?.stop()
        pollingTimer = nil
    }

    /// internal for testing
    func performTick() {
        lock.lock()
        let kickstarts = selectWorkersToKickstart(now: dateProvider.currentDate())
        lock.unlock()
        for (workerId, attempt) in kickstarts {
            let attemptText = "attempt \(attempt)/\(settings.maxAttemptsPerWorker)"
            logger.warning("auto-kickstart fired for \(workerId.value) (\(attemptText))")
            kickstartExecutor { [weak self, logger, onDemandWorkerStarter] in
                do {
                    try onDemandWorkerStarter.start(workerId: workerId)
                } catch {
                    logger.error("auto-kickstart failed for \(workerId.value) (\(attemptText)): \(error)")
                }
                self?.didFinishKickstart(workerId: workerId)
            }
        }
    }

    private func didFinishKickstart(workerId: WorkerId) {
        lock.lock()
        defer { lock.unlock() }
        inFlight.remove(workerId)
    }

    private func selectWorkersToKickstart(now: Date) -> [(workerId: WorkerId, attempt: Int)] {
        let alivenesses = workerIds.map { (workerId: $0, aliveness: workerAlivenessProvider.alivenessForWorker(workerId: $0)) }
        let registered = alivenesses.filter { $0.aliveness.registered }
        // Молчат все, кто регистрировался, — проблема на стороне очереди/сети, а не воркеров.
        if !registered.isEmpty, registered.allSatisfy({ $0.aliveness.silent }) {
            if !isMassSilenceEpisode {
                isMassSilenceEpisode = true
                logger.warning("auto-kickstart skipped: all \(registered.count) registered workers are silent")
            }
            return []
        }
        isMassSilenceEpisode = false

        var result = [(workerId: WorkerId, attempt: Int)]()
        for (workerId, aliveness) in alivenesses {
            guard !aliveness.disabled, !aliveness.registered || aliveness.silent else {
                if candidateSince.removeValue(forKey: workerId) != nil {
                    logger.info("auto-kickstart candidate \(workerId.value) recovered")
                }
                continue
            }
            let since: Date
            if let existing = candidateSince[workerId] {
                since = existing
            } else {
                since = now
                candidateSince[workerId] = now
                logger.info("auto-kickstart candidate \(workerId.value) (\(aliveness.registered ? "silent" : "not registered"))")
            }
            guard now.timeIntervalSince(since) >= settings.silenceThreshold else { continue }
            guard !inFlight.contains(workerId) else { continue }
            if let lastAttempt = lastAttemptAt[workerId], now.timeIntervalSince(lastAttempt) < settings.cooldown {
                continue
            }
            let attempt = (attempts[workerId] ?? 0) + 1
            guard attempt <= settings.maxAttemptsPerWorker else {
                if gaveUp.insert(workerId).inserted {
                    logger.error(
                        "auto-kickstart gave up for \(workerId.value) after \(settings.maxAttemptsPerWorker) attempts: " +
                        "check the host manually — foreign console GUI session blocking Local Network " +
                        "(ios-emcee-runbook R1), repeated kernel panics, or host is down"
                    )
                }
                continue
            }
            attempts[workerId] = attempt
            lastAttemptAt[workerId] = now
            inFlight.insert(workerId)
            result.append((workerId: workerId, attempt: attempt))
        }
        return result
    }
}
