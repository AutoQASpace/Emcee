import Dispatch
import Foundation
import Models
import QueueModels
import Types

public protocol BucketResultSender {
    func send(
        testingResult: TestingResult,
        requestId: RequestId,
        workerId: WorkerId,
        payloadSignature: PayloadSignature,
        callbackQueue: DispatchQueue,
        completion: @escaping (Either<BucketId, Error>) -> ()
    )
}
