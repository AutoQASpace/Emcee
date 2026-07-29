import BuildArtifacts
import Foundation
import EmceeLogging
import PathLib
import ProcessController
import ResourceLocation
import ResourceLocationResolver
import Runner
import RunnerModels

public final class XcTestRunFileArgument: SubprocessArgument, CustomStringConvertible {
    private let buildArtifacts: IosBuildArtifacts
    private let entriesToRun: [TestEntry]
    private let path: AbsolutePath
    private let resourceLocationResolver: ResourceLocationResolver
    private let testContext: TestContext
    private let testingEnvironment: XcTestRunTestingEnvironment
    private let singleTestMaximumDuration: TimeInterval

    public enum XcTestRunFileArgumentError: CustomStringConvertible, Error {
        case cannotObtainBundleIdentifier(path: AbsolutePath)
        
        public var description: String {
            switch self {
            case .cannotObtainBundleIdentifier(let path):
                return "Cannot obtain bundle id for bundle at path: '\(path)'"
            }
        }
    }

    public init(
        buildArtifacts: IosBuildArtifacts,
        entriesToRun: [TestEntry],
        path: AbsolutePath,
        resourceLocationResolver: ResourceLocationResolver,
        testContext: TestContext,
        testingEnvironment: XcTestRunTestingEnvironment,
        singleTestMaximumDuration: TimeInterval
    ) {
        self.buildArtifacts = buildArtifacts
        self.entriesToRun = entriesToRun
        self.path = path
        self.resourceLocationResolver = resourceLocationResolver
        self.testContext = testContext
        self.testingEnvironment = testingEnvironment
        self.singleTestMaximumDuration = singleTestMaximumDuration
    }
    
    public var description: String {
        "<\(type(of: self)) tests: \(entriesToRun.map { $0.testName }), environment \(testContext.environment), path: \(path)>"
    }

    public func stringValue() throws -> String {
        let xcTestRun = try createXcTestRun()
        let xcTestRunPlist = XcTestRunPlist(xcTestRun: xcTestRun)
        try xcTestRunPlist.createPlistData().write(
            to: path.fileUrl,
            options: .atomic
        )
        return path.pathString
    }

    private func createXcTestRun() throws -> XcTestRun {
        switch buildArtifacts {
        case .iosLogicTests(let xcTestBundle):
            return try xcTestRunForLogicTesting(
                resolvableXcTestBundle: resourceLocationResolver.resolvable(withRepresentable: xcTestBundle.location)
            )
        case .iosApplicationTests(let xcTestBundle, let appBundle):
            return try xcTestRunForApplicationTesting(
                resolvableXcTestBundle: resourceLocationResolver.resolvable(withRepresentable: xcTestBundle.location),
                resolvableAppBundle: resourceLocationResolver.resolvable(withRepresentable: appBundle)
            )
        case .iosUiTests(let xcTestBundle, let appBundle, let runner, let additionalApps):
            return try xcTestRunForUiTesting(
                resolvableXcTestBundle: resourceLocationResolver.resolvable(withRepresentable: xcTestBundle.location),
                resolvableAppBundle: resourceLocationResolver.resolvable(withRepresentable: appBundle),
                resolvableRunnerBundle: resourceLocationResolver.resolvable(withRepresentable: runner),
                resolvableAdditionalAppBundles: additionalApps.map { resourceLocationResolver.resolvable(withRepresentable: $0) }
            )
        }
    }

    private func xcTestRunForLogicTesting(
        resolvableXcTestBundle: ResolvableResourceLocation
    ) throws -> XcTestRun {
        let testBundlePath = try resolvableXcTestBundle.resolve().directlyAccessibleResourcePath()
        let testHostPath = "__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"
        
        let insertedLibraries = testingEnvironment.insertedLibraries + [
            "__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib/libXCTestBundleInject.dylib"
        ]
        
        let xctestSpecificEnvironment = [
            "DYLD_INSERT_LIBRARIES": insertedLibraries.joined(separator: ":"),
            "XCInjectBundleInto": testHostPath,
        ]
        let testTargetProductModuleName = try self.testTargetProductModuleName(
            xcTestBundlePath: testBundlePath
        )
        
        return XcTestRun(
            testTargetName: testTargetProductModuleName,
            bundleIdentifiersForCrashReportEmphasis: [],
            dependentProductPaths: [
                testBundlePath.pathString,
            ],
            testBundlePath: testBundlePath.pathString,
            testHostPath: testHostPath,
            testHostBundleIdentifier: "com.apple.dt.xctest.tool",
            uiTargetAppPath: nil,
            environmentVariables: testContext.environment,
            commandLineArguments: [],
            uiTargetAppEnvironmentVariables: testContext.environment,
            uiTargetAppCommandLineArguments: [],
            uiTargetAppMainThreadCheckerEnabled: false,
            skipTestIdentifiers: [],
            onlyTestIdentifiers: entriesToRun.map { $0.testName.stringValue },
            testingEnvironmentVariables: xctestSpecificEnvironment.byMergingWith(testContext.environment),
            isUITestBundle: false,
            isAppHostedTestBundle: false,
            isXCTRunnerHostedTestBundle: false,
            testTargetProductModuleName: testTargetProductModuleName,
            systemAttachmentLifetime: .deleteOnSuccess,
            userAttachmentLifetime: .deleteOnSuccess
        )
    }

    private func xcTestRunForApplicationTesting(
        resolvableXcTestBundle: ResolvableResourceLocation,
        resolvableAppBundle: ResolvableResourceLocation
    ) throws -> XcTestRun {
        let hostAppPath = try resourceLocationResolver.resolvable(resourceLocation: resolvableAppBundle.resourceLocation).resolve().directlyAccessibleResourcePath()
        let testBundlePath = try resolvableXcTestBundle.resolve().directlyAccessibleResourcePath()
        let testTargetProductModuleName = try self.testTargetProductModuleName(
            xcTestBundlePath: testBundlePath
        )

        guard let hostAppBundle = Bundle(path: hostAppPath.pathString), let hostAppBundleIdentifier = hostAppBundle.bundleIdentifier else {
            throw XcTestRunFileArgumentError.cannotObtainBundleIdentifier(path: hostAppPath)
        }
        
        let insertedLibraries = testingEnvironment.insertedLibraries + [
            "__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib/libXCTestBundleInject.dylib"
        ]
            
        let xctestSpecificEnvironment = [
            "DYLD_INSERT_LIBRARIES": insertedLibraries.joined(separator: ":"),
            "XCInjectBundleInto": hostAppPath.pathString,
        ]

        return XcTestRun(
            testTargetName: testTargetProductModuleName,
            bundleIdentifiersForCrashReportEmphasis: [],
            dependentProductPaths: [
                hostAppPath.pathString,
                testBundlePath.pathString,
            ],
            testBundlePath: testBundlePath.pathString,
            testHostPath: hostAppPath.pathString,
            testHostBundleIdentifier: hostAppBundleIdentifier,
            uiTargetAppPath: nil,
            environmentVariables: testContext.environment,
            commandLineArguments: [],
            uiTargetAppEnvironmentVariables: testContext.environment,
            uiTargetAppCommandLineArguments: [],
            uiTargetAppMainThreadCheckerEnabled: false,
            skipTestIdentifiers: [],
            onlyTestIdentifiers: entriesToRun.map { $0.testName.stringValue },
            testingEnvironmentVariables: xctestSpecificEnvironment.byMergingWith(testContext.environment),
            isUITestBundle: false,
            isAppHostedTestBundle: true,
            isXCTRunnerHostedTestBundle: false,
            testTargetProductModuleName: testTargetProductModuleName,
            systemAttachmentLifetime: .deleteOnSuccess,
            userAttachmentLifetime: .deleteOnSuccess
        )
    }

    private func xcTestRunForUiTesting(
        resolvableXcTestBundle: ResolvableResourceLocation,
        resolvableAppBundle: ResolvableResourceLocation,
        resolvableRunnerBundle: ResolvableResourceLocation,
        resolvableAdditionalAppBundles: [ResolvableResourceLocation]
    ) throws -> XcTestRun {
        let uiTargetAppPath = try resourceLocationResolver.resolvable(resourceLocation: resolvableAppBundle.resourceLocation).resolve().directlyAccessibleResourcePath()
        let hostAppPath = try resourceLocationResolver.resolvable(resourceLocation: resolvableRunnerBundle.resourceLocation).resolve().directlyAccessibleResourcePath()
        let testBundlePath = try resolvableXcTestBundle.resolve().directlyAccessibleResourcePath()
        let additionalApplicationBundlePaths: [AbsolutePath] = try resolvableAdditionalAppBundles.map {
            try resourceLocationResolver.resolvable(resourceLocation: $0.resourceLocation).resolve().directlyAccessibleResourcePath()
        }
        let testTargetProductModuleName = try self.testTargetProductModuleName(
            xcTestBundlePath: testBundlePath
        )
        
        var testingEnvironmentVariables = [
            "DYLD_FRAMEWORK_PATH": "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
            "DYLD_LIBRARY_PATH": "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks"
        ]
        if !testingEnvironment.insertedLibraries.isEmpty {
            testingEnvironmentVariables["DYLD_INSERT_LIBRARIES"] = testingEnvironment.insertedLibraries.joined(separator: ":")
        }

        return XcTestRun(
            testTargetName: testTargetProductModuleName,
            bundleIdentifiersForCrashReportEmphasis: [],
            dependentProductPaths: ([uiTargetAppPath, testBundlePath, hostAppPath] + additionalApplicationBundlePaths).map { $0.pathString },
            testBundlePath: testBundlePath.pathString,
            testHostPath: hostAppPath.pathString,
            testHostBundleIdentifier: "StubBundleId",
            uiTargetAppPath: uiTargetAppPath.pathString,
            environmentVariables: testContext.environment,
            commandLineArguments: [],
            uiTargetAppEnvironmentVariables: testContext.environment,
            uiTargetAppCommandLineArguments: [],
            uiTargetAppMainThreadCheckerEnabled: false,
            skipTestIdentifiers: [],
            onlyTestIdentifiers: entriesToRun.map { $0.testName.stringValue },
            testingEnvironmentVariables: testingEnvironmentVariables,
            isUITestBundle: true,
            isAppHostedTestBundle: false,
            isXCTRunnerHostedTestBundle: true,
            testTargetProductModuleName: testTargetProductModuleName,
            systemAttachmentLifetime: .deleteOnSuccess,
            userAttachmentLifetime: .deleteOnSuccess,
            preferredScreenCaptureFormat: preferredScreenCaptureFormat(),
            testTimeouts: testTimeouts()
        )
    }

    /// Unified video recording scheme (shared with EmceeReportPlugin):
    ///   VIDEO_RECORDER: off | plugin | native — "native" makes Xcode record test video into xcresult
    ///   VIDEO_ONLY_ON_RETRY: true — record only retry attempts (EMCEE_TEST_IS_RETRY is injected by the queue on reenqueue)
    /// Legacy fallback when VIDEO_RECORDER is absent: NATIVE_VIDEO_CAPTURE / RECORD_VIDEO_ONLY_ON_RETRY.
    ///
    /// The key is ALWAYS written. An absent key is NOT "no capture": Xcode's default is screen
    /// RECORDING on runtimes that support it (18.6+; field-proven 2026-07-29 — kXCTAttachmentScreenRecording
    /// mp4s appeared for failed first-run tests with no key at all), which burns the video encoder
    /// on every test on GPU-less VMs. Explicit SCREENSHOTS is the cheap off-state.
    private func preferredScreenCaptureFormat() -> XcTestRunScreenCaptureFormat {
        let environment = testContext.environment
        let nativeEnabled: Bool
        switch environment["VIDEO_RECORDER"] {
        case "native": nativeEnabled = true
        case "off", "plugin": nativeEnabled = false
        default: nativeEnabled = environment["NATIVE_VIDEO_CAPTURE"] == "true"
        }
        guard nativeEnabled else { return .screenshots }

        let onlyOnRetry = (environment["VIDEO_ONLY_ON_RETRY"] ?? environment["RECORD_VIDEO_ONLY_ON_RETRY"] ?? "false") == "true"
        if onlyOnRetry && environment["EMCEE_TEST_IS_RETRY"] != "true" {
            return .screenshots
        }
        return .screenRecording
    }

    /// Native XCTest per-test timeouts — the primary defense against a test hanging forever
    /// (unbounded loop in test code with a responsive app: neither the simulator watchdog nor
    /// the silence tracker catches it). XCTest fails such a test with a readable
    /// "exceeded execution time allowance" verdict (plus a spindump attachment) and continues
    /// running the remaining tests of the bucket.
    ///
    /// Allowance = singleTestMaximumDuration, rounded UP by Apple to a full minute (270 → 300),
    /// so it fires AFTER Emcee's own long-running-test detection at singleTestMaximumDuration
    /// and BEFORE the in-simulator terminate fallback (see Runner). Kill-switch:
    /// NATIVE_TEST_TIMEOUTS=false in the test environment.
    private func testTimeouts() -> XcTestRunTestTimeouts? {
        guard testContext.environment["NATIVE_TEST_TIMEOUTS"] != "false" else { return nil }
        let defaultAllowance = Int(singleTestMaximumDuration.rounded(.up))
        return XcTestRunTestTimeouts(
            defaultExecutionTimeAllowance: defaultAllowance,
            maximumExecutionTimeAllowance: defaultAllowance * 2
        )
    }
    
    private func testTargetProductModuleName(
        xcTestBundlePath: AbsolutePath
    ) throws -> String {
        let plistPath = xcTestBundlePath.appending("Info.plist")
        let plistContents = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistPath.fileUrl, options: .mappedIfSafe),
            options: [],
            format: nil
        )
        guard let plistDict = plistContents as? NSDictionary else {
            throw InfoPlistError.failedToReadPlistContents(path: plistPath, contents: plistContents)
        }
        guard let bundleName = plistDict["CFBundleName"] as? String else {
            throw InfoPlistError.noValueCFBundleName(path: plistPath)
        }
        return suitableModuleName(name: bundleName)
    }
    
    private func suitableModuleName(name: String) -> String {
        return name
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
