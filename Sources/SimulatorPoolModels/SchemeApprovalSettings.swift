public struct SchemeApprovalSettings: Codable, CustomStringConvertible, Hashable {
    public struct Approval: Codable, CustomStringConvertible, Hashable {
        public let scheme: String
        public let bundleId: String

        public init(scheme: String, bundleId: String) {
            self.scheme = scheme
            self.bundleId = bundleId
        }

        public var description: String {
            return "<\(type(of: self)) \(scheme) → \(bundleId)>"
        }
    }

    public let approvals: [Approval]

    public init(approvals: [Approval]) {
        self.approvals = approvals
    }

    public var description: String {
        return "<\(type(of: self)) approvals: \(approvals)>"
    }
}
