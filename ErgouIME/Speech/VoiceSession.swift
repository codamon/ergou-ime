// ergou-ime — voice input inside the input method (M2).
// SPDX-License-Identifier: GPL-3.0-only
//
// D, 2026-11-09:
//   tap Right Option  → start: VoiceHUD at the bottom centre, live text above
//   tap it again      → stop and recognise
//   result            → typed straight into the text field; if that text
//                       field is gone (focus moved, nowhere to type), copied
//                       to the clipboard with a short "已复制" note
//   Esc while recording or recognising → cancel
// A "tap" is Right Option pressed and released within 0.6 s with no other key
// in between, so Option shortcuts (⌥+key) never start recording. The Option
// key itself is never consumed.
//
// Recognisers (docs/PLAN-v1.md M2.6): SenseVoice for the live text,
// Qwen3-ASR (FinalPass, if installed) for what gets typed, with 我的词 as
// hotwords (TermStore). Either one alone also works.
//
// 自动整理 = 云端 (stage B, docs/PLAN-v1.md M2.7): while recording, each
// segment's final text goes to ErgouIME Cloud as soon as it is recognised
// (CloudStream → CloudCorrector), with the app name, 我的词 and as context
// the end of the text before the cursor (if allowed, taken when recording
// starts) plus the segments before it. After the stop only the segments
// still out are waited for (at most CloudTidy.finishWait). Terms the cloud
// model picks out are learned into 我的词 (TermStore, source .cloud) when
// the text is typed.
//
// Global voice (other input sources active) is M3 (docs/PLAN-v1.md).
// Privacy: audio stays in memory; recognised text is never logged; the
// clipboard is only written in the no-text-field case (Privacy rule 5).

import AppKit

/// Where a recognised result goes. Implemented by the controller.
protocol VoiceTarget: AnyObject {
    /// Caret rectangle in screen coordinates (empty if unknown).
    var voiceCaretRect: NSRect { get }
    /// Insert the text; false if there is no text field to insert into.
    func insertVoiceText(_ text: String) -> Bool
    /// Text before the cursor (cloud tidy-up context), nil if unavailable.
    func voiceTextBeforeCursor(limit: Int) -> String?
    /// Bundle identifier of the app being typed into.
    var voiceAppBundleID: String? { get }
}

final class VoiceSession {
    static let shared = VoiceSession()

    enum State: Equatable { case idle, recording, transcribing }
    private(set) var state: State = .idle

    /// The controller whose client was focused when recording started.
    weak var target: VoiceTarget?

    private let recorder = VoiceRecorder()
    private let queue = DispatchQueue(label: "com.codamon.inputmethod.Ergou.speech", qos: .userInitiated)
    /// SenseVoice (live text; final text when Qwen3-ASR is not installed). On `queue`.
    private var transcriber: SpeechTranscriber?
    private var transcriberFailedAt: Date?
    /// Counts recordings, so FinalPass can drop a cancelled one's segments.
    private var recordingID = 0
    #if ERGOU_WITH_SHERPA
    private var punctuator: Punctuator?
    private var punctuatorFailed = false
    #endif
    private var generation = 0

    // Tap detection.
    private var optionDownAt: TimeInterval?
    private var keyDuringOption = false
    static let maxTap: TimeInterval = 0.6

    private init() {
        recorder.onLevel = { level in VoiceHUD.shared.level(level) }
    }

    var isActive: Bool { state != .idle }

    // MARK: - Right Option

    func rightOptionDown() {
        optionDownAt = ProcessInfo.processInfo.systemUptime
        keyDuringOption = false
    }

    func rightOptionUp() {
        defer { optionDownAt = nil }
        guard let down = optionDownAt, !keyDuringOption,
              ProcessInfo.processInfo.systemUptime - down <= Self.maxTap else { return }
        toggle()
    }

    /// Any key while Right Option is down: it was a shortcut.
    func keyPressed() {
        if optionDownAt != nil { keyDuringOption = true }
    }

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .transcribing: if isTidying { skipTidy() }
        }
    }

    // MARK: - Skipping the tidy-up

    /// The recognised text while the language model tidies it; nil otherwise.
    private var tidyOriginal: String?
    var isTidying: Bool { tidyOriginal != nil }

    /// Right Option tap or Return while 整理中: type what was recognised now.
    /// Cloud: segments already tidied keep the tidied text (CloudStream.skip).
    func skipTidy() {
        guard let original = tidyOriginal else { return }
        if let stream = cloudStream, stream.skip() { return }
        tidyOriginal = nil
        generation += 1                       // the tidy result is dropped
        let mine = generation
        deliver(original, generation: mine)
    }

    func cancel() {
        tidyOriginal = nil
        endCloudStream()
        generation += 1
        if state == .recording { _ = recorder.stop() }
        if state != .idle { cancelFinalPass() }
        stopLivePreview()
        state = .idle
        VoiceHUD.shared.hide()
    }

    // MARK: - Recording

    private func start() {
        if SecureInput.isActive { return }                 // Privacy rule 6
        guard SpeechModelFiles.senseVoiceSmallInt8.isPresent || Self.accurateInstalled else {
            VoiceHUD.shared.note("还没有语音模型，在设置里下载", symbol: "arrow.down.circle", for: 3)
            SettingsLauncher.open(page: .models)
            return
        }
        switch VoiceRecorder.permission {
        case .denied:
            VoiceHUD.shared.note("没有麦克风权限：系统设置 › 隐私与安全性 › 麦克风", symbol: "mic.slash", for: 4)
            return
        case .undetermined:
            VoiceRecorder.requestPermission { [weak self] ok in if ok { self?.start() } }
            return
        case .granted:
            break
        }
        let mic = AudioInputs.resolve(chosenUID: SharedSettings.microphoneUID,
                                      preferBuiltInOverBluetooth: SharedSettings.preferBuiltInMic)
        recorder.device = mic?.id
        microphoneName = mic?.name
            ?? AudioInputs.effectiveName(chosenUID: "", preferBuiltInOverBluetooth: false)
        do {
            try recorder.start()
        } catch {
            Log.speech.error("Could not start recording")
            VoiceHUD.shared.note("没法开始录音", symbol: "mic.slash", for: 3)
            return
        }
        state = .recording
        recordingID += 1
        // Qwen3-ASR loads in the background while the user speaks.
        let accurate = beginFinalPass(recordingID)
        endCloudStream()
        cloudStream = makeCloudStream(recordingID)
        resetSegments(finalPass: accurate ? recordingID : nil, recording: recordingID, cloud: cloudStream != nil)
        VoiceHUD.shared.listening()
        CorrectorClient.shared.prepare()
        startLivePreview()
        // Load the model while the user speaks.
        queue.async { [weak self] in
            guard let self else { return }
            self.loadSenseVoice()
            self.loadPunctuator()
        }
    }

    private static var accurateInstalled: Bool {
        #if ERGOU_WITH_SHERPA
        return FinalPass.isInstalled
        #else
        return false
        #endif
    }

    private func beginFinalPass(_ id: Int) -> Bool {
        #if ERGOU_WITH_SHERPA
        return FinalPass.shared.begin(recording: id, hotwords: TermStore.shared.hotwords)
        #else
        return false
        #endif
    }

    private func cancelFinalPass() {
        #if ERGOU_WITH_SHERPA
        FinalPass.shared.cancel(recording: recordingID)
        #endif
    }

    /// On `queue`. SenseVoice, if installed; a failed load is retried after a minute.
    private func loadSenseVoice() {
        // Deleted in Settings: let go of it, so it stops being used and its
        // private clone (the only copy left) can be removed.
        if transcriber != nil, !SpeechModelFiles.senseVoiceSmallInt8.isPresent {
            transcriber = nil
            SpeechModelFiles.removeOrphanedPrivateCopies()
        }
        guard transcriber == nil, SpeechModelFiles.senseVoiceSmallInt8.isPresent else { return }
        if let failed = transcriberFailedAt, Date().timeIntervalSince(failed) < 60 { return }
        transcriber = SpeechTranscriberFactory.make()
        transcriberFailedAt = transcriber == nil ? Date() : nil
    }

    /// Name of the microphone used for the current recording, for messages.
    private var microphoneName: String?

    /// Quiet mics: bring the peak up to about -6 dB (at most ×20) before
    /// recognition. Loud input is left alone.
    private static func normalised(_ samples: [Float]) -> [Float] {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0, peak < 0.25 else { return samples }
        let gain = min(20, 0.5 / peak)
        return samples.map { $0 * gain }
    }

    /// Below about -80 dBFS everywhere: no signal at all, not a quiet room.
    private static func isDigitalSilence(_ samples: [Float]) -> Bool {
        var peak: Float = 0
        for s in samples where abs(s) > peak { peak = abs(s); if peak > 1e-4 { return false } }
        return true
    }

    private func stop() {
        stopLivePreview()
        let samples = recorder.stop()
        guard samples.count > Int(VoiceRecorder.sampleRate * 0.3),
              SpeechSegmenter.voicedSeconds(samples, silence: SpeechSegmenter.silenceThreshold(samples)) >= 0.3 else {
            // Nothing said: no text, no clipboard, just close.
            state = .idle
            generation += 1
            cancelFinalPass()
            endCloudStream()
            if samples.count > Int(VoiceRecorder.sampleRate * 1.5), Self.isDigitalSilence(samples) {
                // A second or more of exact silence: the mic is not working
                // (e.g. built-in mic with the lid closed). Say which one.
                let name = microphoneName.map { "（\($0)）" } ?? ""
                VoiceHUD.shared.note("麦克风没有声音\(name)，在设置 › 语音 里换一个", symbol: "mic.slash", for: 4)
            } else {
                VoiceHUD.shared.hide()
            }
            return
        }
        state = .transcribing
        VoiceHUD.shared.working("识别中")
        generation += 1
        let mine = generation
        queue.async { [weak self] in
            guard let self else { return }
            let started = DispatchTime.now()
            if self.finalPassID == nil { self.loadSenseVoice() }
            self.loadPunctuator()
            // Segments already recognised while recording are kept; finish the rest.
            self.recogniseSegments(in: samples, from: self.segmentCursor, final: true)
            self.finalTexts(samples) { segments, engine in
                let text = segments.compactMap { $0 }.joined()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
                let seconds = Double(samples.count) / VoiceRecorder.sampleRate
                // Diagnostics only: loudness and whether anything came out — never the text.
                let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
                Log.speech.notice("recognised \(seconds, format: .fixed(precision: 1), privacy: .public) s of audio (\(self.segmentTexts.count, privacy: .public) segments, \(engine, privacy: .public)) in \(ms, format: .fixed(precision: 0), privacy: .public) ms after stop, peak \(peak, format: .fixed(precision: 3), privacy: .public), silence \(self.silence, format: .fixed(precision: 0), privacy: .public) dB, \(self.skippedSilent, privacy: .public) skipped, \(text.count, privacy: .public) chars")
                let recognizerOK = engine != "none"
                DispatchQueue.main.async {
                    self.correctThenDeliver(text.isEmpty ? nil : text, segments: segments,
                                            generation: mine, recognizerOK: recognizerOK)
                }
            }
        }
    }

    /// On `queue`, after the last segment was cut: the text of each segment
    /// (nil: nothing recognised), from Qwen3-ASR when it ran, else SenseVoice.
    /// `done` runs on `queue` with the texts and which engine produced them
    /// (for the log).
    private func finalTexts(_ samples: [Float], done: @escaping ([String?], String) -> Void) {
        #if ERGOU_WITH_SHERPA
        if let id = finalPassID {
            let count = segmentTexts.count
            FinalPass.shared.finish(recording: id, segments: count) { [weak self] outcome in
                self?.queue.async {
                    guard let self else { return }
                    // A new recording may have started meanwhile (Esc, then Right Option).
                    let current = self.finalPassID == id && self.segmentTexts.count == count
                    switch current ? outcome : .cancelled {
                    case .cancelled:
                        done([], "cancelled")                 // dropped by the generation check
                    case .texts(let finals):
                        // A segment Qwen3-ASR made nothing of keeps SenseVoice's text, if any.
                        let texts = (0..<count).map { i -> String? in
                            if let t = finals[i], !SpeechSegmenter.isOnlyFiller(t) { return t }
                            return self.segmentTexts[i]
                        }
                        done(texts, "qwen3")
                    case .unavailable:
                        // Qwen3-ASR did not load: SenseVoice for what it has not done yet.
                        self.loadSenseVoice()
                        for i in 0..<count where self.segmentTexts[i] == nil {
                            let r = self.segmentRanges[i]
                            if r.upperBound <= samples.count { self.segmentTexts[i] = self.senseVoiceText(Self.normalised(Array(samples[r]))) }
                        }
                        done(self.segmentTexts, self.transcriber == nil ? "none" : "sensevoice (fallback)")
                    }
                }
            }
            return
        }
        #endif
        done(segmentTexts, transcriber == nil ? "none" : "sensevoice")
    }

    // MARK: - Segments and live text

    /// On `queue` only. Long dictation is cut at pauses (SpeechSegmenter);
    /// each finished segment is recognised once, while recording.
    private var segmentCursor = 0
    /// SenseVoice text per voiced segment (nil: not run, or nothing heard).
    private var segmentTexts: [String?] = []
    /// Where each segment lies in the recording (absolute sample indices).
    private var segmentRanges: [Range<Int>] = []
    /// On `queue`: this recording's FinalPass id when Qwen3-ASR is in use.
    private var finalPassID: Int?
    /// On `queue`: this recording's silence threshold (SpeechSegmenter.silenceThreshold).
    private var silence = SpeechSegmenter.silenceDB
    /// On `queue`: segments skipped as silent, for the diagnostics line.
    private var skippedSilent = 0
    /// On `queue`: the recording these segments belong to, and whether each
    /// final segment text goes to the cloud as soon as it is known.
    private var segmentsRecording = 0
    private var segmentsToCloud = false

    private func resetSegments(finalPass: Int?, recording: Int, cloud: Bool) {
        queue.async { [weak self] in
            self?.segmentsRecording = recording
            self?.segmentsToCloud = cloud
            self?.segmentCursor = 0
            self?.segmentTexts = []
            self?.segmentRanges = []
            self?.finalPassID = finalPass
            self?.silence = SpeechSegmenter.silenceDB
            self?.skippedSilent = 0
        }
    }

    /// On `queue`. Recognise every complete segment of `samples` from
    /// `start` (absolute index); with `final`, also the remainder.
    private func recogniseSegments(in samples: [Float], from start: Int, final: Bool, base: Int = 0) {
        silence = SpeechSegmenter.silenceThreshold(samples)
        // At stop, with Qwen3-ASR in use, SenseVoice is not needed any more.
        let preview = !final || finalPassID == nil
        var offset = start - base
        while let cut = SpeechSegmenter.nextCut(in: samples, from: offset, final: false, silence: silence) {
            addSegment(samples, offset..<cut, base: base, preview: preview)
            offset = cut
        }
        if final, offset < samples.count, samples.count - offset > Int(VoiceRecorder.sampleRate * 0.3) {
            addSegment(samples, offset..<samples.count, base: base, preview: preview)
            offset = samples.count
        }
        segmentCursor = base + offset
    }

    /// On `queue`. A finished segment: SenseVoice text (for the live text,
    /// or the final text without Qwen3-ASR) and, with Qwen3-ASR, queued for it.
    private func addSegment(_ samples: [Float], _ range: Range<Int>, base: Int, preview: Bool) {
        let segment = Array(samples[range])
        // Silent segments make the models invent a filler (or recite the hotwords); skip them.
        guard SpeechSegmenter.voicedSeconds(segment, silence: silence) >= 0.3 else { skippedSilent += 1; return }
        let normalised = Self.normalised(segment)
        let index = segmentTexts.count
        segmentTexts.append(preview ? senseVoiceText(normalised) : nil)
        segmentRanges.append((base + range.lowerBound)..<(base + range.upperBound))
        let recording = segmentsRecording
        #if ERGOU_WITH_SHERPA
        if let id = finalPassID {
            // Cloud: send the segment once Qwen3-ASR has it (SenseVoice's text
            // if Qwen3-ASR made nothing of it), not at the end.
            let decoded: ((String?) -> Void)? = !segmentsToCloud ? nil : { [weak self] text in
                self?.queue.async {
                    guard let self, self.finalPassID == id, index < self.segmentTexts.count else { return }
                    let final = text.flatMap { SpeechSegmenter.isOnlyFiller($0) ? nil : $0 } ?? self.segmentTexts[index]
                    DispatchQueue.main.async { self.streamSubmit(recording: recording, index: index, text: final) }
                }
            }
            FinalPass.shared.submit(recording: id, index: index, samples: normalised,
                                    sampleRate: Int(VoiceRecorder.sampleRate), decoded: decoded)
            return
        }
        #endif
        // SenseVoice only: its text is final.
        if segmentsToCloud, let text = segmentTexts[index] {
            DispatchQueue.main.async { self.streamSubmit(recording: recording, index: index, text: text) }
        }
    }

    /// On `queue`. The current, unfinished segment for the live text.
    private func previewText(_ samples: [Float]) -> String? {
        guard SpeechSegmenter.voicedSeconds(samples, silence: silence) >= 0.3 else { return nil }
        return senseVoiceText(Self.normalised(samples))
    }

    /// On `queue`. SenseVoice + punctuation model; nil without SenseVoice.
    private func senseVoiceText(_ normalised: [Float]) -> String? {
        loadSenseVoice()
        var text = transcriber?.transcribe(samples: normalised, sampleRate: Int(VoiceRecorder.sampleRate))
        #if ERGOU_WITH_SHERPA
        // Only SenseVoice needs this; Qwen3-ASR punctuates by itself.
        if let raw = text, let punctuator { text = punctuator.punctuate(raw) }
        #endif
        guard let text, !text.isEmpty, !SpeechSegmenter.isOnlyFiller(text) else { return nil }
        return text
    }

    /// While recording, every ~0.7 s: recognise newly finished segments and
    /// re-recognise only the current one, then show it all above the
    /// capsule. Cost stays flat however long the user talks.
    private var liveTimer: DispatchSourceTimer?
    private var liveBusy = false

    private func startLivePreview() {
        stopLivePreview()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.8, repeating: 0.7)
        timer.setEventHandler { [weak self] in self?.livePreviewTick() }
        timer.resume()
        liveTimer = timer
    }

    private func stopLivePreview() {
        liveTimer?.cancel()
        liveTimer = nil
    }

    private func livePreviewTick() {
        guard state == .recording else { return }
        // A password field took focus while recording: stop and discard
        // (Privacy rule 6: nothing is recorded in secure input; audit L6).
        if SecureInput.isActive {
            cancel()
            VoiceHUD.shared.note("进入密码框，已停止录音", symbol: "lock", for: 3)
            return
        }
        if recorder.count >= Int(VoiceRecorder.sampleRate) * VoiceRecorder.maxSeconds {
            stop()                                   // 20 min: finish automatically
            return
        }
        guard !liveBusy else { return }
        liveBusy = true
        let mine = generation
        queue.async { [weak self] in
            guard let self else { return }
            let base = self.segmentCursor
            let tail = self.recorder.copy(from: base)
            self.recogniseSegments(in: tail, from: base, final: false, base: base)
            let rest = self.segmentCursor - base
            var partial: String?
            if tail.count - rest > Int(VoiceRecorder.sampleRate / 2) {
                partial = self.previewText(Array(tail[rest...]))
            }
            let recognised = self.segmentTexts
            DispatchQueue.main.async {
                self.liveBusy = false
                // Segments already tidied by the cloud show their tidied text.
                let done = self.cloudStream?.shown(recognised) ?? recognised.compactMap { $0 }.joined()
                let shown = done + (partial ?? "")
                guard mine == self.generation, self.state == .recording, !shown.isEmpty else { return }
                VoiceHUD.shared.transcript(shown)
            }
        }
    }

    /// Optional punctuation model (on `queue`). Picked up as soon as it has
    /// been downloaded; a file that fails its check is not retried.
    private func loadPunctuator() {
        #if ERGOU_WITH_SHERPA
        if punctuator != nil, !SpeechModelFiles.punctuationCTTransformerInt8.isPresent {
            punctuator = nil                         // deleted in Settings
            SpeechModelFiles.removeOrphanedPrivateCopies()
        }
        guard punctuator == nil, !punctuatorFailed,
              SpeechModelFiles.punctuationCTTransformerInt8.isPresent else { return }
        punctuator = Punctuator()
        punctuatorFailed = punctuator == nil
        #endif
    }

    // MARK: - Cloud tidy-up

    /// This recording's cloud tidy-up; nil unless 自动整理 is 云端.
    private var cloudStream: CloudStream?

    /// What may go with the text: the app name, and the text before the
    /// cursor if the user allows it (taken now; the cursor may move later).
    /// Nothing in secure input (rule 6).
    private static func cloudContext(_ target: VoiceTarget?) -> CloudCorrector.Context? {
        guard SharedSettings.voiceCorrection == .cloud, !SecureInput.isActive else { return nil }
        // Not in terminals or password managers (CloudTidy.noContextApps).
        let before = SharedSettings.cloudSendContext && CloudTidy.contextAllowed(bundleID: target?.voiceAppBundleID)
            ? target?.voiceTextBeforeCursor(limit: CloudTidy.maxContext) : nil
        return CloudCorrector.Context(before: before, app: CloudCorrector.appName(bundleID: target?.voiceAppBundleID))
    }

    private func makeCloudStream(_ recording: Int) -> CloudStream? {
        guard let context = Self.cloudContext(target) else { return nil }
        return CloudStream(batch: recording, before: context.before, app: context.app,
                           terms: TermStore.shared.activeTerms) { request, done in
            CloudCorrector.shared.send(request, done: done)
        }
    }

    /// A segment's final text, while recording or just after: to the cloud now.
    private func streamSubmit(recording: Int, index: Int, text: String?) {
        guard let text, let stream = cloudStream, stream.batch == recording else { return }
        // Switched away from 云端, or a password field took focus: send no more.
        guard SharedSettings.voiceCorrection == .cloud, !SecureInput.isActive else { endCloudStream(); return }
        stream.submit(index, text)
    }

    /// Esc, or not tidying in the cloud after all: drop replies still out
    /// and stop their requests.
    private func endCloudStream() {
        guard let stream = cloudStream else { return }
        cloudStream = nil
        stream.cancel()
        CloudCorrector.shared.cancel(batch: stream.batch)
    }

    /// After the stop: wait only for the segments still out.
    private func cloudFinish(_ stream: CloudStream, segments: [String?], text: String, generation mine: Int) {
        let started = DispatchTime.now()
        tidyOriginal = text
        stream.onUpdate = { [weak self, weak stream] in
            guard let self, let stream, mine == self.generation, self.state == .transcribing else { return }
            VoiceHUD.shared.transcript(stream.shown(segments))
        }
        VoiceHUD.shared.transcript(stream.shown(segments))
        stream.finish(segments) { [weak self] result in
            guard let self else { return }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
            Log.speech.notice("cloud tidy-up: \(result.tidied, privacy: .public)/\(result.segments, privacy: .public) segments tidied, \(stream.pending, privacy: .public) still out, waited \(ms, format: .fixed(precision: 0), privacy: .public) ms after recognition, \(result.terms.count, privacy: .public) terms")
            if stream.pending > 0 { CloudCorrector.shared.cancel(batch: stream.batch) }   // timed out or skipped
            guard mine == self.generation, self.state == .transcribing, self.cloudStream === stream else { return }
            self.cloudStream = nil
            self.tidyOriginal = nil
            // Learned only when the text is typed (not after Esc).
            for t in result.terms {
                TermStore.shared.record(term: t.term, heard: t.heard, source: .cloud)   // ignored in secure input
            }
            self.deliver(result.text, generation: mine)
        }
        if cloudStream === stream, tidyOriginal != nil { VoiceHUD.shared.working("云端整理中", skippable: true) }
    }

    /// Language-model clean-up (Settings → 语音 → 自动整理), then deliver.
    private func correctThenDeliver(_ text: String?, segments: [String?], generation mine: Int, recognizerOK: Bool) {
        guard mine == generation, state == .transcribing else { return }
        if let text, !text.isEmpty, recognizerOK, let stream = cloudStream,
           SharedSettings.voiceCorrection == .cloud, !SecureInput.isActive {
            cloudFinish(stream, segments: segments, text: text, generation: mine)
            return
        }
        endCloudStream()
        guard let text, !text.isEmpty, CorrectorClient.current != nil else {
            deliver(text, generation: mine, recognizerOK: recognizerOK); return
        }
        VoiceHUD.shared.transcript(text)
        VoiceHUD.shared.working("整理中", skippable: true)
        let started = DispatchTime.now()
        if !CorrectorClient.shared.isWarm { VoiceHUD.shared.working("正在加载整理模型", skippable: true) }
        tidyOriginal = text
        CorrectorClient.shared.tidy(text) { [weak self] result, changed in
            // A skipped tidy-up must not clear the next recording's 整理中 state.
            if mine == self?.generation { self?.tidyOriginal = nil }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
            Log.speech.notice("tidy-up \(changed ? "applied" : "skipped", privacy: .public) in \(ms, format: .fixed(precision: 0), privacy: .public) ms")
            self?.deliver(result, generation: mine)
        }
    }

    private func deliver(_ text: String?, generation mine: Int, recognizerOK: Bool = true) {
        guard mine == generation, state == .transcribing else { return }
        state = .idle
        let text = text.map { SharedSettings.autoSpace ? AutoSpace.apply($0) : $0 }
        if let text, !text.isEmpty, !SecureInput.isActive { VoiceHistory.shared.add(text) }
        guard recognizerOK else {
            VoiceHUD.shared.note("语音模型加载失败，在设置里重新下载", symbol: "exclamationmark.triangle", for: 3)
            return
        }
        guard let text, !text.isEmpty else {
            VoiceHUD.shared.note("没听清，再说一次", symbol: "ear", for: 2)
            return
        }
        if let target, target.insertVoiceText(text) {
            VoiceHUD.shared.hide()
            return
        }
        if target == nil, GlobalHotkey.shared.isRunning, !SecureInput.isActive {
            // Another input source is active: switch to ours to type it.
            ForeignInsert.insert(text) { [weak self] ok in
                if ok { VoiceHUD.shared.hide() } else { self?.copyInstead(text) }
            }
            return
        }
        copyInstead(text)
    }

    /// No text field: clipboard, written once, never read (Privacy rule 5).
    private func copyInstead(_ text: String) {
        if SecureInput.isActive { VoiceHUD.shared.hide(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        VoiceHUD.shared.transcript(text)
        VoiceHUD.shared.note("没有输入框，已复制到剪贴板", symbol: "doc.on.clipboard", for: 2.5)
    }
}
