import Foundation

/// Measures the processed signal sent to the virtual microphone.
/// Peaks accumulate between UI updates; overload stays latched for the session.
struct AudioInputMeter {
    // RC003 audio is 16 kHz: require at least 2% clipped samples in a
    // 100 ms window. Packet boundaries and UI peak resets do not reset it.
    private static let windowSize = 1_600
    private static let clippingThreshold = 32
    private var windowSamples = 0
    private var clippedSamples = 0
    private var peak = 0
    private(set) var overloaded = false
    private(set) var sampleCount = 0

    var peakDBFS: Double? {
        peak > 0 ? min(0, 20 * log10(Double(peak) / 32_768)) : nil
    }
    var displayLevel: Double {
        peakDBFS.map { min(1, max(0, ($0 + 60) / 60)) } ?? 0
    }

    mutating func append(_ samples: [Int16]) {
        sampleCount += samples.count
        for sample in samples {
            peak = max(peak, abs(Int(sample)))
            if !overloaded {
                windowSamples += 1
                if sample == .max || sample == .min { clippedSamples += 1 }
                if clippedSamples >= Self.clippingThreshold { overloaded = true }
                if windowSamples == Self.windowSize {
                    windowSamples = 0
                    clippedSamples = 0
                }
            }
        }
    }

    mutating func clearPeak() { peak = 0 }
}
