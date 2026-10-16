import Foundation

public struct AutoKickstartSilentWorkersConfiguration: Codable, Equatable {
    public let enabled: Bool
    public let silenceThreshold: TimeInterval
    public let maxAttemptsPerWorker: Int
    public let cooldown: TimeInterval

    public init(enabled: Bool, silenceThreshold: TimeInterval, maxAttemptsPerWorker: Int, cooldown: TimeInterval) {
        self.enabled = enabled
        self.silenceThreshold = silenceThreshold
        self.maxAttemptsPerWorker = maxAttemptsPerWorker
        self.cooldown = cooldown
    }

    public static let defaultSilenceThreshold: TimeInterval = 300
    public static let defaultMaxAttemptsPerWorker = 2
    public static let defaultCooldown: TimeInterval = 120

    private enum CodingKeys: String, CodingKey {
        case enabled
        case silenceThreshold
        case maxAttemptsPerWorker
        case cooldown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            silenceThreshold: try container.decodeIfPresent(TimeInterval.self, forKey: .silenceThreshold) ?? Self.defaultSilenceThreshold,
            maxAttemptsPerWorker: try container.decodeIfPresent(Int.self, forKey: .maxAttemptsPerWorker) ?? Self.defaultMaxAttemptsPerWorker,
            cooldown: try container.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? Self.defaultCooldown
        )
    }
}
