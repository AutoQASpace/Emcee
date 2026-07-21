import Foundation

public struct RSDocumentLocation: RSTypedValue, Codable, Equatable {
    public static let typeName = "DocumentLocation"
    
    public let concreteTypeName: RSString
    // Xcode 26.1 в событии issueEmitted у documentLocationInCreatingWorkspace
    // ключ "url" не отдаёт — поэтому опционально, иначе декодер бросает
    // "key url not found" и reason падения теряется.
    public let url: RSString?

    public init(
        concreteTypeName: RSString,
        url: RSString?
    ) {
        self.concreteTypeName = concreteTypeName
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        try Self.validateRsType(decoder: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        concreteTypeName = try container.decode(RSString.self, forKey: .concreteTypeName)
        url = try container.decodeIfPresent(RSString.self, forKey: .url)
    }
}
