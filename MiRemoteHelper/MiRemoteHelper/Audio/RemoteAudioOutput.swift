// SPDX-License-Identifier: GPL-3.0-only
// AVAudioEngine routing adapted from Open Voice Bridge. See THIRD_PARTY_NOTICES.md.
import AVFoundation
import AudioToolbox
import CoreAudio

final class RemoteAudioOutput {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    private var generation: UInt64 = 0
    private var drainCompletion: (() -> Void)?
    private(set) var queuedFrames = 0
    private(set) var error: String?
    private(set) var deviceUID = ""
    private var selectedDeviceID: AudioDeviceID = 0
    var isDeviceAlive: Bool {
        guard selectedDeviceID != 0 else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(selectedDeviceID, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }
    var isReady: Bool {
        guard engine?.isRunning == true, let unit = engine?.outputNode.audioUnit else { return false }
        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global, 0, &current, &size) == noErr
            && current == selectedDeviceID
    }

    func configure(uid: String) -> Bool {
        stop()
        guard let device = CoreAudioDeviceCatalog.loopbackDevices().first(where: { $0.uid == uid }) else {
            error = String(localized: "Select an installed BlackHole 2ch or MiRemoteV 2ch device.")
            return false
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        guard let unit = engine.outputNode.audioUnit else { error = String(localized: "Unable to open audio output."); return false }
        var id = device.id
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout.size(ofValue: id)))
        guard result == noErr else { error = String(localized: "Unable to connect to the virtual microphone (\(result))."); return false }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            engine.prepare()
            try engine.start()
            player.play()
            self.engine = engine
            self.player = player
            selectedDeviceID = device.id
            deviceUID = uid
            error = nil
            return true
        } catch {
            self.error = String(localized: "Unable to start the virtual microphone: \(error.localizedDescription)")
            engine.stop()
            return false
        }
    }

    @discardableResult func enqueue(_ samples: [Int16], completion: (() -> Void)? = nil) -> Bool {
        guard !samples.isEmpty, isReady, let player else { return false }
        // Bound latency and memory to one second if the audio device stops consuming.
        guard queuedFrames + samples.count <= 16_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            error = String(localized: "Audio output is backing up. Reconnect the virtual microphone.")
            return false
        }
        for index in samples.indices { channel[index] = Float(samples[index]) / 32_768 }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        queuedFrames += samples.count
        let token = generation
        let frameCount = samples.count
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.queuedFrames = max(0, self.queuedFrames - frameCount)
                completion?()
                if self.queuedFrames == 0 {
                    let drained = self.drainCompletion
                    self.drainCompletion = nil
                    drained?()
                }
            }
        }
        return true
    }

    func beginSession() {
        drainCompletion = nil
        generation &+= 1
        queuedFrames = 0
        player?.stop()
        if isReady { player?.play() }
    }

    func stop() {
        drainCompletion = nil
        generation &+= 1
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        queuedFrames = 0
        deviceUID = ""
        selectedDeviceID = 0
    }

    func testTone(completion: @escaping () -> Void) -> Bool {
        beginSession()
        let samples: [Int16] = (0..<8_000).map { i in
            let phase: Double = 2.0 * Double.pi * 440.0 * Double(i) / 16_000.0
            return Int16(sin(phase) * 2_000.0)
        }
        return enqueue(samples, completion: completion)
    }

    func whenDrained(_ completion: @escaping () -> Void) {
        if queuedFrames == 0 { completion() }
        else { drainCompletion = completion }
    }
}
