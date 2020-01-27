import RequestSender

public final class RegisterWorkerRequest: NetworkRequest {
    public typealias Response = RegisterWorkerResponse

    public let httpMethod = HTTPMethod.post
    public let pathWithLeadingSlash = RESTMethod.registerWorker.withPrependingSlash

    public let payload: RegisterWorkerPayload?
    public init(payload: RegisterWorkerPayload) {
        self.payload = payload
    }
}
