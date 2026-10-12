import BuildArtifacts
import DateProvider
import DeveloperDirLocator
import FileSystem
import Foundation
import EmceeLogging
import ObservableFileReader
import ProcessController
import ResourceLocationResolver
import ResultStream
import ResultStreamModels
import Runner
import RunnerModels
import Tmp
import PathLib
import XcodebuildTestRunnerConstants

public final class XcodebuildBasedTestRunner: TestRunner {
    private let dateProvider: DateProvider
    private let fileSystem: FileSystem
    private let processControllerProvider: ProcessControllerProvider
    private let resourceLocationResolver: ResourceLocationResolver
    private let xcResultTool: XcResultTool

    public init(
        dateProvider: DateProvider,
        fileSystem: FileSystem,
        processControllerProvider: ProcessControllerProvider,
        resourceLocationResolver: ResourceLocationResolver,
        xcResultTool: XcResultTool
    ) {
        self.dateProvider = dateProvider
        self.fileSystem = fileSystem
        self.processControllerProvider = processControllerProvider
        self.resourceLocationResolver = resourceLocationResolver
        self.xcResultTool = xcResultTool
    }
    
    public func prepareTestRun(
        buildArtifacts: IosBuildArtifacts,
        developerDirLocator: DeveloperDirLocator,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        testContext: TestContext,
        testRunnerStream: TestRunnerStream,
        testTimeoutConfiguration: TestTimeoutConfiguration
    ) throws -> TestRunnerInvocation {
        AuxiliaryServiceLauncher.shared.ensureRunning(
            services: testContext.auxiliaryServices ?? [],
            resourceLocationResolver: resourceLocationResolver,
            processControllerProvider: processControllerProvider,
            logger: logger
        )

        let resultStreamFile = testContext.testRunnerWorkingDirectory.appending("result_stream.json")
        try fileSystem.createFile(path: resultStreamFile, data: nil)
        
        let xcresultBundlePath = self.xcresultBundlePath(
            testRunnerWorkingDirectory: testContext.testRunnerWorkingDirectory
        )
        
        let xcTestRunFile = XcTestRunFileArgument(
            buildArtifacts: buildArtifacts,
            entriesToRun: entriesToRun,
            path: testContext.testRunnerWorkingDirectory.appending("testrun.xctestrun"),
            resourceLocationResolver: resourceLocationResolver,
            testContext: testContext,
            testingEnvironment: XcTestRunTestingEnvironment(
                insertedLibraries: testContext.userInsertedLibraries
            ),
            singleTestMaximumDuration: testTimeoutConfiguration.singleTestMaximumDuration
        )
        
        let processController = try processControllerProvider.createProcessController(
            subprocess: Subprocess(
                arguments: [
                    "/usr/bin/xcrun",
                    "xcodebuild",
                    "-destination", XcodebuildSimulatorDestinationArgument(destinationId: testContext.simulatorUdid),
                    "-derivedDataPath", testContext.testRunnerWorkingDirectory.appending("derivedData"),
                    "-resultBundlePath", xcresultBundlePath,
                    "-resultStreamPath", resultStreamFile,
                    "-xctestrun", xcTestRunFile,
                    "-parallel-testing-enabled", "NO",
                    "test-without-building",
                ],
                environment: Environment(testContext.environment)
            )
        )
        
        let resultStream = ResultStreamImpl(
            dateProvider: dateProvider,
            logger: logger,
            testRunnerStream: testRunnerStream
        )
        let observableFileReader: ObservableFileReader = ObservableFileReaderImpl(
            path: resultStreamFile,
            processControllerProvider: processControllerProvider
        )
        
        var observableFileReaderHandler: ObservableFileReaderHandler?
        
        processController.onStart { [logger] sender, _ in
            testRunnerStream.openStream()
            do {
                observableFileReaderHandler = try observableFileReader.read(handler: resultStream.write(data:))
            } catch {
                logger.error("Failed to read stream file: \(error)", subprocessPidInfo: sender.subprocessInfo.pidInfo)
                return sender.terminateAndForceKillIfNeeded()
            }
            resultStream.streamContents { [weak self] error in
                if let error = error {
                    logger.error("Result stream error: \(error)", subprocessPidInfo: sender.subprocessInfo.pidInfo)
                    // улика для расследования порчи стрима (дефект A)
                    logger.error("Result stream file state: \(FileActivityMarker.marker(paths: [resultStreamFile]))")
                }

                // Билдер автономен: конец НАШЕГО чтения (в т.ч. по ошибке парсера) не означает
                // конца исполнения тестов. Процесс финализирует xcresult в самом конце жизни —
                // убивать его здесь нельзя (гонка с финализацией = нечитаемый бандл = весь бакет
                // стабится в отчёте). Событийный страж слепнет без событий — глушим его и ждём
                // выхода процесса по файловому прогрессу; убиваем только вставших/переживших cap.
                testRunnerStream.streamReadingAborted()

                if let strongSelf = self {
                    RunnerProcessProgressWaiter(
                        logger: logger,
                        maximumSilenceDuration: testTimeoutConfiguration.testRunnerMaximumSilenceDuration,
                        hardCap: testTimeoutConfiguration.bucketShutdownHardCap
                    ).waitForExit(
                        isProcessRunning: { sender.isProcessRunning },
                        progressMarker: { FileActivityMarker.marker(paths: [resultStreamFile, xcresultBundlePath]) },
                        killProcess: {
                            sender.interruptAndForceKillIfNeeded()
                            sender.waitForProcessToDie()
                        }
                    )
                    strongSelf.readResultBundle(
                        path: xcresultBundlePath,
                        testRunnerStream: testRunnerStream
                    )
                }

                testRunnerStream.closeStream()
            }
        }
        processController.onTermination { _, _ in
            observableFileReaderHandler?.cancel()
            resultStream.close()
        }

        // При отмене/завершении прогона нужно принудительно завершить приложения
        // внутри симулятора (app под тестом + UITests-Runner): иначе осиротевший
        // in-sim процесс переживает освобождение сима и конкурирует со следующим
        // bucket'ом. Делегируем выделенному InSimulatorApplicationTerminator.
        let inSimulatorApplicationTerminator = InSimulatorApplicationTerminator(
            processControllerProvider: processControllerProvider,
            resourceLocationResolver: resourceLocationResolver
        )
        let simulatorSetPath = testContext.simulatorPath.removingLastComponent
        let simulatorUdid = testContext.simulatorUdid.value

        return ProcessControllerWrappingTestRunnerInvocation(
            processController: processController,
            logger: logger,
            onCancel: {
                inSimulatorApplicationTerminator.terminateApplications(
                    buildArtifacts: buildArtifacts,
                    simulatorSetPath: simulatorSetPath,
                    simulatorUdid: simulatorUdid,
                    logger: logger
                )
            }
        )
    }

    public func additionalEnvironment(testRunnerWorkingDirectory: AbsolutePath) -> [String: String] {
        return [
            XcodebuildTestRunnerConstants.envXcresultPath: xcresultBundlePath(testRunnerWorkingDirectory: testRunnerWorkingDirectory).pathString
        ]
    }

    private func xcresultBundlePath(testRunnerWorkingDirectory: AbsolutePath) -> AbsolutePath {
        return testRunnerWorkingDirectory.appending("resultBundle.xcresult")
    }
    
    private func readResultBundle(
        path: AbsolutePath,
        testRunnerStream: TestRunnerStream
    ) {
        do {
            let actionsInvocationRecord = try xcResultTool.get(path: path)
            actionsInvocationRecord.issues.testFailureSummaries?.values.forEach{ (testFailureIssueSummary: RSTestFailureIssueSummary) in
                testRunnerStream.caughtException(
                    testException: testFailureIssueSummary.testException()
                )
            }
        } catch {
            testRunnerStream.caughtException(
                testException: TestException(
                    reason: "Error parsing xcresult bundle: \(error)",
                    filePathInProject: path.pathString,
                    lineNumber: 0,
                    relatedTestName: nil
                )
            )
        }
    }
}
