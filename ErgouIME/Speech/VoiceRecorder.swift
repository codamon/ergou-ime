// ergou-ime — microphone capture for push-to-talk (M2 T2.2).
// SPDX-License-Identifier: GPL-3.0-only
//
// AVAudioEngine input tap → 16 kHz mono Float32, kept in memory only and
// capped at 60 s. Nothing is written to disk (Privacy rule 7).

import AVFoundation
import CoreAudio
import AudioToolbox

final class VoiceRecorder {
    static let sampleRate: Double = 16_000
    /// Long dictation is split into segments (SpeechSegmenter), so the cap is
    /// about memory only: 20 min ≈ 77 MB of Float32 (D: 60 s was too short).
    static let maxSeconds = 20 * 60

    /// New for every recording: an engine that has run on one device keeps
    /// that device's format, and after switching microphones start() failed
    /// with -10868 "formats don't match" (D's Mac, 2026-11-10).
    private var engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: VoiceRecorder.sampleRate,
                                       channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false
    /// Input level 0…1 (RMS on a dB scale), called on the main queue ~30×/s.
    var onLevel: ((Float) -> Void)?
    private var lastLevelAt: TimeInterval = 0

    enum Permission { case granted, denied, undetermined }

    static var permission: Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
    }

    private var configObserver: NSObjectProtocol?

    func start() throws {
        guard !isRecording else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        usedFallback = false
        restarts = 0
        do {
            try begin()
        } catch where device != nil {
            // The chosen mic would not open: record from the system default
            // rather than not at all.
            Log.speech.error("Chosen microphone failed; using the system default")
            usedFallback = true
            let chosen = device
            device = nil
            defer { device = chosen }
            try begin()
        }
        isRecording = true
    }

    private var restarts = 0

    /// A fresh engine on `device`, observed for configuration changes.
    private func begin() throws {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine = AVAudioEngine()
        converter = nil
        try startEngine()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.configurationChanged() }
    }

    /// Selecting a device fires a configuration change right after start
    /// while capture carries on; restarting then lost everything after the
    /// first words (D's Mac, 2026-11-10). A Bluetooth headset switching to
    /// its call profile does stop the audio. So: wait a moment, and only if
    /// no new samples arrived rebuild the engine; samples so far are kept.
    private func configurationChanged() {
        guard isRecording else { return }
        let before = count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isRecording else { return }
            if self.engine.isRunning, self.count > before { return }
            guard self.restarts < 5 else {
                Log.speech.error("audio keeps changing; not restarting again")
                return
            }
            self.restarts += 1
            Log.speech.notice("audio stopped after a configuration change; restarting capture")
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            do {
                try self.begin()
            } catch {
                Log.speech.error("Could not restart capture: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The microphone to record from (AudioInputs.resolve); nil = the
    /// system default input. Set before each start.
    var device: AudioDeviceID?
    /// True when the last start() could not open `device` and used the default.
    private(set) var usedFallback = false

    private func startEngine() throws {
        let input = engine.inputNode
        if var device, let unit = input.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global, 0, &device,
                                              UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { Log.speech.error("Could not select the microphone (\(status, privacy: .public))") }
            // The node's output format still describes the old device (seen:
            // 2 ch 192 kHz after picking a 48 kHz USB mic → -10868 on start).
            // Make the output match the new device; append() converts.
            let hardware = input.inputFormat(forBus: 0)
            if status == noErr, hardware.sampleRate > 0, hardware.channelCount > 0 {
                var asbd = hardware.streamDescription.pointee
                let set = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                               &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
                if set != noErr { Log.speech.error("Could not set the microphone format (\(set, privacy: .public))") }
            }
        }
        // nil format: the tap delivers the node's current hardware format;
        // append() builds a converter for whatever format actually arrives.
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Samples recorded so far.
    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }

    /// A copy of the samples from `index` on (for segmenting while recording).
    func copy(from index: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard index < samples.count else { return [] }
        return Array(samples[max(0, index)...])
    }

    /// Stops and returns everything recorded since start().
    func stop() -> [Float] {
        guard isRecording else { return [] }
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); defer { lock.unlock() }
        let out = samples
        samples.removeAll()
        return out
    }

    private func reportLevel(_ frame: UnsafeBufferPointer<Float>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelAt >= 1.0 / 30, let onLevel else { return }
        lastLevelAt = now
        var sum: Float = 0
        for x in frame { sum += x * x }
        let rms = (sum / Float(max(frame.count, 1))).squareRoot()
        // Speech on the built-in mic sits around -45…-25 dBFS; the old
        // -50…0 dB mapping kept the bars nearly flat (D's photo, 2026-11-09).
        // -58 dB → 0, -18 dB → 1, with a curve that lifts normal speech.
        let db = 20 * log10(max(rms, 1e-6))
        let level = pow(min(max((db + 58) / 40, 0), 1), 0.7)
        DispatchQueue.main.async { onLevel(level) }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData, out.frameLength > 0 else { return }
        reportLevel(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        lock.lock(); defer { lock.unlock() }
        let room = Int(Self.sampleRate) * Self.maxSeconds - samples.count
        guard room > 0 else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: min(room, Int(out.frameLength))))
    }
}
