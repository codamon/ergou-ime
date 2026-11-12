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
    /// Set when `sourceURL` is our own unchanged copy: where the publisher
    /// has the file. Shown next to the download address.
    var originURL: URL? = nil
    let licenseName: String
    let licenseURL: URL
    /// Plain-language summary shown in the confirmation dialog.
    let licenseSummary: [String]
    let attribution: String
    /// Files expected after unpacking, with their SHA-256 (shared with the
    /// input method, which checks them again before loading).
    let files: SpeechModelFiles
    /// nil: an archive (.tar.bz2 or .zip) to unpack. Otherwise the download
    /// is this one file.
    var singleFile: String? = nil
    /// Tag after the name in the model list ("推荐").
    var badge: String? = nil
    /// One line under the name in the model list.
    var blurb: String? = nil
    /// Extra size information for the dialog (unpacked size, memory).
    var sizeNote: String? = nil
    /// "模型" or "词库", used in the download dialog.
    var kind = "模型"
    /// Shown in the dialog once installed. nil: "已安装，马上就能用。"
    var installedNote: String? = nil
    /// Tell the input method to redeploy Rime after installing or deleting
    /// (the pinyin dictionary).
    var redeploysRime = false
    /// The input method takes the downloaded file and deletes it (整句模型,
    /// GrammarModel.swift); only VERSION stays, so that is what "installed"
    /// means.
    var handedToInputMethod = false
    /// Removed after this one is installed (整句模型: one of two).
    var replaces: [SpeechModelFiles] = []

    var isInstalled: Bool {
        handedToInputMethod
            ? FileManager.default.fileExists(atPath: files.directory.appendingPathComponent("VERSION").path)
            : files.isPresent
    }
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

    /// 拼音大词库 (雾凇拼音). The release archive also holds tencent, 41448 and
    /// others; only 8105 + base + ext are kept (SpeechModelFiles).
    static let pinyinDictionary = SpeechModel(
        id: "rime-ice-cn-dicts-2026.06.30",
        displayName: "雾凇拼音词库 2026.06.30（字表 + 基础 + 扩展，约 89 万词）",
        shortName: "拼音大词库",
        engine: .senseVoice,
        archiveBytes: 14_715_121,
        sourceURL: URL(string: "https://github.com/iDvel/rime-ice/releases/download/2026.06.30/cn_dicts.zip")!,
        sha256: "4e19619920f901cf900a33142ac0d10586787cdaf577a5b106da2cc078a84720",
        licenseName: "GNU GPL-3.0",
        licenseURL: URL(string: "https://github.com/iDvel/rime-ice/blob/main/LICENSE")!,
        licenseSummary: [
            "GPL-3.0 开源许可证，和本程序相同，可以自由使用、修改和分发。",
            "雾凇拼音是长期维护的开源简体拼音词库；词条来源（华宇野风词库、清华大学 THUOCL、腾讯词向量等）写在词库文件开头。",
            "只是词表，没有可执行的内容。下载后输入法会再校验一遍，只在这台 Mac 上使用。",
        ],
        attribution: "雾凇拼音 © iDvel 及贡献者",
        files: .pinyinDictRimeIce,
        badge: "推荐",
        blurb: "约 89 万词，比自带的词库（约 8 万词）全得多，新词、日常短语和整句都更准。拼音和五笔拼音混输都用它。",
        sizeNote: "解压后约 28 MB。装好后输入法第一次重新部署要多花一点时间，这期间先打出英文。",
        kind: "词库",
        installedNote: "已安装。输入法正在重新部署，稍等片刻就换成大词库。",
        redeploysRime: true)

    /// 整句模型, one of two (only one grammar can be active). Measured on 121
    /// everyday clauses with 拼音大词库: whole clause right 65 % → 81 %
    /// (轻量) / 83 % (万象); peak memory 37 → 76 / 391 MB.
    static let grammarCompact = SpeechModel(
        id: "rime-octagram-zh-hans-bgw-compact-20260712",
        displayName: "Rime 官方整句模型 zh-hans-t-essay-bgw-compact（2026-07-12）",
        shortName: "整句模型 · 轻量",
        engine: .senseVoice,
        archiveBytes: 40_925_228,
        sourceURL: URL(string: "https://github.com/lotem/rime-octagram-data/releases/download/20260712/zh-hans-t-essay-bgw-compact.gram")!,
        sha256: "d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e",
        licenseName: "GNU LGPL-3.0",
        licenseURL: URL(string: "https://github.com/lotem/rime-octagram-data/blob/master/LICENSE")!,
        licenseSummary: [
            "LGPL-3.0 开源许可证，可以自由使用和分发。",
            "Rime 作者佛振维护的语言模型数据，按词与词的搭配给整句打分。",
            "只是数据，没有可执行的内容。下载后输入法会再校验一遍，只在这台 Mac 上使用。",
        ],
        attribution: "rime-octagram-data © 佛振（lotem）及 RIME 开发者",
        files: .grammarCompact,
        singleFile: "zh-hans-t-essay-bgw-compact.gram",
        badge: "推荐",
        blurb: "整句输入更准：实测整句全对从 65% 提到 81%。打字时多占约 40 MB 内存。和“万象”二选一。",
        sizeNote: "约 41 MB。输入法会把它拷进自己的目录并删掉下载的原文件，所以只占一份空间。打字时多占约 40 MB 内存。",
        kind: "模型",
        installedNote: "已安装。输入法正在重新部署，稍等片刻就生效。",
        redeploysRime: true,
        handedToInputMethod: true,
        replaces: [.grammarWanxiang])

    static let grammarWanxiang = SpeechModel(
        id: "rime-lmdg-wanxiang-lts-zh-hans-2025-12-07",
        displayName: "万象整句模型 wanxiang-lts-zh-hans（RIME-LMDG LTS，2026-11-10 的文件）",
        shortName: "整句模型 · 万象",
        engine: .senseVoice,
        archiveBytes: 418_071_596,
        // Our unchanged copy (Cloudflare R2, see docs/THIRD_PARTY.md): the
        // publisher replaces the "LTS" file in place (2026-11-10), after
        // which every download failed the SHA-256 check until a new release
        // of ours. scripts/check-model-urls.py reports when the two differ.
        sourceURL: URL(string: "https://ergou-dl.signalhouse.nz/wanxiang/2026-11-10/wanxiang-lts-zh-hans.gram")!,
        sha256: "3457b69f5fe0fc4f5d211c878bbfa2e2361b90639952c9845c8e31e9d047cde6",
        originURL: URL(string: "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram")!,
        licenseName: "CC BY 4.0",
        licenseURL: URL(string: "https://github.com/amzxyz/RIME-LMDG/blob/wanxiang/LICENSE")!,
        licenseSummary: [
            "CC BY 4.0（知识共享署名）：可以自由使用和分发，要注明作者。",
            "万象拼音（amzxyz）训练的大语言模型数据，整句略准于轻量模型。",
            "只是数据，没有可执行的内容。下载后输入法会再校验一遍，只在这台 Mac 上使用。",
        ],
        attribution: "RIME-LMDG 万象语言模型 © amzxyz，CC BY 4.0",
        files: .grammarWanxiang,
        singleFile: "wanxiang-lts-zh-hans.gram",
        blurb: "比轻量模型略准（实测整句全对 83%，轻量 81%），但打字时要多占约 350 MB 内存，内存小的 Mac 不建议。和“轻量”二选一。",
        sizeNote: "约 418 MB。⚠️ 打字时要多占约 350 MB 内存（实测峰值 391 MB，不用模型时 37 MB）；8 GB 内存的 Mac 建议用轻量模型。输入法会把它拷进自己的目录并删掉下载的原文件，所以只占一份空间。",
        kind: "模型",
        installedNote: "已安装。输入法正在重新部署，稍等片刻就生效。",
        redeploysRime: true,
        handedToInputMethod: true,
        replaces: [.grammarCompact])

    /// Optional extra for 拼音大词库: rime-ice's tencent.dict.yaml, from the
    /// same archive (downloaded again, only this file kept).
    static let pinyinDictionaryTencent = SpeechModel(
        id: "rime-ice-tencent-2026.06.30",
        displayName: "雾凇拼音 · 腾讯词库 2026.06.30（约 98 万词）",
        shortName: "腾讯词库",
        engine: .senseVoice,
        archiveBytes: pinyinDictionary.archiveBytes,
        sourceURL: pinyinDictionary.sourceURL,
        sha256: pinyinDictionary.sha256,
        licenseName: pinyinDictionary.licenseName,
        licenseURL: pinyinDictionary.licenseURL,
        licenseSummary: [
            "GPL-3.0 开源许可证，和本程序相同（随雾凇拼音发布）。",
            "词条整理自腾讯 AI Lab 的中文词向量词表，多是常见词、新词和各种名称。",
            "只是词表，没有可执行的内容。下载后输入法会再校验一遍，只在这台 Mac 上使用。",
        ],
        attribution: "雾凇拼音 © iDvel 及贡献者；词表来源：腾讯 AI Lab 中文词向量",
        files: .pinyinDictTencent,
        blurb: "可选。在拼音大词库之外再加约 98 万词，多是新词、专有名词和名称；常用词已经在大词库里了，加上后冷僻候选也会多一些。",
        sizeNote: "和拼音大词库是同一个压缩包，只留腾讯词库，解压后约 17 MB。重新部署和占用内存都会多一些。",
        kind: "词库",
        installedNote: "已安装。输入法正在重新部署，稍等片刻就生效。",
        redeploysRime: true)

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
