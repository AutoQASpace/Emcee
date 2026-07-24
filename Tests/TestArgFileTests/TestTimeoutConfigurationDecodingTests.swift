import Foundation
import RunnerModels
import XCTest

final class TestTimeoutConfigurationDecodingTests: XCTestCase {
    func test___decoding_without_hard_cap___uses_default() throws {
        let json = Data("""
        {"singleTestMaximumDuration": 270, "testRunnerMaximumSilenceDuration": 900}
        """.utf8)
        let config = try JSONDecoder().decode(TestTimeoutConfiguration.self, from: json)
        XCTAssertEqual(config.bucketShutdownHardCap, TestTimeoutConfiguration.defaultBucketShutdownHardCap)
        XCTAssertEqual(config.bucketShutdownHardCap, 1800)
    }

    func test___decoding_with_hard_cap___uses_value() throws {
        let json = Data("""
        {"singleTestMaximumDuration": 270, "testRunnerMaximumSilenceDuration": 900, "bucketShutdownHardCap": 3600}
        """.utf8)
        let config = try JSONDecoder().decode(TestTimeoutConfiguration.self, from: json)
        XCTAssertEqual(config.bucketShutdownHardCap, 3600)
    }
}
