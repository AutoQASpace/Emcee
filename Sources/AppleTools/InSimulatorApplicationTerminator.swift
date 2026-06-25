import BuildArtifacts
import EmceeLogging
import Foundation
import PathLib
import ProcessController
import ResourceLocation
import ResourceLocationResolver

/// Принудительно завершает приложения (app под тестом + UITests-Runner) внутри
/// симулятора через `simctl terminate`, без reboot/erase.
///
/// Нужно, чтобы внутри-симуляторные процессы не пережили освобождение симулятора:
/// иначе осиротевший runner продолжает работу на симе и конкурирует со следующим
/// bucket'ом за SpringBoard и реестр приложений (FBSApplicationLibrary), что
/// приводит к обрывам прогона и каскаду mass-skip.
public final class InSimulatorApplicationTerminator {

    private let processControllerProvider: ProcessControllerProvider
    private let resourceLocationResolver: ResourceLocationResolver

    public init(
        processControllerProvider: ProcessControllerProvider,
        resourceLocationResolver: ResourceLocationResolver
    ) {
        self.processControllerProvider = processControllerProvider
        self.resourceLocationResolver = resourceLocationResolver
    }

    /// Завершает app под тестом и UITests-Runner в указанном симуляторе.
    /// Best-effort: ошибки резолва bundle id и `simctl terminate` не пробрасываются,
    /// а логируются — доочистка не должна ронять прогон.
    public func terminateApplications(
        buildArtifacts: IosBuildArtifacts,
        simulatorSetPath: AbsolutePath,
        simulatorUdid: String,
        logger: ContextualLogger
    ) {
        for bundleIdentifier in bundleIdentifiers(buildArtifacts: buildArtifacts, logger: logger) {
            terminate(
                bundleIdentifier: bundleIdentifier,
                simulatorSetPath: simulatorSetPath,
                simulatorUdid: simulatorUdid,
                logger: logger
            )
        }
    }

    private func bundleIdentifiers(
        buildArtifacts: IosBuildArtifacts,
        logger: ContextualLogger
    ) -> [String] {
        do {
            switch buildArtifacts {
            case .iosLogicTests:
                return []
            case .iosApplicationTests(_, let appBundle):
                return [
                    try bundleIdentifier(ofResolvable: resourceLocationResolver.resolvable(withRepresentable: appBundle))
                ].compactMap { $0 }
            case .iosUiTests(_, let appBundle, let runner, _):
                return [
                    try bundleIdentifier(ofResolvable: resourceLocationResolver.resolvable(withRepresentable: appBundle)),
                    try bundleIdentifier(ofResolvable: resourceLocationResolver.resolvable(withRepresentable: runner))
                ].compactMap { $0 }
            }
        } catch {
            logger.warning("Failed to resolve bundle identifiers for in-simulator cleanup: \(error)")
            return []
        }
    }

    private func bundleIdentifier(ofResolvable resolvable: ResolvableResourceLocation) throws -> String? {
        let bundlePath = try resolvable.resolve().directlyAccessibleResourcePath()
        return Bundle(path: bundlePath.pathString)?.bundleIdentifier
    }

    private func terminate(
        bundleIdentifier: String,
        simulatorSetPath: AbsolutePath,
        simulatorUdid: String,
        logger: ContextualLogger
    ) {
        do {
            let controller = try processControllerProvider.createProcessController(
                subprocess: Subprocess(
                    arguments: [
                        "/usr/bin/xcrun", "simctl",
                        "--set", simulatorSetPath,
                        "terminate", simulatorUdid, bundleIdentifier
                    ]
                )
            )
            logger.debug("In-sim cleanup: running 'simctl terminate \(simulatorUdid) \(bundleIdentifier)'")
            try? controller.startAndWaitForSuccessfulTermination()
            logger.debug("In-sim cleanup: finished 'simctl terminate \(simulatorUdid) \(bundleIdentifier)'")
        } catch {
            logger.warning("Failed to terminate \(bundleIdentifier) in simulator \(simulatorUdid): \(error)")
        }
    }
}
