import DeveloperDirLocator
import DeveloperDirModels
import EmceeExtensions
import Foundation
import PlistLib
import ProcessController
import SimulatorPoolModels
import Tmp
import UniqueIdentifierGenerator
import ResourceLocationResolver
import PathLib

public final class SimulatorSettingsModifierImpl: SimulatorSettingsModifier {

    /// Набор значений, которые надо иметь в одном plist-файле симулятора.
    private struct DomainPatch {
        /// Имя файла в `<device>/data/Library/Preferences`.
        ///
        /// Именно файла, а не домена cfprefsd: домен SpringBoard называется
        /// `com.apple.springboard` строчными (это его bundle id), и файл лежит с таким же
        /// именем. Раньше здесь стоял `com.apple.SpringBoard`, и запись уходила в никуда —
        /// файловая система macOS регистронезависима, а cfprefsd нет, поэтому «прочитать»
        /// такой домен получалось, а записать нет.
        let fileName: String
        let entries: [String: Any]
    }

    private enum Constants {
        /// Таймауты операций с симулятором в `apply()` не приходят, поэтому берём с запасом
        /// относительно `simulatorOperationTimeouts` из конфигурации прогона.
        static let shutdownTimeout: TimeInterval = 60
        static let bootTimeout: TimeInterval = 300
    }

    private let developerDirLocator: DeveloperDirLocator
    private let processControllerProvider: ProcessControllerProvider
    private let tempFolder: TemporaryFolder
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    private let resourceLocationResolver: ResourceLocationResolver

    public init(
        developerDirLocator: DeveloperDirLocator,
        processControllerProvider: ProcessControllerProvider,
        tempFolder: TemporaryFolder,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator,
        resourceLocationResolver: ResourceLocationResolver
    ) {
        self.developerDirLocator = developerDirLocator
        self.processControllerProvider = processControllerProvider
        self.tempFolder = tempFolder
        self.uniqueIdentifierGenerator = uniqueIdentifierGenerator
        self.resourceLocationResolver = resourceLocationResolver
    }
    
    /// Применяет настройки симулятора записью plist-файлов на **выключенном** симуляторе.
    ///
    /// Раньше настройки писались через `defaults import` в живой симулятор, а чтобы они
    /// вступили в силу, SpringBoard убивали (`SIGKILL`) — он перечитывает их только при своём
    /// старте. Так делать нельзя: на iOS 18 любой перезапуск SpringBoard лишает симулятор
    /// способности менять ориентацию до конца сессии, и все тесты с поворотом падают
    /// (`Failed to find "fullscreen_button"`). Ни мягкий рестарт, ни перезапуск `backboardd`
    /// не помогают — состояние переживает и то, и другое, лечит только перезагрузка симулятора.
    ///
    /// Поэтому: если нужных значений ещё нет, симулятор гасится, файлы пишутся напрямую и
    /// симулятор бутится заново. SpringBoard стартует уже с новыми настройками, убивать
    /// никого не нужно. Подробности — AQA-8030.
    public func apply(
        developerDir: DeveloperDir,
        simulatorSettings: SimulatorSettings,
        toSimulator simulator: Simulator
    ) throws {
        let environment = Environment(try developerDirLocator.suitableEnvironment(forDeveloperDir: developerDir))
        let patches = domainPatches(simulatorSettings: simulatorSettings)

        if patches.contains(where: { !isSatisfied(patch: $0, simulator: simulator) }) {
            try shutdown(environment: environment, simulator: simulator)
            try patches.forEach { try write(patch: $0, simulator: simulator) }
            try boot(environment: environment, simulator: simulator)
        }

        try addRootCertsKeychain(
            rootCerts: simulatorSettings.simulatorKeychainSettings.rootCerts,
            environment: environment,
            simulator: simulator
        )

        try applySchemeApprovals(
            approvals: simulatorSettings.schemeApprovalSettings.approvals,
            environment: environment,
            simulator: simulator
        )
    }

    private func domainPatches(simulatorSettings: SimulatorSettings) -> [DomainPatch] {
        let localization = simulatorSettings.simulatorLocalizationSettings
        let watchdog = simulatorSettings.watchdogSettings
        return [
            DomainPatch(
                fileName: ".GlobalPreferences.plist",
                entries: [
                    "AppleLocale": localization.localeIdentifier,
                    "AppleLanguages": localization.languages,
                    "AppleKeyboards": localization.keyboards,
                    "ApplePasscodeKeyboards": localization.passcodeKeyboards,
                    "AppleKeyboardsExpanded": localization.enableKeyboardExpansion ? 1 : 0,
                    "AddingEmojiKeybordHandled": localization.addingEmojiKeybordHandled,
                ]
            ),
            DomainPatch(
                fileName: "com.apple.Preferences.plist",
                entries: [
                    "UIKeyboardDidShowInternationalInfoIntroduction": localization.didShowInternationalInfoAlert,
                    "DidShowContinuousPathIntroduction": localization.didShowContinuousPathIntroduction,
                    "DidShowGestureKeyboardIntroduction": localization.didShowGestureKeyboardIntroduction,
                ]
            ),
            DomainPatch(
                fileName: "com.apple.keyboard.preferences.plist",
                entries: [
                    "DidShowContinuousPathIntroduction": localization.didShowContinuousPathIntroduction,
                ]
            ),
            DomainPatch(
                fileName: "com.apple.springboard.plist",
                entries: [
                    "FBLaunchWatchdogExceptions": watchdog.bundleIds.reduce(into: [String: Int]()) {
                        $0[$1] = watchdog.timeout
                    },
                ]
            ),
        ]
    }

    private func isSatisfied(patch: DomainPatch, simulator: Simulator) -> Bool {
        let currentEntries = plist(at: path(for: patch, simulator: simulator))
        return patch.entries.allSatisfy { key, wanted in
            isSatisfied(current: currentEntries?[key], wanted: wanted)
        }
    }

    /// На каждом бутe iOS дописывает к нашим спискам своё — язык и клавиатуру хоста, а в
    /// `FBLaunchWatchdogExceptions` добавляет собственные записи вроде `com.apple.Spotlight`.
    /// Поэтому строгое равенство значений давало бы вечное расхождение: применили — iOS
    /// дописала — на следующем бакетe применяем снова, и так каждый раз.
    ///
    /// Считаем настройку применённой, если на месте **наши** значения: для массивов наш список
    /// должен быть префиксом фактического (порядок важен — первым элементом определяются язык
    /// приложения и активная раскладка, поэтому вставку перед нашими значениями надо замечать,
    /// а не игнорировать), для словарей достаточно наличия наших пар, для остального — равенство.
    private func isSatisfied(current: Any?, wanted: Any) -> Bool {
        if let wantedArray = wanted as? [Any] {
            guard !wantedArray.isEmpty else { return true }
            guard let currentArray = current as? [Any], currentArray.count >= wantedArray.count else { return false }
            return zip(currentArray, wantedArray).allSatisfy { isSatisfied(current: $0, wanted: $1) }
        }
        if let wantedDict = wanted as? [String: Any] {
            guard let currentDict = current as? [String: Any] else { return wantedDict.isEmpty }
            return wantedDict.allSatisfy { isSatisfied(current: currentDict[$0.key], wanted: $0.value) }
        }
        guard let currentValue = current as? NSObject, let wantedValue = wanted as? NSObject else { return false }
        return currentValue.isEqual(wantedValue)
    }

    private func write(patch: DomainPatch, simulator: Simulator) throws {
        let plistPath = path(for: patch, simulator: simulator)
        var entries = plist(at: plistPath) ?? [:]
        patch.entries.forEach { key, wanted in
            entries[key] = merged(current: entries[key], wanted: wanted)
        }
        try FileManager.default.createDirectory(
            at: plistPath.removingLastComponent.fileUrl,
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
        try data.write(to: plistPath.fileUrl, options: .atomic)
    }

    /// Словари мержим, чтобы не выбросить записи самой iOS: в исключениях вотчдога живёт её
    /// `com.apple.Spotlight`, и он должен остаться. Массивы и скаляры заменяем целиком —
    /// порядок в списках задаёт приоритет, и определять его должны мы.
    private func merged(current: Any?, wanted: Any) -> Any {
        guard let wantedDict = wanted as? [String: Any] else { return wanted }
        guard var result = current as? [String: Any] else { return wanted }
        wantedDict.forEach { result[$0.key] = merged(current: result[$0.key], wanted: $0.value) }
        return result
    }

    private func plist(at path: AbsolutePath) -> [String: Any]? {
        guard let data = try? Data(contentsOf: path.fileUrl) else { return nil }
        let contents = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return contents as? [String: Any]
    }

    private func path(for patch: DomainPatch, simulator: Simulator) -> AbsolutePath {
        simulator.path.appending("data", "Library", "Preferences", patch.fileName)
    }

    private func shutdown(environment: Environment, simulator: Simulator) throws {
        try processControllerProvider.startAndWaitForSuccessfulTermination(
            arguments: [
                "/usr/bin/xcrun", "simctl", "--set", simulator.simulatorSetPath,
                "shutdown", simulator.udid.value,
            ],
            environment: environment,
            automaticManagement: .sigintThenKillAfterRunningFor(interval: Constants.shutdownTimeout)
        )
    }

    private func boot(environment: Environment, simulator: Simulator) throws {
        try processControllerProvider.startAndWaitForSuccessfulTermination(
            arguments: [
                "/usr/bin/xcrun", "simctl", "--set", simulator.simulatorSetPath,
                "bootstatus", simulator.udid.value, "-bd",
            ],
            environment: environment,
            automaticManagement: .sigintThenKillAfterRunningFor(interval: Constants.bootTimeout)
        )
    }

    private func applySchemeApprovals(
        approvals: [SchemeApprovalSettings.Approval],
        environment: Environment,
        simulator: Simulator
    ) throws {
        for approval in approvals {
            let key = "com.apple.CoreSimulator.CoreSimulatorBridge-->\(approval.scheme)"
            try processControllerProvider.startAndWaitForSuccessfulTermination(
                arguments: [
                    "/usr/bin/xcrun", "simctl", "--set", simulator.simulatorSetPath,
                    "spawn", simulator.udid.value,
                    "defaults", "write", "com.apple.launchservices.schemeapproval",
                    key, approval.bundleId,
                ],
                environment: environment,
                automaticManagement: .sigtermThenKillIfSilent(interval: 30)
            )
        }
    }

    private func addRootCertsKeychain(
        rootCerts: [SimulatorCertificateLocation],
        environment: Environment,
        simulator: Simulator
    ) throws {
        let certPaths: [AbsolutePath] = try rootCerts.map {
            try resourceLocationResolver
                .resolvePath(resourceLocation: $0.resourceLocation)
                .directlyAccessibleResourcePath()
        }
                
        try certPaths.forEach { certPath in
            try processControllerProvider.startAndWaitForSuccessfulTermination(
                arguments: ["/usr/bin/xcrun", "simctl", "--set", simulator.simulatorSetPath, "keychain", simulator.udid.value, "add-root-cert", certPath],
                environment: environment,
                automaticManagement: .sigtermThenKillIfSilent(interval: 30)
            )
        }
    }
    
}

extension ProcessControllerProvider {
    func startAndWaitForSuccessfulTermination(
        arguments: [SubprocessArgument],
        environment: Environment,
        automaticManagement: AutomaticManagement = .noManagement
    ) throws {
        try createProcessController(
            subprocess: Subprocess(
                arguments: arguments,
                environment: environment,
                automaticManagement: automaticManagement
            )
        ).startAndWaitForSuccessfulTermination()
    }
}
