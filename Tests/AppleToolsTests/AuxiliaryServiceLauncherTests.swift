@testable import AppleTools
import Darwin
import Foundation
import PathLib
import ProcessController
import ProcessControllerTestHelpers
import ResourceLocation
import ResourceLocationResolverTestHelpers
import RunnerModels
import XCTest

final class AuxiliaryServiceLauncherTests: XCTestCase {
    private let cachedBinary = AbsolutePath("/cache/abc/zip_contents/deeplink_bridge")
    private let oldBinary = "/Users/jenkins/emcee/16.0.16/auxiliary_deeplink_bridge/auxiliary/deeplink_bridge"
    private lazy var service = AuxiliaryService(
        key: "bridge",
        port: 8765,
        binary: "deeplink_bridge",
        location: .remoteUrl(URL(string: "https://user:secret@example.com/deeplink_bridge.zip#deeplink_bridge")!, nil)
    )

    // MARK: - Decision

    func test___free_port___start() {
        XCTAssertEqual(decide(owner: nil), .start)
    }

    func test___same_binary___keep_running() {
        XCTAssertEqual(decide(owner: .init(pid: 10, executablePath: cachedBinary.pathString)), .keepRunning(pid: 10))
    }

    func test___other_build_of_same_service___replace() {
        XCTAssertEqual(
            decide(owner: .init(pid: 10, executablePath: oldBinary)),
            .replace(pid: 10, executablePath: oldBinary)
        )
    }

    func test___other_binary_name___foreign() {
        XCTAssertEqual(
            decide(owner: .init(pid: 10, executablePath: "/usr/bin/python3")),
            .foreignProcess(pid: 10, executablePath: "/usr/bin/python3")
        )
    }

    func test___deleted_binary_with_same_process_name___replace() {
        XCTAssertEqual(
            decide(owner: .init(pid: 10, executablePath: nil, processName: "deeplink_bridge")),
            .replace(pid: 10, executablePath: "<deleted> deeplink_bridge")
        )
    }

    func test___unknown_executable_path___foreign() {
        XCTAssertEqual(decide(owner: .init(pid: 10, executablePath: nil)), .foreignProcess(pid: 10, executablePath: nil))
    }

    // MARK: - Launcher

    func test___free_port___starts_cached_binary() {
        let inspector = FakePortInspector(owner: nil)
        let started = launch(inspector: inspector, onStart: { inspector.owner = .init(pid: 20, executablePath: self.cachedBinary.pathString) })

        XCTAssertEqual(started, [[cachedBinary.pathString]])
        XCTAssertEqual(inspector.signals, [])
    }

    func test___same_binary_running___nothing_started() {
        let inspector = FakePortInspector(owner: .init(pid: 10, executablePath: cachedBinary.pathString))
        let started = launch(inspector: inspector)

        XCTAssertEqual(started, [])
        XCTAssertEqual(inspector.signals, [])
    }

    func test___old_binary_running___terminated_then_new_started() {
        let inspector = FakePortInspector(owner: .init(pid: 10, executablePath: oldBinary))
        inspector.onSignal = { signal, _ in if signal == SIGTERM { inspector.owner = nil } }
        let started = launch(inspector: inspector, onStart: { inspector.owner = .init(pid: 20, executablePath: self.cachedBinary.pathString) })

        XCTAssertEqual(inspector.signals.map(\.signal), [SIGTERM])
        XCTAssertEqual(started, [[cachedBinary.pathString]])
    }

    func test___old_binary_ignores_sigterm___killed_then_new_started() {
        let inspector = FakePortInspector(owner: .init(pid: 10, executablePath: oldBinary))
        inspector.onSignal = { signal, _ in if signal == SIGKILL { inspector.owner = nil } }
        let started = launch(inspector: inspector)

        XCTAssertEqual(inspector.signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertEqual(started, [[cachedBinary.pathString]])
    }

    func test___port_never_released___not_started() {
        let inspector = FakePortInspector(owner: .init(pid: 10, executablePath: oldBinary))
        let started = launch(inspector: inspector)

        XCTAssertEqual(inspector.signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertEqual(started, [])
    }

    func test___foreign_process___not_touched() {
        let inspector = FakePortInspector(owner: .init(pid: 10, executablePath: "/usr/bin/python3"))
        let started = launch(inspector: inspector)

        XCTAssertEqual(inspector.signals, [])
        XCTAssertEqual(started, [])
    }

    func test___no_location___skipped() {
        service = AuxiliaryService(key: "bridge", port: 8765, binary: "deeplink_bridge")
        let inspector = FakePortInspector(owner: nil)
        let started = launch(inspector: inspector)

        XCTAssertEqual(started, [])
    }

    func test___resolve_error___skipped() {
        let inspector = FakePortInspector(owner: nil)
        let started = launch(inspector: inspector, resolver: FakeResourceLocationResolver.throwing())

        XCTAssertEqual(started, [])
    }

    func test___service_decodes_location_from_test_arg_file_string() throws {
        let json = """
        {"location": "https://u:p@example.com/b/deeplink_bridge.zip#deeplink_bridge", "key": "bridge", "port": 8765, "binary": "deeplink_bridge"}
        """
        let decoded = try JSONDecoder().decode(AuxiliaryService.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.location?.url?.fragment, "deeplink_bridge")
        XCTAssertEqual(decoded.port, 8765)
    }

    func test___service_without_location_still_decodes() throws {
        let json = #"{"key": "bridge", "port": 8765, "binary": "deeplink_bridge"}"#
        XCTAssertNil(try JSONDecoder().decode(AuxiliaryService.self, from: Data(json.utf8)).location)
    }

    func test___credentials_redacted() {
        XCTAssertEqual(
            AuxiliaryServiceLauncher.redactingCredentials("failed https://user:secret@example.com/a.zip"),
            "failed https://***@example.com/a.zip"
        )
    }

    // MARK: - Helpers

    private func decide(owner: AuxiliaryServicePortOwner?) -> AuxiliaryServiceLaunchDecision {
        AuxiliaryServiceLaunchDecision.decide(owner: owner, expectedBinaryPath: cachedBinary, binaryName: "deeplink_bridge")
    }

    private func launch(
        inspector: FakePortInspector,
        resolver: FakeResourceLocationResolver? = nil,
        onStart: @escaping () -> () = {}
    ) -> [[String]] {
        var started = [[String]]()
        let provider = FakeProcessControllerProvider { subprocess in
            started.append(try subprocess.arguments.map { try $0.stringValue() })
            onStart()
            return FakeProcessController(subprocess: subprocess)
        }
        let launcher = AuxiliaryServiceLauncher(
            portInspector: inspector,
            portReleaseTimeout: 0.05,
            listenTimeout: 0.05,
            pollInterval: 0.01
        )
        launcher.ensureRunning(
            services: [service],
            resourceLocationResolver: resolver ?? FakeResourceLocationResolver.resolvingTo(path: cachedBinary),
            processControllerProvider: provider,
            logger: .noOp
        )
        return started
    }
}

private final class FakePortInspector: AuxiliaryServicePortInspector {
    struct SentSignal: Equatable {
        let signal: Int32
        let pid: Int32
    }

    var owner: AuxiliaryServicePortOwner?
    var signals = [SentSignal]()
    var onSignal: (Int32, Int32) -> () = { _, _ in }

    init(owner: AuxiliaryServicePortOwner?) {
        self.owner = owner
    }

    func listeningProcess(port: UInt16) -> AuxiliaryServicePortOwner? { owner }

    func sendSignal(_ signal: Int32, pid: Int32) {
        signals.append(SentSignal(signal: signal, pid: pid))
        onSignal(signal, pid)
    }
}
