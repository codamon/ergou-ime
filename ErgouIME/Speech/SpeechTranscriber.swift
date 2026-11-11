// ergou-ime — speech-to-text abstraction (push-to-talk, M2/M3).
// SPDX-License-Identifier: GPL-3.0-only
//
// Privacy: transcription is on-device only. Audio arrives as an in-memory
// buffer, is decoded, and is dropped. Implementations must not write audio or
// transcripts to disk and must not log transcript text. No recording while
// secure input is on (SecureInput.isActive).
//
// The result is shown as a candidate (Enter commits), never inserted directly.

import Foundation

protocol SpeechTranscriber: AnyObject {
    /// Transcribe one utterance. `samples` are mono Float32 PCM in [-1, 1].
    /// Blocking; call off the main thread.
    func transcribe(samples: [Float], sampleRate: Int) -> String?
}

enum SpeechTranscriberFactory {
    /// The engine chosen in ErgouIME Settings. Returns nil when the app was
    /// built without sherpa-onnx or the model is missing — the caller then
    /// shows "还没有语音模型" and opens Settings' download dialog
    /// (SettingsLauncher.open(page: .models)). Never downloads by itself.
    static func make(_ kind: SpeechEngineKind = SharedSettings.speechEngine) -> SpeechTranscriber? {
        #if ERGOU_WITH_SHERPA
        switch kind {
        case .senseVoice:
            let files = SpeechModelFiles.senseVoiceSmallInt8
            // The model folder can be written by ErgouIME Settings (network
            // access): clone the files into our private container, check
            // the clones against hashes fixed in our code, and let
            // onnxruntime parse only those (Privacy rule 9). ~0.3 s once.
            guard let directory = files.verifiedPrivateCopy() else {
                Log.speech.error("Speech model file failed its SHA-256 check")
                return nil
            }
            return SenseVoiceTranscriber(modelDirectory: directory)
        case .whisper:
            // TODO(M6 T6.2): Whisper (MIT weights) via sherpa-onnx's offline
            // Whisper config — the second implementation, in case the FunASR
            // model licence changes to something unacceptable.
            Log.speech.error("Whisper engine not implemented yet")
            return nil
        }
        #else
        return nil
        #endif
    }
}
