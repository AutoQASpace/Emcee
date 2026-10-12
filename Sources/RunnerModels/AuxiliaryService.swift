import Foundation
import ResourceLocation

public struct AuxiliaryService: Codable, Hashable {
    public let key: String        // identifier, [a-z][a-z0-9_]* convention
    public let port: UInt16
    public let binary: String?    // optional binary filename; if nil, use key
    /// Where the worker fetches the binary from, e.g. "https://…/deeplink_bridge.zip#deeplink_bridge".
    /// Resolved through ResourceLocationResolver (worker URL cache), same as plugins and app bundles.
    public let location: ResourceLocation?

    public init(key: String, port: UInt16, binary: String? = nil, location: ResourceLocation? = nil) {
        self.key = key
        self.port = port
        self.binary = binary
        self.location = location
    }

    public var effectiveBinaryName: String { binary ?? key }
}
