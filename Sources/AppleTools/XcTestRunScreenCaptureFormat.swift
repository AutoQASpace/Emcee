public enum XcTestRunScreenCaptureFormat: String, CaseIterable {

    /// Xcode captures per-step screenshots (default behavior when the key is absent)
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
