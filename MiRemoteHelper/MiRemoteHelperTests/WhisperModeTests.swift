import Foundation
import Testing
@testable import MiRemoteHelper

struct WhisperModeTests {
    @Test func preservesExistingGainAndRemembersIndependentWhisperGain() throws {
        let name = "WhisperModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3.0, forKey: "gainDB")
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.whisperMode)
        #expect(settings.activeGainDB == 3)
        settings.whisperMode = true
        #expect(settings.activeGainDB == 3)
        settings.activeGainDB = 9
        settings.whisperMode = false
        #expect(settings.activeGainDB == 3)
        settings.activeGainDB = -2
        settings.whisperMode = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.whisperMode)
        #expect(reloaded.activeGainDB == 9)
        #expect(reloaded.gainDB == -2)
        reloaded.activeGainDB = 0
        #expect(AppSettings(defaults: defaults).whisperGainDB == 0)
    }

    @Test func whisperPreservesHighFrequencyDetailAndNormalModeKeepsSmoothing() {
        let samples: [Int16] = [1000, -1000, 1000, -1000, 1000]
        #expect(PCMPostprocessor.process(samples, gainDB: 0, smoothing: false) == samples)
        #expect(PCMPostprocessor.process(samples, gainDB: 0) == [1000, 0, 0, 0, 1000])
        #expect(PCMPostprocessor.process([], gainDB: 6, smoothing: false).isEmpty)
        #expect(PCMPostprocessor.process([1000], gainDB: 6, smoothing: false) == [1995])
    }

    @Test func gainSaturatesSafelyAndMeterDetectsBothRails() {
        let boosted = PCMPostprocessor.process([20000, -20000], gainDB: 12, smoothing: false)
        #expect(boosted == [.max, .min])
        for sample in boosted {
            var meter = AudioInputMeter()
            meter.append(Array(repeating: sample, count: 32))
            #expect(meter.overloaded)
            #expect(meter.displayLevel > 0.99)
            meter.clearPeak()
            meter.append([1])
            #expect(meter.overloaded)
        }
        #expect(PCMPostprocessor.process([1234], gainDB: .nan, smoothing: false) == [1234])
    }

    @Test func isolatedSpikesDoNotTriggerOverload() {
        var meter = AudioInputMeter()
        for _ in 0..<10 {
            meter.append([.max, .min])
            meter.append(Array(repeating: 100, count: 1598))
            meter.clearPeak()
        }
        #expect(!meter.overloaded)
    }

    @Test func repeatedClippingAcrossPacketsAndPeakResetsTriggersOverload() {
        var meter = AudioInputMeter()
        meter.append(Array(repeating: .max, count: 16))
        meter.clearPeak()
        meter.append(Array(repeating: 100, count: 100))
        meter.append(Array(repeating: .min, count: 15))
        #expect(!meter.overloaded)
        meter.append([.min])
        #expect(meter.overloaded)
        meter.clearPeak()
        meter.append(Array(repeating: 0, count: 1600))
        #expect(meter.overloaded)
        meter = AudioInputMeter()
        #expect(!meter.overloaded)
    }

    @Test func meterAccumulatesPeaksBetweenUpdatesAndResetsWithoutFalseOverload() throws {
        var meter = AudioInputMeter()
        meter.append([0, 0])
        #expect(meter.peakDBFS == nil)
        #expect(meter.displayLevel == 0)
        meter.append([16384])
        meter.append([100])
        let peak = try #require(meter.peakDBFS)
        #expect(abs(peak + 6.0206) < 0.001)
        #expect(!meter.overloaded)
        meter.clearPeak()
        #expect(meter.peakDBFS == nil)
        meter.append([.max])
        meter = AudioInputMeter()
        #expect(!meter.overloaded)
        #expect(meter.displayLevel == 0)
    }
}
