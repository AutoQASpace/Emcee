import ArgLib
import AutomaticTermination
import BuildArtifacts
import CommonTestModels
import Deployer
import EmceeDI
import EmceeVersion
import Foundation
import LocalHostDeterminer
import MetricsExtensions
import PathLib
import QueueModels
import QueueServerConfiguration
import RESTServer
import ResourceLocationResolver
import SimulatorPoolModels
import TestArgFile
import TestDestination
import Tmp
import UniqueIdentifierGenerator

fileprivate var disposeBag: [Any] = []

public final class RunTestsCommand: Command {
    public let name = "runTests"
    public let description = "Runs tests (easy to use command)"
    public let arguments: Arguments = [
        ArgumentDescriptions.queue.asRequired.asMultiple,
        ArgumentDescriptions.worker.asRequired.asMultiple,
        ArgumentDescriptions.device.asRequired,
        ArgumentDescriptions.runtime.asRequired,
        ArgumentDescriptions.testBundle.asRequired,
        ArgumentDescriptions.kind.asOptional,
        ArgumentDescriptions.app.asOptional,
        ArgumentDescriptions.runner.asOptional,
        ArgumentDescriptions.test.asOptional,
        ArgumentDescriptions.retries.asOptional,
        ArgumentDescriptions.testTimeout.asOptional,
        ArgumentDescriptions.junit.asOptional,
        ArgumentDescriptions.trace.asOptional,
        ArgumentDescriptions.hostname.asOptional,
        ArgumentDescriptions.locale.asOptional,
        ArgumentDescriptions.language.asMultiple.asOptional,
        ArgumentDescriptions.keyboard.asMultiple.asOptional,
    ]
    
    private let di: DI
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    
    public init(di: DI) throws {
        self.di = di
        self.uniqueIdentifierGenerator = try di.get()
    }
    
    public func run(payload: CommandPayload) throws {
        let hostname: String = try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.hostname.name) ?? LocalHostDeterminer.currentHostAddress
        try HostnameSetup.update(hostname: hostname, di: di)
        
        let httpRestServer = HTTPRESTServer(
            automaticTerminationController: StayAliveTerminationController(),
            logger: try di.get(),
            portProvider: AnyAvailablePortProvider(),
            useOnlyIPv4: true
        )
        disposeBag.append(httpRestServer)
        
        let queueUrls: [URL] = try payload.nonEmptyCollectionOfValues(argumentName: ArgumentDescriptions.queue.name)
        let queueDeploymentDestinations = try queueUrls.map { try $0.deploymentDestination() }
        
        let workerUrls: [URL] = try payload.nonEmptyCollectionOfValues(argumentName: ArgumentDescriptions.worker.name)
        let workerDeploymentDestinations = try workerUrls.map { try $0.deploymentDestination() }
        
        let resourceLocationResolver: ResourceLocationResolver = try di.get()
        let testBundlePath: AbsolutePath = try resourceLocationResolver.resolvePath(
            resourceLocation: .localFilePath(
                try payload.expectedSingleTypedValue(argumentName: ArgumentDescriptions.testBundle.name)
            )
        ).directlyAccessibleResourcePath()
        let xcTestBundle = XcTestBundle(location: TestBundleLocation(.localFilePath(testBundlePath.pathString)), testDiscoveryMode: .parseFunctionSymbols)
        
        let appBundleLocation: String? = try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.app.name)
        let appBundlePath: AbsolutePath?
        if let appBundleLocation = appBundleLocation {
            appBundlePath = try resourceLocationResolver.resolvePath(
                resourceLocation: .localFilePath(appBundleLocation)
            ).directlyAccessibleResourcePath()
        } else {
            appBundlePath = nil
        }
        
        let runnerBundleLocation: String? = try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.runner.name)
        let runnerBundlePath: AbsolutePath?
        if let runnerBundleLocation = runnerBundleLocation {
            runnerBundlePath = try resourceLocationResolver.resolvePath(
                resourceLocation: .localFilePath(runnerBundleLocation)
            ).directlyAccessibleResourcePath()
        } else {
            runnerBundlePath = nil
        }
        
        let buildArtifacts: AppleBuildArtifacts
        if let runnerBundlePath = runnerBundlePath, let appBundlePath = appBundlePath {
            buildArtifacts = .iosUiTests(
                xcTestBundle: xcTestBundle,
                appBundle: AppBundleLocation(.localFilePath(appBundlePath.pathString)),
                runner: RunnerAppLocation(.localFilePath(runnerBundlePath.pathString)),
                additionalApplicationBundles: []
            )
        } else if let appBundlePath = appBundlePath {
            buildArtifacts = .iosApplicationTests(
                xcTestBundle: xcTestBundle,
                appBundle: AppBundleLocation(.localFilePath(appBundlePath.pathString))
            )
        } else {
            buildArtifacts = .iosLogicTests(xcTestBundle: xcTestBundle)
        }
        
        let testNamesToRun: [TestName] = try payload.possiblyEmptyCollectionOfValues(argumentName: ArgumentDescriptions.test.name)
        let numberOfRetries: UInt = try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.retries.name) ?? TestArgFileDefaultValues.numberOfRetries
        let testTimeout: TimeInterval = try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.testTimeout.name) ?? TestArgFileDefaultValues.testTimeoutConfiguration.singleTestMaximumDuration
        let testDestination = TestDestination.appleSimulator(
            deviceType: try payload.expectedSingleTypedValue(argumentName: ArgumentDescriptions.device.name),
            kind: try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.kind.name) ?? .iOS,
            version: try payload.expectedSingleTypedValue(argumentName: ArgumentDescriptions.runtime.name)
        )
        
        let simulatorLocale: String = try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.locale.name) ?? TestArgFileDefaultValues.simulatorLocalizationSettings.localeIdentifier
        let simulatorLanguages: [String] = try payload.possiblyEmptyCollectionOfValues(argumentName: ArgumentDescriptions.language.name).orIfEmpty(TestArgFileDefaultValues.simulatorLocalizationSettings.languages)
        let simulatorKeyboards: [String] = try payload.possiblyEmptyCollectionOfValues(argumentName: ArgumentDescriptions.keyboard.name).orIfEmpty(TestArgFileDefaultValues.simulatorLocalizationSettings.keyboards)
        let passcodeKeyboards: [String] = try payload.possiblyEmptyCollectionOfValues(argumentName: ArgumentDescriptions.passcodeKeyboard.name).orIfEmpty(TestArgFileDefaultValues.simulatorLocalizationSettings.passcodeKeyboards)
        
        var testsToRun: [TestToRun] = []
        if testNamesToRun.isEmpty {
            testsToRun = [.allDiscoveredTests]
        } else {
            testsToRun = testNamesToRun.map { .testName($0) }
        }
        
        var environment = [String: String]()
        ProcessInfo.processInfo.environment.forEach { (key: String, value: String) in
            if key.starts(with: "EMCEE_") {
                environment[String(key.dropFirst("EMCEE_".count))] = value
            }
        }
        
        let testArgFile = TestArgFile(
            entries: [
                TestArgFileEntry(
                    buildArtifacts: buildArtifacts,
                    developerDir: TestArgFileDefaultValues.developerDir,
                    environment: environment,
                    userInsertedLibraries: [],
                    numberOfRetries: numberOfRetries,
                    testRetryMode: TestArgFileDefaultValues.testRetryMode,
                    logCapturingMode: TestArgFileDefaultValues.logCapturingMode,
                    runnerWasteCleanupPolicy: TestArgFileDefaultValues.runnerWasteCleanupPolicy,
                    pluginLocations: [],
                    scheduleStrategy: TestArgFileDefaultValues.scheduleStrategy,
                    simulatorOperationTimeouts: TestArgFileDefaultValues.simulatorOperationTimeouts,
                    simulatorSettings: SimulatorSettings(
                        simulatorLocalizationSettings: TestArgFileDefaultValues.simulatorLocalizationSettings
                            .with(localeIdentifier: simulatorLocale)
                            .with(languages: simulatorLanguages)
                            .with(keyboards: simulatorKeyboards)
                            .with(passcodeKeyboards: passcodeKeyboards),
                        simulatorKeychainSettings: TestArgFileDefaultValues.simulatorSettings.simulatorKeychainSettings,
                        watchdogSettings: TestArgFileDefaultValues.simulatorSettings.watchdogSettings
                    ),
                    testDestination: testDestination,
                    testTimeoutConfiguration: TestTimeoutConfiguration(singleTestMaximumDuration: testTimeout, testRunnerMaximumSilenceDuration: testTimeout),
                    testAttachmentLifetime: TestArgFileDefaultValues.testAttachmentLifetime,
                    testsToRun: testsToRun,
                    workerCapabilityRequirements: TestArgFileDefaultValues.workerCapabilityRequirements
                )
            ],
            prioritizedJob: PrioritizedJob(
                analyticsConfiguration: AnalyticsConfiguration(),
                jobGroupId: JobGroupId(uniqueIdentifierGenerator.generate()),
                jobGroupPriority: .medium,
                jobId: JobId("autoJobId_" + uniqueIdentifierGenerator.generate()),
                jobPriority: .medium
            ),
            testDestinationConfigurations: []
        )
        
        let queueServerConfiguration = QueueServerConfiguration(
            globalAnalyticsConfiguration: AnalyticsConfiguration(),
            checkAgainTimeInterval: QueueServerConfigurationDefaultValues.checkAgainTimeInterval,
            queueServerDeploymentDestinations: queueDeploymentDestinations,
            queueServerTerminationPolicy: QueueServerConfigurationDefaultValues.queueServerTerminationPolicy,
            workerDeploymentDestinations: workerDeploymentDestinations,
            defaultWorkerSpecificConfiguration: WorkerSpecificConfigurationDefaultValues.defaultWorkerConfiguration,
            workerStartMode: QueueServerConfigurationDefaultValues.workerStartMode,
            useOnlyIPv4: QueueServerConfigurationDefaultValues.useOnlyIPv4,
            portRange: QueueServerConfigurationDefaultValues.defaultQueuePortRange
        )
        
        try RunTestsOnRemoteQueueLogic(di: di).run(
            commonReportOutput: ReportOutput(
                junit: try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.junit.name),
                tracingReport: try payload.optionalSingleTypedValue(argumentName: ArgumentDescriptions.trace.name)
            ),
            emceeVersion: EmceeVersion.version,
            hostname: hostname,
            logger: try di.get(),
            queueServerConfiguration: queueServerConfiguration,
            remoteCacheConfig: nil,
            tempFolder: try TemporaryFolder(),
            testArgFile: testArgFile,
            httpRestServer: httpRestServer
        )
    }
}

extension TestName: ParsableArgument {
    public init(argumentValue: String) throws {
        self = try Self.createFromTestNameString(stringValue: argumentValue)
    }
}

extension Double: ParsableArgument {
    public init(argumentValue: String) throws {
        guard let value = Self(argumentValue) else {
            throw GenericParseError<Self>(argumentValue: argumentValue)
        }
        self = value
    }
}
