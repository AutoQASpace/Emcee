import CommonTestModels
import Foundation
import QueueModels

/// A combination of TestingResult of all Buckets
public struct CombinedTestingResults {
    
    /// All tests that succeded
    public let successfulTests: [TestEntryResult]
    
    /// All tests that failed
    public let failedTests: [TestEntryResult]
    
    /// All test results
    public let unfilteredResults: [TestEntryResult]
    
    public let xcresultData: [Data]
    
    public init(testingResults: [TestingResult]) {
        self.successfulTests = testingResults.flatMap { $0.successfulTests }
        self.failedTests = testingResults.flatMap { $0.failedTests }
        self.unfilteredResults = testingResults.flatMap { $0.unfilteredResults }
        self.xcresultData = testingResults.flatMap { $0.xcresultData }
    }
}
