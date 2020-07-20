import BalancingBucketQueue
import Foundation
import Models
import ModelsTestHelpers
import QueueModels
import QueueServer
import RESTMethods
import RunnerModels
import XCTest

final class JobResultsEndpointTests: XCTestCase, JobResultsProvider {
    private struct Throwable: Error {}
    private let jobId: JobId = "jobid"
    private lazy var jobResults = JobResults(
        jobId: jobId,
        testingResults: [TestingResult(
            bucketId: "bucketid",
            testDestination: TestDestinationFixtures.testDestination,
            unfilteredResults: [TestEntryResult.lost(testEntry: TestEntryFixtures.testEntry())]
            )
        ]
    )
    
    func test___indicates_activity() {
        let endpoint = JobResultsEndpoint(jobResultsProvider: self)
        
        XCTAssertTrue(
            endpoint.requestIndicatesActivity,
            "This endpoint should indicate activity because it indicates queue is being used by the user"
        )
    }
    
    func results(jobId: JobId) throws -> JobResults {
        guard jobId == self.jobId else { throw Throwable() }
        return jobResults
    }
    
    func test___requesting_job_results_for_existing_job() throws {
        let endpoint = JobResultsEndpoint(jobResultsProvider: self)
        let response = try endpoint.handle(payload: JobResultsRequest(jobId: jobId))
        XCTAssertEqual(response.jobResults, jobResults)
    }
    
    func test___request_state_for_non_existing_job() {
        let endpoint = JobResultsEndpoint(jobResultsProvider: self)
        XCTAssertThrowsError(try endpoint.handle(payload: JobResultsRequest(jobId: "invalid job id")))
    }
}

