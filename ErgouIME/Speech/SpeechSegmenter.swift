// ergou-ime — split long recordings at pauses (D, 2026-11-09: 60 s was too short).
// SPDX-License-Identifier: GPL-3.0-only
//
// SenseVoice is trained on utterance-length audio; minutes in one pass get
// slower and less accurate. We cut at pauses so each segment is recognised
// once, as soon as it is complete:
//   - a pause (energy below the threshold) of >= 0.5 s ends a segment that is
//     already >= 3 s long;
//   - a segment never exceeds 25 s: then we cut at the quietest 30 ms frame
//     within its last 4 s.
// Energy only, no extra model. Frames are 30 ms (480 samples at 16 kHz).

import Foundation

struct SpeechSegmenter {
    static let sampleRate = 16_000
    static let frame = 480                         // 30 ms
    static let minSegment = 3 * sampleRate
    static let maxSegment = 25 * sampleRate
    static let pause = sampleRate / 2              // 0.5 s
    /// The fixed threshold, tuned on the MacBook's built-in mic. Quieter
    /// mics get a lower one from `silenceThreshold` (never a higher one).
    static let silenceDB: Float = -45

    /// Silence threshold for this recording: a little above its own noise
    /// floor (15th percentile of 30 ms frames over the last 30 s), between
    /// -62 and -45 dB. A USB dynamic mic peaked at only -30 dB and whole
    /// sentences fell under -45 dB, were taken for silence and dropped
    /// (D's Mac, 2026-11-10).
    static func silenceThreshold(_ samples: [Float]) -> Float {
        let window = 30 * sampleRate
        let start = max(0, samples.count - window)
        var levels: [Float] = []
        levels.reserveCapacity((samples.count - start) / frame + 1)
        var i = start
        while i + frame <= samples.count { levels.append(db(samples, i, frame)); i += frame }
        guard levels.count >= 10 else { return silenceDB }
        levels.sort()
        let floor = levels[levels.count * 15 / 100]
        return min(silenceDB, max(-62, floor + 8))
    }

    /// Index where the next complete segment ends, if `samples[start...]`
    /// already contains one. Pass `final: true` at the end of the recording
    /// to take whatever is left.
    static func nextCut(in samples: [Float], from start: Int, final: Bool, silence: Float = silenceDB) -> Int? {
        let available = samples.count - start
        guard available > 0 else { return nil }
        if final { return samples.count }

        var silentRun = 0
        var quietest = (index: 0, db: Float.greatestFiniteMagnitude)
        var i = start
        while i + frame <= samples.count {
            let db = Self.db(samples, i, frame)
            let length = i + frame - start
            if db < silence {
                silentRun += frame
                if silentRun >= pause, length >= minSegment {
                    return i + frame - silentRun / 2       // middle of the pause
                }
            } else {
                silentRun = 0
            }
            if length >= maxSegment - 4 * sampleRate, db < quietest.db {
                quietest = (i + frame / 2, db)
            }
            if length >= maxSegment {
                return quietest.index > start ? quietest.index : i + frame
            }
            i += frame
        }
        return nil
    }

    /// Seconds of frames louder than the silence threshold. Below ~0.3 s the
    /// recording is treated as silence: SenseVoice otherwise "hears" a
    /// filler (D started and stopped at once and got 嗯。, 2026-11-09).
    static func voicedSeconds(_ samples: [Float], silence: Float = silenceDB) -> Double {
        var voiced = 0
        var i = 0
        while i + frame <= samples.count {
            if db(samples, i, frame) >= silence { voiced += frame }
            i += frame
        }
        return Double(voiced) / Double(sampleRate)
    }

    /// True when recognised text is only fillers and punctuation (嗯。/ 啊 / 呃…).
    static func isOnlyFiller(_ text: String) -> Bool {
        let fillers = Set("嗯啊呃哦唔额噢喔诶欸哎嘿呀吧呢".map { $0 })
        let core = text.filter { !$0.isPunctuation && !$0.isWhitespace }
        return core.isEmpty || core.allSatisfy { fillers.contains($0) }
    }

    private static func db(_ s: [Float], _ start: Int, _ n: Int) -> Float {
        var sum: Float = 0
        for k in start..<(start + n) { sum += s[k] * s[k] }
        return 20 * log10(max((sum / Float(n)).squareRoot(), 1e-6))
    }
}
