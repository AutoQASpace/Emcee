import ArgLib
import Foundation

final class ArgumentDescriptions {
    static let emceeVersion = doubleDashedDescription(dashlessName: "emcee-version", overview: "Explicit version of Emcee binary")
    static let junit = doubleDashedDescription(dashlessName: "junit", overview: "Path where the combined (for all test destinations) Junit report file should be created")
    static let output = doubleDashedDescription(dashlessName: "output", overview: "Path to file where to store the output")
    static let queueServer = doubleDashedDescription(dashlessName: "queue-server", overview: "An address to a server which runs job queues, e.g. 127.0.0.1:1234")
    static let queueServerConfigurationLocation = doubleDashedDescription(dashlessName: "queue-server-configuration-location", overview: "JSON file location which describes QueueServerConfiguration, e.g. http://example.com/file.zip#path/to/config.json")
    static let remoteCacheConfig = doubleDashedDescription(dashlessName: "remote-cache-config", overview: "JSON file with remote server settings")
    static let setFeatureStatus = doubleDashedDescription(dashlessName: "set-feature-status", overview: "Enabled/Disabled")
    static let tempFolder = doubleDashedDescription(dashlessName: "temp-folder", overview: "Where to store temporary stuff, including simulator data")
    static let testArgFile = doubleDashedDescription(dashlessName: "test-arg-file", overview: "JSON file with test plan")
    static let trace = doubleDashedDescription(dashlessName: "trace", overview: "Path where the combined (for all test destinations) Chrome trace file should be created")
    static let workerId = doubleDashedDescription(dashlessName: "worker-id", overview: "An identifier used to distinguish between workers. Useful to match with deployment destination's identifier")
    static let numberOfSimulators = doubleDashedDescription(dashlessName: "number-of-simulators", overview: "Number of simulators to use for benchmarking")
    static let duration = doubleDashedDescription(dashlessName: "duration", overview: "Benchmark duration, in seconds")
    static let sampleInterval = doubleDashedDescription(dashlessName: "sample-interval", overview: "How often system metrics are sampled, in seconds")
    static let plist = doubleDashedDescription(dashlessName: "plist", overview: "Path to benchmark results")

    private static func doubleDashedDescription(dashlessName: String, overview: String, multiple: Bool = false) -> ArgumentDescription {
        return ArgumentDescription(name: .doubleDashed(dashlessName: dashlessName), overview: overview, multiple: multiple)
    }
}
