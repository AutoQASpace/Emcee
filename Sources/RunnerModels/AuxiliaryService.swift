import Foundation

public struct AuxiliaryService: Codable, Hashable {
    public let key: String        // identifier, [a-z][a-z0-9_]* convention
    public let port: UInt16
    public let binary: String?    // optional binary filename; if nil, use key

    public init(key: String, port: UInt16, binary: String? = nil) {
        self.key = key
        self.port = port
        self.binary = binary
    }

    public var effectiveBinaryName: String { binary ?? key }
}
