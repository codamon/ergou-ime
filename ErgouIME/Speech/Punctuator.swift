// ergou-ime — add punctuation to recognised text (CT-Transformer via sherpa-onnx).
// SPDX-License-Identifier: GPL-3.0-only
//
// SenseVoice returns text without punctuation. The punctuation model is a
// separate optional download (ErgouIME Settings). Measured on D's Mac
// 2026-11-09: load 77 ms, 4–7 ms per sentence.

#if ERGOU_WITH_SHERPA
import Foundation

final class Punctuator {
    private let handle: OpaquePointer

    /// nil when the model is missing or fails its SHA-256 check.
    init?() {
        let files = SpeechModelFiles.punctuationCTTransformerInt8
        guard files.isPresent else { return nil }
        // Load our own verified clone, never the App Group file (rule 9).
        guard let directory = files.verifiedPrivateCopy() else {
            Log.speech.error("Punctuation model failed its SHA-256 check")
            return nil
        }
        let model = strdup(directory.appendingPathComponent("model.int8.onnx").path)!
        let provider = strdup("cpu")!
        defer { free(model); free(provider) }
        var config = SherpaOnnxOfflinePunctuationConfig()
        config.model.ct_transformer = UnsafePointer(model)
        config.model.num_threads = 1
        config.model.provider = UnsafePointer(provider)
        guard let p = SherpaOnnxCreateOfflinePunctuation(&config) else {
            Log.speech.error("SherpaOnnxCreateOfflinePunctuation failed")
            return nil
        }
        handle = p
    }

    deinit { SherpaOnnxDestroyOfflinePunctuation(handle) }

    func punctuate(_ text: String) -> String {
        guard let out = SherpaOfflinePunctuationAddPunct(handle, text) else { return text }
        defer { SherpaOfflinePunctuationFreeText(out) }
        let s = String(cString: out)
        return s.isEmpty ? text : s
    }
}
#endif
