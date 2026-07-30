public enum XcTestRunScreenCaptureFormat: String, CaseIterable {

    /// Xcode captures per-step screenshots — the cheap option (no video encoder).
    /// NOTE: this is NOT the default: an absent key means screen RECORDING on runtimes
    /// that support it (18.6+; field-proven 2026-07-29), screenshots only on older
    /// runtimes (15.4). Write the key explicitly to opt out of recording.
    ///
    /// Raw values are camelCase — the ONLY spelling XCTestCore accepts (its binary contains
    /// literally "screenshots"/"screenRecording"; field-proven 2026-07-30: the previously
    /// used "SCREENSHOTS"/"SCREEN_RECORDING" were silently ignored and the default recording
    /// kept running on every test). Do not "fix" the casing back.
    case screenshots = "screenshots"

    /// Xcode records test video into xcresult (requires runtime support; older runtimes fall back to screenshots)
    case screenRecording = "screenRecording"

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
