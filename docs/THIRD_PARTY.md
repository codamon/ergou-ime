# 第三方组件

除下表的组件外，仓库里的代码都是本项目自己写的，按 GPL-3.0 发布。第三方二进制、码表和模型都不进仓库（例外：由雾凇英文词库生成的 `RimeData/ergou_en.dict.yaml`，见下表），由 `scripts/` 在 Mac 上下载，下载时校验 SHA-256（码表固定到 git 提交）。

| 组件 | 版本 | 许可证 | 用途 | 获取方式 |
|---|---|---|---|---|
| [librime](https://github.com/rime/librime) | 1.17.0（`rime-33e7814-macOS-universal`） | BSD-3-Clause | 输入法引擎 | `scripts/fetch-librime.sh` |
| [librime-lua](https://github.com/hchunhui/librime-lua)（随 librime 1.17.0 预编译包，`rime-plugins/librime-lua.dylib`） | 同上 | BSD-3-Clause；Lua 解释器静态链接在插件里（Lua 是 MIT。librime-lua 的 CMake 优先用 `thirdparty/lua5.4`，其次系统的 lua5.4/5.3/5.2/LuaJIT/5.1；预编译包具体用哪个版本没有单独核实，不影响许可证） | 五笔拼音混输的 Lua 组件（自动上屏规则、五笔码提示、五笔容错） | `scripts/fetch-librime.sh`（只拷这一个插件） |
| [librime-octagram](https://github.com/lotem/librime-octagram)（随 librime 1.17.0 预编译包，`rime-plugins/librime-octagram.dylib`） | 同 librime | BSD-3-Clause | 整句模型插件：用下载的语言模型给整句打分 | `scripts/fetch-librime.sh` |
| [OpenCC](https://github.com/BYVoid/OpenCC) 数据（`rime-data/opencc/`，随 librime 预编译包） | 同 librime | Apache-2.0 | 简繁切换（`simplifier`，s2t） | `scripts/fetch-librime.sh`，由 `scripts/embed-vendor.sh` 打进安装包 |
| [rime-prelude](https://github.com/rime/rime-prelude) | `082425e` | LGPL-3.0 | Rime 基础配置（按键、标点、符号） | `scripts/fetch-rime-data.sh` |
| [rime-wubi86-jidian](https://github.com/KyleBing/rime-wubi86-jidian) | `4d08110` | MIT | 五笔 86 极点码表 | `scripts/fetch-rime-data.sh` |
| pinyin_simp 拼音词典（随 rime-wubi86-jidian） | `4d08110` | Apache-2.0（2026-11-10 核实：文件头写明派生自 AOSP [PinyinIME](https://android.googlesource.com/platform/packages/inputmethods/PinyinIME/)，该项目有 `MODULE_LICENSE_APACHE2`，NOTICE 为 “Copyright (c) 2009, The Android Open Source Project … Apache License, Version 2.0”；同一文件的上游 [rime/rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp) 也是 Apache-2.0）。随 rime-wubi86-jidian（MIT）一起获取 | 没下载拼音大词库时的拼音候选（回退用） | 同上 |
| [雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice) 英文词库：`en_dicts/en`、`en_ext`，约 2.2 万词 | git 提交 `99662ba01e3affa6a0f009174ca530b887bac3b6`（2026-10-31；`en.dict.yaml` SHA-256 `1049164d…ec44`，`en_ext.dict.yaml` `c8648c1d…06a2`） | GPL-3.0-only（同上）。`en.dict.yaml` 文件头写明来源：google-10000-english 的常见两万词、rime-melt 的英文词库 | 中英混输：打 `github` 出 GitHub。随安装包提供，不用下载 | `scripts/gen-english-dict.py` 生成 `RimeData/ergou_en.dict.yaml`（只留纯字母的词，大小写按 `tools/english-dict/casing.txt` 修正），生成结果进仓库 |
| [雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice) emoji 表：`opencc/emoji.txt` | git 提交 `99662ba01e3affa6a0f009174ca530b887bac3b6` | GPL-3.0-only（同上） | 候选里的 emoji：打“笑”出 😄。随安装包提供 | `scripts/gen-emoji-dict.py` 生成 `RimeData/opencc/ergou_emoji.txt`（只留汉字词，每个词最多 2 个 emoji、单字 1 个，去掉 macOS 13.0 画不出的新 emoji）。符号表 `ergou_symbols.txt` 来自我们自己写的 `tools/emoji/symbols.txt`。生成结果进仓库 |
| [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin) 部件拆字码表和拼写规则（© Mirtle；码表：开放词典 / henrysting / Mirtle），取自 rime-ice 同一提交里的 `radical_pinyin.dict.yaml`（版本 2026.06.18）和 `radical_pinyin.schema.yaml` | 同上 | GPL-3.0（仓库 LICENSE 与 README；2026-11-12 核实） | 拆字：拼音方案里按 `` ` `` 后用部件的拼音打字。随安装包提供 | `scripts/gen-radical-dict.py` 生成 `RimeData/ergou_radical.dict.yaml`（去掉注释）和 `ergou_radical.schema.yaml`（全拼和三种双拼的拼写规则），生成结果进仓库 |
| `lua/ergou/select_character.lua`（以词定字）参照 rime-ice 的 `lua/select_character.lua`（原作 [BlindingDark/rime-lua-select-character](https://github.com/BlindingDark/rime-lua-select-character)）重写 | 同上 | GPL-3.0-only（rime-ice） | 以词定字 | 源码在仓库里 |
| [雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice) 词库：`cn_dicts/8105`（字表）、`base`（基础）、`ext`（扩展），约 89 万条 | release `2026.06.30`（`cn_dicts.zip`，14.7 MB，SHA-256 `4e196199…4720`） | GPL-3.0-only（和本项目相同；2026-11-10 核实仓库 LICENSE 与 README“许可证”一节）。词条来源（华宇野风、THUOCL 等）写在 `base.dict.yaml` 文件头 | 拼音大词库：两个方案的拼音候选。可选的“腾讯词库”是同一压缩包里的 `tencent.dict.yaml`（约 98 万条，词表来源腾讯 AI Lab 中文词向量，随雾凇以 GPL-3.0 发布），单独下载、单独删除，只和拼音大词库一起用。41448、others 不用 | 用户在二狗输入法设置 › 输入 › 词库 里点击并确认后下载；没装时用 pinyin_simp |
| 整句模型 · 轻量：[rime-octagram-data](https://github.com/lotem/rime-octagram-data) `zh-hans-t-essay-bgw-compact.gram`（41 MB） | release `20260712` | LGPL-3.0 | 长句选词（和万象二选一） | 用户在设置 › 输入 › 词库和整句模型 里确认后下载 |
| 整句模型 · 万象：[RIME-LMDG](https://github.com/amzxyz/RIME-LMDG) `wanxiang-lts-zh-hans.gram`（418 MB） | release `LTS`（2025-12-07 发布；用的是作者 2026-11-10 重新上传的文件，SHA-256 `3457b69f…cde6`） | CC BY 4.0（仓库 LICENSE 与 LICENSE-SCOPE.md：自行维护的数据按 CC BY 4.0；2026-11-11 核实） | 同上 | 同上。作者会原地替换这个文件，所以下载地址是我们存的原样拷贝 `https://ergou-dl.signalhouse.nz/wanxiang/2026-11-10/wanxiang-lts-zh-hans.gram`（Cloudflare R2 桶 `ergou-models`，未改动；同目录的 `NOTICE.txt` 写明作者、许可证和来源）。换新文件时：传到新的日期目录，改 `ModelCatalog`、`SpeechModelFiles` 的地址和 SHA-256，旧目录留着给旧版本用 |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 2.0.1（osx-universal2-shared-no-tts） | Apache-2.0 | 离线语音识别运行时 | `scripts/fetch-sherpa-onnx.sh` |
| onnxruntime（随 sherpa-onnx） | — | MIT | 推理 | 同上 |
| [SenseVoice Small](https://huggingface.co/FunAudioLLM/SenseVoiceSmall) int8（sherpa-onnx 转换版 2025-09-09，约 158 MB） | — | 代码 MIT；**模型权重是 [FunASR 模型协议](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE) v1.1，不是开源许可证** | 语音转文字模型 | 用户在 二狗输入法设置 里点击并确认后下载（开发时用 `scripts/fetch-sensevoice-model.sh`） |
| CT-Transformer 中英标点模型（`sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8`，由 [iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch](https://modelscope.cn/models/iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch) 转换，压缩包约 65 MB） | 2024-04-12 | Apache-2.0（ModelScope 上原模型标注的许可证，2026-11-10 核实；HuggingFace 的 [funasr/ct-punc](https://huggingface.co/funasr/ct-punc) 也标 Apache-2.0） | 给 SenseVoice 的结果加标点（Qwen3-ASR 自带标点，不用它） | 用户在二狗输入法设置里点击并确认后下载 |
| [Qwen3-ASR 0.6B](https://github.com/QwenLM/Qwen3-ASR) int8（[Wasser1462](https://github.com/Wasser1462/Qwen3-ASR-onnx) 导出 ONNX，sherpa-onnx 打包 2026-03-25，压缩包 879 MB，解压后约 985 MB） | — | Apache-2.0 | 高精度语音转文字（说完后的最终结果；认“我的词”热词） | 用户在 二狗输入法设置 里点击并确认后下载 |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | b12211（arm64 与 x64 用 lipo 合成） | MIT | 语音整理的本机大模型推理，只在 ErgouIMECorrector（XPC，无网络权限）里 | `scripts/fetch-llama.sh` |
| Qwen2.5-7B-Instruct Q4_K_M（bartowski 量化）、Qwen3-4B Q4_K_M | — | Apache-2.0 | 语音整理模型，用户在设置里确认后下载，不随包分发 | 二狗输入法设置 |
| 联想词库（[librime-predict](https://github.com/rime/librime-predict) data-1.0 的 predict.txt，源自 rime-essay、rime-octagram-data） | data-1.0 | LGPL-3.0（数据）；转换用的 OpenCC 为 Apache-2.0 | 联想。转成简体、精简后存为只读 SQLite，打进安装包 | `scripts/fetch-predict.sh` |
| [rime-double-pinyin](https://github.com/rime/rime-double-pinyin) 的拼写规则和编码显示规则（preedit_format） | master | GPL-3.0 | 双拼（小鹤、自然码、微软） | 写在 `Shared/InputOptions.swift` |

## 参考：鼠鬚管 Squirrel

[Squirrel](https://github.com/rime/squirrel) 是 GPL-3.0，和本项目许可证兼容。目前只参考它的结构（IMK 配置、librime 接入方式），没有复制文件。

如果以后从 Squirrel 借用文件或大段代码：

1. 保留原文件开头的版权和许可证声明，不删不改；
2. 在文件开头加一行说明来源（仓库、提交号、原路径）和我们的改动；
3. 在本表加一行记录。

## 模型分发（结论）

SenseVoice 模型**只由用户在 二狗输入法设置 里点击并确认后下载，不随安装包分发，也不进仓库**。确认弹窗写明模型名、大小、来源网址、SHA-256 和 FunASR 模型协议要点（含第 4.2 条“不得诋毁”、第 6 条“可单方修改”）及全文链接；下载后校验 SHA-256。“关于”页展示署名和协议链接。

Whisper（MIT 权重）在 M6 前作为第二个识别引擎加入，以防 FunASR 协议改成不能接受的条款。

## 打包分发

- 已做（0.1.0）：随包分发的组件的许可证文本由 `scripts/embed-vendor.sh` 拷进 `ErgouIME.app/Contents/Resources/Licenses/`（来源见 [licenses/README.md](licenses/README.md)）。设置程序“关于”页还没有列出它们（M6 T6.4）。
- llama.cpp 只在 ErgouIMECorrector 里；它的 `LICENSE` 来自 `vendor/llama/`（`scripts/fetch-llama.sh`）。
