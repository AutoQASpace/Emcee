import Foundation
import QueueServerConfiguration
import XCTest

final class AutoKickstartSilentWorkersConfigurationTests: XCTestCase {
    func test___config_without_block___has_no_auto_kickstart() throws {
        let config = try decode(block: nil)

        XCTAssertNil(config.autoKickstartSilentWorkers)
    }

    func test___block_with_enabled_only___uses_defaults() throws {
        let config = try decode(block: #"{"enabled": true}"#)

        XCTAssertEqual(
            config.autoKickstartSilentWorkers,
            AutoKickstartSilentWorkersConfiguration(enabled: true, silenceThreshold: 300, maxAttemptsPerWorker: 2, cooldown: 120)
        )
    }

    func test___full_block___parsed() throws {
        let config = try decode(block: #"{"enabled": false, "silenceThreshold": 600, "maxAttemptsPerWorker": 3, "cooldown": 60}"#)

        XCTAssertEqual(
            config.autoKickstartSilentWorkers,
            AutoKickstartSilentWorkersConfiguration(enabled: false, silenceThreshold: 600, maxAttemptsPerWorker: 3, cooldown: 60)
        )
    }

    func test___block___survives_encoding_for_queue_host() throws {
        // Клиент пересериализует конфиг и отправляет его на хост очереди (RemoteQueueStarter).
        let config = try decode(block: #"{"enabled": true, "silenceThreshold": 600}"#)

        let reencoded = try JSONDecoder().decode(
            QueueServerConfiguration.self,
            from: try JSONEncoder().encode(config)
        )

        XCTAssertEqual(
            reencoded.autoKickstartSilentWorkers,
            AutoKickstartSilentWorkersConfiguration(enabled: true, silenceThreshold: 600, maxAttemptsPerWorker: 2, cooldown: 120)
        )
    }

    func test___enabled_block___is_effective() throws {
        let config = try decode(block: #"{"enabled": true}"#)

        XCTAssertEqual(
            config.enabledAutoKickstartSilentWorkers,
            AutoKickstartSilentWorkersConfiguration(enabled: true, silenceThreshold: 300, maxAttemptsPerWorker: 2, cooldown: 120)
        )
    }

    func test___disabled_block___is_not_effective() throws {
        let config = try decode(block: #"{"enabled": false, "silenceThreshold": 600}"#)

        XCTAssertNil(config.enabledAutoKickstartSilentWorkers)
    }

    func test___block_without_enabled___is_not_effective() throws {
        let config = try decode(block: #"{"silenceThreshold": 600}"#)

        XCTAssertNil(config.enabledAutoKickstartSilentWorkers)
    }

    private func decode(block: String?) throws -> QueueServerConfiguration {
        let blockLine = block.map { #""autoKickstartSilentWorkers": \#($0),"# } ?? ""
        let json = """
            {
              \(blockLine)
              "queueServerDeploymentDestinations": [{
                "host": "queue", "port": 22, "username": "user",
                "authentication": {"password": "pass"}, "remoteDeploymentPath": "/queue"
              }],
              "workerDeploymentDestinations": [{
                "host": "worker", "port": 22, "username": "user",
                "authentication": {"password": "pass"}, "remoteDeploymentPath": "/worker"
              }]
            }
            """
        return try JSONDecoder().decode(QueueServerConfiguration.self, from: Data(json.utf8))
    }
}
