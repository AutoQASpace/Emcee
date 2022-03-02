import BuildArtifacts
import Foundation
import TestArgFile
import TestDiscovery

public enum TestDicoveryModeInputValidationError: Error, CustomStringConvertible {
    case missingAppBundleToPerformApplicationTestRuntimeDump(XcTestBundle)
    case missingAppBundleToPerformExecutableLaunchDump(XcTestBundle)
    
    public var description: String {
        switch self {
        case .missingAppBundleToPerformApplicationTestRuntimeDump(let xcTestBundle):
            return "Cannot perform runtime dump in application test mode: test bundle \(xcTestBundle) requires application bundle to be provided, but build artifacts do not contain location of app bundle"
        case .missingAppBundleToPerformExecutableLaunchDump(let xcTestBundle):
            return "App bundle with a dumping capability is needed to perform a dump from the test bundle \(xcTestBundle) in the executable launch mode, but build artifacts do not contain location of the app bundle"
        }
    }
}

public final class TestDiscoveryModeDeterminer {
    public static func testDiscoveryMode(testArgFileEntry: TestArgFileEntry) throws -> AppleTestDiscoveryMode {
        switch testArgFileEntry.buildArtifacts.xcTestBundle.testDiscoveryMode {
        case .parseFunctionSymbols:
            return .parseFunctionSymbols
            
        case .runtimeExecutableLaunch:
            switch testArgFileEntry.buildArtifacts {
            case .iosLogicTests:
                throw TestDicoveryModeInputValidationError.missingAppBundleToPerformApplicationTestRuntimeDump(testArgFileEntry.buildArtifacts.xcTestBundle)
            case .iosApplicationTests(_, let appBundle):
                return .runtimeExecutableLaunch(appBundle)
            case .iosUiTests(_, let appBundle, _, _):
                return .runtimeExecutableLaunch(appBundle)
            }
            
        case .runtimeLogicTest:
            return .runtimeLogicTest
            
        case .runtimeAppTest:
            switch testArgFileEntry.buildArtifacts {
            case .iosLogicTests:
                throw TestDicoveryModeInputValidationError.missingAppBundleToPerformApplicationTestRuntimeDump(testArgFileEntry.buildArtifacts.xcTestBundle)
            case .iosApplicationTests(_, let appBundle):
                return .runtimeAppTest(
                    RuntimeDumpApplicationTestSupport(
                        appBundle: appBundle
                    )
                )
            case .iosUiTests(_, let appBundle, _, _):
                return .runtimeAppTest(
                    RuntimeDumpApplicationTestSupport(
                        appBundle: appBundle
                    )
                )
            }
        }
    }
}
