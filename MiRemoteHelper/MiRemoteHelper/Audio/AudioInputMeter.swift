import Foundation

/// Measures the processed signal sent to the virtual microphone.
/// Peaks accumulate between UI updates; overload stays latched for the session.
struct AudioInputMeter {
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
            if sample == .max || sample == .min { overloaded = true }
        }
    }

    mutating func clearPeak() { peak = 0 }
}
