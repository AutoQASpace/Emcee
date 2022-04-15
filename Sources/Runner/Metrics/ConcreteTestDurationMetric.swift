import Foundation
import Graphite
import MetricsRecording
import QueueModels

public final class ConcreteTestDurationMetric: GraphiteMetric {
    public init(
        result: String,
        host: String,
        testClassName: String,
        testMethodName: String,
        duration: Double,
        version: Version,
        timestamp: Date
    ) {
        super.init(
            fixedComponents: ["test", "duration"],
            variableComponents: [
                result,
                host,
                testClassName,
                testMethodName,
                version.value,
                GraphiteMetric.reservedField,
                GraphiteMetric.reservedField
            ],
            value: duration,
            timestamp: timestamp
        )
    }
}
