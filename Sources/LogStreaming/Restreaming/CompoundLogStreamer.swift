import EmceeLogging
import EmceeLoggingModels
import Foundation

/// streams provided log into multiple streamers.
public final class CompoundLogStreamer: LogStreamer {
    private let streamers: [LogStreamer]
    
    public init(streamers: [LogStreamer]) {
        self.streamers = streamers
    }
    
    public func stream(logEntry: LogEntry) {
        for streamer in streamers {
            streamer.stream(logEntry: logEntry)
        }
    }
}
