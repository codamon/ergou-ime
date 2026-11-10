// ErgouIME Settings — downloadable speech models (data only).
// SPDX-License-Identifier: GPL-3.0-only
//
// Lives in the Settings target only: the input method never needs URLs.
// Values match scripts/fetch-sensevoice-model.sh — keep them in sync.

import Foundation

struct SpeechModel: Identifiable {
    let id: String
    let displayName: String
    /// Short label for lists and the dialog title.
    let shortName: String
    let engine: SpeechEngineKind
    /// Compressed archive size in bytes (shown as "约 158 MB").
    let archiveBytes: Int64
    let sourceURL: URL
    let sha256: String
    let licenseName: String
    let licenseURL: URL
    /// Plain-language summary shown in the confirmation dialog.
    let licenseSummary: [String]
    let attribution: String
    /// Files expected after unpacking, with their SHA-256 (shared with the
    /// input method, which checks them again before loading).
    let files: SpeechModelFiles
    /// nil: a .tar.bz2 to unpack. Otherwise the download is this one file.
    var singleFile: String? = nil
    /// Tag after the name in the model list ("推荐").
    var badge: String? = nil
    /// One line under the name in the model list.
    var blurb: String? = nil
    /// Extra size information for the dialog (unpacked size, memory).
    var sizeNote: String? = nil
}

enum ModelCatalog {
    /// Measured on D's Mac 2026-11-10 (docs/PLAN-v1.md M2.6): 2.9 %
    /// character errors vs SenseVoice 3.9 %, 0.3 % with 我的词.
    static let qwen3ASR06BInt8 = SpeechModel(
        id: "qwen3-asr-0.6B-int8-2026-03-25",
        displayName: "Qwen3-ASR 0.6B（int8，2026-03-25）",
        shortName: "高精度识别模型",
        engine: .senseVoice,
        archiveBytes: 878_702_423,
        sourceURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2")!,
        sha256: "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96",
        licenseName: "Apache License 2.0",
        licenseURL: URL(string: "https://github.com/QwenLM/Qwen3-ASR/blob/main/LICENSE")!,
        licenseSummary: [
            "Apache-2.0 开源许可证，可以自由使用、修改和分发。",
            "模型由阿里巴巴通义千问团队发布；这里用的是 sherpa-onnx 打包的 int8 量化版。",
            "下载后只在这台 Mac 上运行，不联网。",
        ],
        attribution: "Qwen3-ASR © Alibaba Cloud（Qwen 团队）；ONNX 导出 © Wasser1462；sherpa-onnx 打包 © k2-fsa",
        files: .qwen3ASR06BInt8,
        badge: "推荐",
        blurb: "错字少，认得“我的词”里的词。说完后整理结果用它，边说边显示的文字仍用轻量模型。",
        sizeNote: "解压后约 985 MB。识别时占用内存约 1.5～2.2 GB，闲置 10 分钟后释放。")

    static let senseVoiceSmallInt8 = SpeechModel(
        id: "sense-voice-zh-en-ja-ko-yue-int8-2025-09-09",
        displayName: "SenseVoice Small（int8，2025-09-09）",
        shortName: "轻量识别模型",
        engine: .senseVoice,
        archiveBytes: 165_783_878,
        sourceURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2")!,
        sha256: "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63",
        licenseName: "FunASR Model Open Source License Agreement v1.1",
        licenseURL: URL(string: "https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE")!,
        licenseSummary: [
            "这不是开源许可证，和本程序的 GPL-3.0 不同。",
            "允许使用、复制、修改、分享；要注明来源和作者，保留模型名。",
            "无正当理由诋毁、恶意抹黑该模型视为违约，自动失去授权（第 4.2 条）。",
            "协议可以单方修改，继续使用即视为接受新版本（第 6 条）。",
        ],
        attribution: "SenseVoice Small © FunAudioLLM / Alibaba Tongyi Lab；sherpa-onnx 转换版 © k2-fsa",
        files: .senseVoiceSmallInt8,
        blurb: "速度快，用来边说边显示文字；没装高精度模型时，最终结果也用它。")

    static let punctuationInt8 = SpeechModel(
        id: "punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8",
        displayName: "CT-Transformer 中英（int8，2024-04-12）",
        shortName: "标点模型",
        engine: .senseVoice,
        archiveBytes: 64_717_756,
        sourceURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2")!,
        sha256: "c0d5aa5f8eeb686032345e180bedf39319dc2e0556781c6264bcadba8328a6e1",
        // ModelScope lists the upstream model (iic/punc_ct-transformer_zh-cn-
        // common-vocab272727-pytorch, which sherpa-onnx converted) as
        // Apache License 2.0 (checked 2026-11-10).
        licenseName: "Apache License 2.0",
        licenseURL: URL(string: "https://modelscope.cn/models/iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch")!,
        licenseSummary: [
            "Apache-2.0 开源许可证（以 ModelScope 上原模型标注的许可证为准），可以自由使用、修改和分发。",
            "模型由阿里巴巴达摩院 FunASR 团队发布；这里用的是 sherpa-onnx 转换的 int8 版本。",
            "下载后只在这台 Mac 上运行，不联网。",
        ],
        attribution: "CT-Transformer 标点模型 © Alibaba DAMO Academy / FunASR；sherpa-onnx 转换版 © k2-fsa",
        files: .punctuationCTTransformerInt8)

    static let all: [SpeechModel] = [qwen3ASR06BInt8, senseVoiceSmallInt8, punctuationInt8]

    private static let qwenLicense = [
        "Apache-2.0 开源许可证，可以自由使用。",
        "模型由阿里巴巴通义千问团队发布；这里用的是 4 位量化（Q4_K_M）版本。",
        "下载后只在这台 Mac 上运行，不联网。",
    ]

    static func correction(_ model: LocalCorrectionModel) -> SpeechModel {
        switch model {
        case .qwen25_7b:
            return SpeechModel(
                id: "qwen2.5-7b-instruct-q4_k_m",
                displayName: "Qwen2.5-7B-Instruct（Q4_K_M）",
                shortName: "整理模型 · 标准",
                engine: .senseVoice,
                archiveBytes: 4_683_074_240,
                sourceURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf")!,
                sha256: "65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423",
                licenseName: "Apache License 2.0",
                licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct/blob/main/LICENSE")!,
                licenseSummary: qwenLicense,
                attribution: "Qwen2.5 © Alibaba Cloud；GGUF 量化 © bartowski",
                files: model.files,
                singleFile: model.fileName)
        case .qwen3_4b:
            return SpeechModel(
                id: "qwen3-4b-q4_k_m",
                displayName: "Qwen3-4B（Q4_K_M）",
                shortName: "整理模型 · 轻量",
                engine: .senseVoice,
                archiveBytes: 2_497_280_256,
                sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!,
                sha256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
                licenseName: "Apache License 2.0",
                licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-4B/blob/main/LICENSE")!,
                licenseSummary: qwenLicense,
                attribution: "Qwen3 © Alibaba Cloud",
                files: model.files,
                singleFile: model.fileName)
        }
    }
}
