@testable import TestDiscovery
import BuildArtifacts
import BuildArtifactsTestHelpers
import CommonTestModels
import CommonTestModelsTestHelpers
import DateProvider
import DeveloperDirLocator
import FileSystem
import Foundation
import MetricsExtensions
import ProcessController
import ProcessControllerTestHelpers
import ResourceLocationResolverTestHelpers
import SimulatorPoolTestHelpers
import TestHelpers
import Tmp
import XCTest
import AppleTestModelsTestHelpers

final class ParseFunctionSymbolsTestDiscovererTests: XCTestCase {
    func test___empty_test_bundle___discovers_no_tests() {
        let discoverer = createParseFunctionSymbolsTestDiscoverer()
        let discoveredTestEntries = assertDoesNotThrow {
            try discoverer.discoverTestEntries(configuration: configuration)
        }
        XCTAssertEqual(discoveredTestEntries, [])
    }
    
    func test___not_empty_test_bundle___discovers_tests() {
        let discoverer = createParseFunctionSymbolsTestDiscoverer(
            nmOutputData: Data(parseFunctionSymbolsTestData.joined(separator: "\n").utf8)
        )
        let discoveredTestEntries = assertDoesNotThrow {
            try discoverer.discoverTestEntries(configuration: configuration)
        }
        XCTAssertEqual(
            discoveredTestEntries,
            expectedDiscoveredTestEnries
        )
    }
    
    private func createParseFunctionSymbolsTestDiscoverer(
        nmOutputData: Data? = nil
    ) -> ParseFunctionSymbolsTestDiscoverer {
        assertDoesNotThrow {
            let plistContents: [String: Any] = [
                "CFBundleExecutable": executableInsideTestBundle
            ]
            _ = try tempFolder.createFile(
                components: [testBundlePathInTempFolder.lastComponent],
                filename: "Info.plist",
                contents: try PropertyListSerialization.data(fromPropertyList: plistContents, format: .binary, options: 0)
            )
        }
        
        return ParseFunctionSymbolsTestDiscoverer(
            developerDirLocator: DefaultDeveloperDirLocator(
                processControllerProvider: DefaultProcessControllerProvider(
                    dateProvider: SystemDateProvider(),
                    filePropertiesProvider: FilePropertiesProviderImpl()
                )
            ),
            logger: .noOp,
            processControllerProvider: FakeProcessControllerProvider { subprocess -> ProcessController in
                XCTAssertEqual(
                    try subprocess.arguments.map { try $0.stringValue() },
                    ["/usr/bin/nm", "-j", "-U", self.testBundlePathInTempFolder.appending(self.executableInsideTestBundle).pathString]
                )
                
                let processController = FakeProcessController(subprocess: subprocess)
                processController.onStart { _, unsubscribe in
                    processController.broadcastStdout(data: nmOutputData ?? Data())
                    processController.overridedProcessStatus = .terminated(exitCode: 0)
                    unsubscribe()
                }
                processController.overridedProcessStatus = .terminated(exitCode: 0)
                return processController
            },
            resourceLocationResolver: FakeResourceLocationResolver.resolvingTo(path: testBundlePathInTempFolder)
        )
    }
    
    private let executableInsideTestBundle = "ExecutableInsideTestBundle"
    private lazy var tempFolder: TemporaryFolder = assertDoesNotThrow { try TemporaryFolder() }
    private lazy var testBundlePathInTempFolder = tempFolder.absolutePath.appending("bundle.xctest")
    private lazy var testBundleLocation = TestBundleLocation(.localFilePath(testBundlePathInTempFolder.pathString))
    private lazy var configuration = AppleTestDiscoveryConfiguration(
        analyticsConfiguration: AnalyticsConfiguration(),
        remoteCache: NoOpRuntimeDumpRemoteCache(),
        testsToValidate: [],
        testDiscoveryMode: .parseFunctionSymbols,
        testConfiguration: AppleTestConfigurationFixture()
            .with(
                buildArtifacts: AppleBuildArtifactsFixture()
                    .logicTests(
                        xcTestBundle: XcTestBundle(
                            location: testBundleLocation,
                            testDiscoveryMode: .parseFunctionSymbols
                        )
                    )
                    .appleBuildArtifacts()
            )
            .appleTestConfiguration()
    )
}
