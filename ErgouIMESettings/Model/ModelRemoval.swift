// ErgouIME Settings — what deleting a speech model does (text for the dialog).
// SPDX-License-Identifier: GPL-3.0-only
//
// ModelDownloader.remove deletes the folder in the App Group. Each process
// drops its private verified clone on its next load or launch
// (SpeechModelFiles.removeOrphanedPrivateCopies), so the space comes back
// then; a model already in memory is released at the latest when the input
// method restarts (VoiceSession.loadSenseVoice lets go of SenseVoice sooner).

import Foundation

enum ModelRemoval {
    static func message(for model: SpeechModel) -> String {
        let size = diskSize(model.files.directory)
        let freed = size > 0 ? "释放约 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))。" : ""
        return [consequence(of: model), freed + "以后可以再下载。"].joined(separator: "\n")
    }

    private static func consequence(of model: SpeechModel) -> String {
        let accurate = SpeechModelFiles.qwen3ASR06BInt8.isPresent
        let light = SpeechModelFiles.senseVoiceSmallInt8.isPresent
        let noVoice = "删除后没有识别模型，语音输入要等重新下载才能用。"
        switch model.files.directoryName {
        case SpeechModelFiles.qwen3ASR06BInt8.directoryName:
            return light ? "说完后的结果改用轻量模型，准确率会下降。" : noVoice
        case SpeechModelFiles.senseVoiceSmallInt8.directoryName:
            return accurate ? "说话时不再边说边显示文字；说完后照常用高精度模型。" : noVoice
        case SpeechModelFiles.punctuationCTTransformerInt8.directoryName:
            return accurate
                ? "只有轻量模型的结果用它加标点；高精度模型自带标点，不受影响。"
                : "轻量模型识别出的文字不再自动加标点。"
        default:
            if LocalCorrectionModel.allCases.contains(where: { $0.files.directoryName == model.files.directoryName }) {
                return "用这个模型时，自动整理只加标点，直到重新下载或换成别的整理方式。"
            }
            return "模型文件会从这台 Mac 上删除。"
        }
    }

    /// Bytes on disk under `url` (0 if missing).
    static func diskSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
