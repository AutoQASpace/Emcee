import Foundation
import Models

public enum RequestType: String, Codable {
    case registerWorker
    case bucketFetch
    case bucketResult
    case reportAlive
}

public final class RegisterWorkerRequest: Codable {
    public let requestType = RequestType.registerWorker
    public let workerId: String
    
    public init(workerId: String) {
        self.workerId = workerId
    }
}

public final class BucketFetchRequest: Codable {
    public let requestType = RequestType.bucketFetch
    public let workerId: String
    public let requestId: String
    
    public init(workerId: String, requestId: String) {
        self.workerId = workerId
        self.requestId = requestId
    }
}

public final class BucketResultRequest: Codable {
    public let requestType = RequestType.bucketResult
    public let workerId: String
    public let requestId: String
    public let bucketResult: BucketResult
    
    public init(workerId: String, requestId: String, bucketResult: BucketResult) {
        self.workerId = workerId
        self.requestId = requestId
        self.bucketResult = bucketResult
    }
}

public final class ReportAliveRequest: Codable {
    public let requestType = RequestType.reportAlive
    public let workerId: String
    
    public init(workerId: String) {
        self.workerId = workerId
    }
}