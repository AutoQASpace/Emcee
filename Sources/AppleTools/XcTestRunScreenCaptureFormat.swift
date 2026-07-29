public enum XcTestRunScreenCaptureFormat: String, CaseIterable {

    /// Xcode captures per-step screenshots — the cheap option (no video encoder).
    /// NOTE: this is NOT the default: an absent key means screen RECORDING on runtimes
    /// that support it (18.6+; field-proven 2026-07-29), screenshots only on older
    /// runtimes (15.4). Write the key explicitly to opt out of recording.
    case screenshots = "SCREENSHOTS"

    /// Xcode records test video into xcresult (requires runtime support; older runtimes fall back to screenshots)
    case screenRecording = "SCREEN_RECORDING"

    public init(fromRawValue value: String) throws {
        guard let captureFormat = XcTestRunScreenCaptureFormat(rawValue: value) else {
            struct UnknownRawValue: Error, CustomStringConvertible {
                let value: String
                var description: String {
                    let possibleValues = XcTestRunScreenCaptureFormat.allCases
                        .map { "'\($0.rawValue)'" }
                        .joined(separator: ", ")
                    return "Couldn't init 'XcTestRunScreenCaptureFormat' from value: '\(value)'. Possible values: \(possibleValues)"
                }
            }
            throw UnknownRawValue(value: value)
        }
        self = captureFormat
    }
}
