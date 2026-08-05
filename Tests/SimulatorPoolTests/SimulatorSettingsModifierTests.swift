@testable import SimulatorPool
import DeveloperDirLocatorTestHelpers
import Foundation
import PathLib
import ProcessController
import ProcessControllerTestHelpers
import SimulatorPoolModels
import SimulatorPoolTestHelpers
import Tmp
import TestHelpers
import UniqueIdentifierGenerator
import UniqueIdentifierGeneratorTestHelpers
import XCTest
import ResourceLocationResolverTestHelpers

final class SimulatorSettingsModifierTests: XCTestCase {

    lazy var modifier = SimulatorSettingsModifierImpl(
        developerDirLocator: developerDirLocator,
        processControllerProvider: processControllerProvider,
        tempFolder: tempFolder,
        uniqueIdentifierGenerator: uniqueIdentifierGenerator,
        resourceLocationResolver: resourceLocationResolver
    )

    func test__add_root_certificates() throws {
        let expectation = addChecksForAddingRootCertificatesIntoKeychain()

        try modifier.apply(
            developerDir: .current,
            simulatorSettings: simulatorSettings,
            toSimulator: simulator
        )

        wait(for: [expectation], timeout: 5.0)
    }

    func test___writes_all_domains() throws {
        try applyRecordingInvocations()

        assertPlist(globalPreferencesFileName, contains: expectedGlobalPreferences)
        assertPlist(preferencesFileName, contains: expectedPreferences)
        assertPlist(keyboardPreferencesFileName, contains: expectedKeyboardPreferences)
        assertPlist(springBoardFileName, contains: expectedSpringBoard)
    }

    func test___shuts_simulator_down_before_boot() throws {
        let invocations = try applyRecordingInvocations()

        let shutdownIndex = assertNotNil { invocations.firstIndex(of: expectedShutdownArguments) }
        let bootIndex = assertNotNil { invocations.firstIndex(of: expectedBootArguments) }
        XCTAssertLessThan(shutdownIndex, bootIndex, "Симулятор должен быть погашен до бутa")
    }

    /// Убийство SpringBoard на iOS 18 лишает симулятор способности менять ориентацию до конца
    /// сессии, поэтому настройки применяются на выключенном симуляторе и демонов трогать нельзя.
    func test___never_kills_daemons() throws {
        let invocations = try applyRecordingInvocations()

        XCTAssertFalse(
            invocations.contains { $0.contains("kill") },
            "Ни один демон в симуляторе не должен убиваться"
        )
    }

    func test___when_all_values_are_present___simulator_is_not_restarted() throws {
        try seedPlist(globalPreferencesFileName, contents: expectedGlobalPreferences)
        try seedPlist(preferencesFileName, contents: expectedPreferences)
        try seedPlist(keyboardPreferencesFileName, contents: expectedKeyboardPreferences)
        try seedPlist(springBoardFileName, contents: expectedSpringBoard)

        let invocations = try applyRecordingInvocations()

        XCTAssertFalse(invocations.contains(expectedShutdownArguments))
        XCTAssertFalse(invocations.contains(expectedBootArguments))
    }

    /// iOS на каждом бутe дописывает своё: язык и клавиатуру хоста в хвост списков и собственные
    /// записи в исключения вотчдога. Это не повод применять настройки заново.
    func test___when_system_appended_its_own_values___simulator_is_not_restarted() throws {
        try seedPlist(
            globalPreferencesFileName,
            contents: expectedGlobalPreferences
                .merging(["SomeExtraValueThatSystemAdds": "yes"]) { current, _ in current }
                .merging(["AppleLanguages": ["lang1", "lang2", "ru-RU"]]) { _, new in new }
                .merging(["AppleKeyboards": ["keyboard1", "keyboard2", "ru_RU@sw=Russian"]]) { _, new in new }
        )
        try seedPlist(preferencesFileName, contents: expectedPreferences)
        try seedPlist(keyboardPreferencesFileName, contents: expectedKeyboardPreferences)
        try seedPlist(
            springBoardFileName,
            contents: ["FBLaunchWatchdogExceptions": ["bundle.id.1": 42, "bundle.id.2": 42, "com.apple.Spotlight": 120]]
        )

        let invocations = try applyRecordingInvocations()

        XCTAssertFalse(invocations.contains(expectedShutdownArguments))
        XCTAssertFalse(invocations.contains(expectedBootArguments))
    }

    /// Порядок в списках задаёт приоритет: первым элементом определяются язык приложения и
    /// активная раскладка. Если система влезла перед нашими значениями, настройки надо применить
    /// заново, а не считать их действующими.
    func test___when_system_value_is_inserted_before_ours___settings_are_applied_again() throws {
        try seedPlist(
            globalPreferencesFileName,
            contents: expectedGlobalPreferences
                .merging(["AppleLanguages": ["ru-RU", "lang1", "lang2"]]) { _, new in new }
        )

        let invocations = try applyRecordingInvocations()

        XCTAssertTrue(invocations.contains(expectedShutdownArguments))
        XCTAssertTrue(invocations.contains(expectedBootArguments))
        assertPlist(globalPreferencesFileName, contains: expectedGlobalPreferences)
    }

    func test___write_preserves_values_of_other_keys() throws {
        try seedPlist(
            globalPreferencesFileName,
            contents: ["SomeExtraValueThatSystemAdds": "yes"]
        )

        try applyRecordingInvocations()

        assertPlist(globalPreferencesFileName, contains: ["SomeExtraValueThatSystemAdds": "yes"])
        assertPlist(globalPreferencesFileName, contains: expectedGlobalPreferences)
    }

    /// Записи iOS в исключениях вотчдога должны сохраниться: словари мержатся, а не заменяются.
    func test___write_preserves_system_watchdog_exceptions() throws {
        try seedPlist(
            springBoardFileName,
            contents: ["FBLaunchWatchdogExceptions": ["com.apple.Spotlight": 120]]
        )

        try applyRecordingInvocations()

        let watchdogExceptions = assertNotNil {
            writtenPlist(springBoardFileName)?["FBLaunchWatchdogExceptions"] as? [String: Any]
        }
        XCTAssertEqual(watchdogExceptions["com.apple.Spotlight"] as? Int, 120)
        XCTAssertEqual(watchdogExceptions["bundle.id.1"] as? Int, 42)
        XCTAssertEqual(watchdogExceptions["bundle.id.2"] as? Int, 42)
    }

    func test___DEVELOPER_DIR_is_present_for_all_subprocess_invocations() throws {
        processControllerProvider.creator = { [developerDirLocator] subprocess -> ProcessController in
            XCTAssertEqual(
                subprocess.environment.values["DEVELOPER_DIR"],
                try developerDirLocator.path(developerDir: .current).pathString,
                "DEVELOPER_DIR env must be used when executing xcrun"
            )

            return FakeProcessController(subprocess: subprocess, processStatus: .terminated(exitCode: 0))
        }

        try modifier.apply(
            developerDir: .current,
            simulatorSettings: simulatorSettings,
            toSimulator: simulator
        )
    }

    // MARK: - Helper Methods

    @discardableResult
    private func applyRecordingInvocations() throws -> [[String]] {
        let recorder = InvocationRecorder()

        processControllerProvider.creator = { subprocess -> ProcessController in
            recorder.invocations.append(try subprocess.arguments.map { try $0.stringValue() })
            return FakeProcessController(subprocess: subprocess, processStatus: .terminated(exitCode: 0))
        }

        try modifier.apply(
            developerDir: .current,
            simulatorSettings: simulatorSettings,
            toSimulator: simulator
        )

        return recorder.invocations
    }

    private func preferencesPath(_ fileName: String) -> AbsolutePath {
        simulator.path.appending("data", "Library", "Preferences", fileName)
    }

    private func seedPlist(_ fileName: String, contents: [String: Any]) throws {
        let path = preferencesPath(fileName)
        try FileManager.default.createDirectory(
            at: path.removingLastComponent.fileUrl,
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0)
        try data.write(to: path.fileUrl)
    }

    private func writtenPlist(_ fileName: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: preferencesPath(fileName).fileUrl) else { return nil }
        let contents = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return contents as? [String: Any]
    }

    private func assertPlist(
        _ fileName: String,
        contains expectedEntries: [String: Any],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let actualEntries = assertNotNil(file: file, line: line) { writtenPlist(fileName) }
        expectedEntries.forEach { key, expectedValue in
            XCTAssertEqual(
                actualEntries[key] as? NSObject,
                expectedValue as? NSObject,
                "\(fileName): значение по ключу \(key)",
                file: file,
                line: line
            )
        }
    }

    private func addChecksForAddingRootCertificatesIntoKeychain(
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "'add-root-cert' call expectation")

        processControllerProvider.creator = { subprocess -> ProcessController in
            let args = try subprocess.arguments.map { try $0.stringValue() }

            if args.contains("keychain"), args.contains("add-root-cert") {
                expectation.fulfill()

                XCTAssertEqual(
                    args,
                    ["/usr/bin/xcrun", "simctl", "--set", self.tempFolder.absolutePath.pathString, "keychain", self.simulator.udid.value, "add-root-cert", "/path/to/cert.pem"]
                )
            }

            return FakeProcessController(subprocess: subprocess, processStatus: .terminated(exitCode: 0))
        }

        return expectation
    }

    // MARK: - Helper Types

    private final class InvocationRecorder {
        var invocations: [[String]] = []
    }

    // MARK: - Helper Variables

    lazy var developerDirLocator = FakeDeveloperDirLocator(
        result: self.tempFolder.absolutePath.appending("Dev_Dir")
    )
    lazy var processControllerProvider = FakeProcessControllerProvider()
    lazy var simulator = Simulator(
        testDestination: TestDestinationFixtures.testDestination,
        udid: UDID(value: "sim_udid"),
        path: tempFolder.absolutePath.appending("sim_path")
    )
    lazy var simulatorSettings = SimulatorSettings(
        simulatorLocalizationSettings: SimulatorLocalizationSettings(
            localeIdentifier: "locale_id",
            keyboards: ["keyboard1", "keyboard2"],
            passcodeKeyboards: ["pass1", "pass2"],
            languages: ["lang1", "lang2"],
            addingEmojiKeybordHandled: true,
            enableKeyboardExpansion: true,
            didShowInternationalInfoAlert: true,
            didShowContinuousPathIntroduction: true,
            didShowGestureKeyboardIntroduction: true
        ),
        simulatorKeychainSettings: SimulatorKeychainSettings(
            rootCerts: [
                .init(.remoteUrl(URL(string: "http://example.com/cert.zip#cert.pem")!, nil))
            ]
        ),
        watchdogSettings: WatchdogSettings(
            bundleIds: ["bundle.id.1", "bundle.id.2"],
            timeout: 42
        )
    )
    lazy var tempFolder = assertDoesNotThrow { try TemporaryFolder() }
    lazy var uniqueIdentifierGenerator = FixedValueUniqueIdentifierGenerator(value: "random_value")
    lazy var resourceLocationResolver = FakeResourceLocationResolver(resolvingResult: .directlyAccessibleFile(path: "/path/to/cert.pem"))

    private let globalPreferencesFileName = ".GlobalPreferences.plist"
    private let preferencesFileName = "com.apple.Preferences.plist"
    private let keyboardPreferencesFileName = "com.apple.keyboard.preferences.plist"
    /// Домен SpringBoard пишется строчными — его bundle id `com.apple.springboard`.
    private let springBoardFileName = "com.apple.springboard.plist"

    private lazy var expectedGlobalPreferences: [String: Any] = [
        "AppleLocale": "locale_id",
        "AppleLanguages": ["lang1", "lang2"],
        "AppleKeyboards": ["keyboard1", "keyboard2"],
        "ApplePasscodeKeyboards": ["pass1", "pass2"],
        "AppleKeyboardsExpanded": 1,
        "AddingEmojiKeybordHandled": true,
    ]
    private lazy var expectedPreferences: [String: Any] = [
        "UIKeyboardDidShowInternationalInfoIntroduction": true,
        "DidShowContinuousPathIntroduction": true,
        "DidShowGestureKeyboardIntroduction": true,
    ]
    private lazy var expectedKeyboardPreferences: [String: Any] = [
        "DidShowContinuousPathIntroduction": true,
    ]
    private lazy var expectedSpringBoard: [String: Any] = [
        "FBLaunchWatchdogExceptions": ["bundle.id.1": 42, "bundle.id.2": 42],
    ]
    private lazy var expectedShutdownArguments = [
        "/usr/bin/xcrun", "simctl", "--set", tempFolder.absolutePath.pathString,
        "shutdown", simulator.udid.value,
    ]
    private lazy var expectedBootArguments = [
        "/usr/bin/xcrun", "simctl", "--set", tempFolder.absolutePath.pathString,
        "bootstatus", simulator.udid.value, "-bd",
    ]
}
