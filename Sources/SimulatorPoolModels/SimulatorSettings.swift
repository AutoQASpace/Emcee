import Foundation

public struct SimulatorSettings: Codable, Hashable, CustomStringConvertible {
    public let simulatorLocalizationSettings: SimulatorLocalizationSettings
    public let simulatorKeychainSettings: SimulatorKeychainSettings
    public let watchdogSettings: WatchdogSettings
    public let schemeApprovalSettings: SchemeApprovalSettings

    public init(
        simulatorLocalizationSettings: SimulatorLocalizationSettings,
        simulatorKeychainSettings: SimulatorKeychainSettings,
        watchdogSettings: WatchdogSettings,
        schemeApprovalSettings: SchemeApprovalSettings = SchemeApprovalSettings(approvals: [])
    ) {
        self.simulatorLocalizationSettings = simulatorLocalizationSettings
        self.simulatorKeychainSettings = simulatorKeychainSettings
        self.watchdogSettings = watchdogSettings
        self.schemeApprovalSettings = schemeApprovalSettings
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case simulatorLocalizationSettings
        case simulatorKeychainSettings
        case watchdogSettings
        case schemeApprovalSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.simulatorLocalizationSettings = try container.decode(SimulatorLocalizationSettings.self, forKey: .simulatorLocalizationSettings)
        self.simulatorKeychainSettings = try container.decodeIfPresent(SimulatorKeychainSettings.self, forKey: .simulatorKeychainSettings)
            ?? SimulatorKeychainSettings(rootCerts: [])
        self.watchdogSettings = try container.decode(WatchdogSettings.self, forKey: .watchdogSettings)
        self.schemeApprovalSettings = try container.decodeIfPresent(SchemeApprovalSettings.self, forKey: .schemeApprovalSettings)
            ?? SchemeApprovalSettings(approvals: [])
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        return "<\((type(of: self))): simulatorLocalizationSettings: \(simulatorLocalizationSettings), simulatorKeychainSettings: \(simulatorKeychainSettings), watchdogSettings: \(watchdogSettings), schemeApprovalSettings: \(schemeApprovalSettings)>"
    }
}
