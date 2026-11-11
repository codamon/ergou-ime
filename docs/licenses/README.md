# 随安装包分发的第三方组件许可证

`scripts/embed-vendor.sh` 把这个目录（除本文件外）和 `vendor/llama/LICENSE`、仓库根目录的 `LICENSE` 一起拷进 `ErgouIME.app/Contents/Resources/Licenses/`。组件列表和用途见 [../THIRD_PARTY.md](../THIRD_PARTY.md)。

| 文件 | 组件 | 来源 |
|---|---|---|
| librime.txt | librime 1.17.0（BSD-3-Clause） | rime/librime@1.17.0 `LICENSE` |
| librime-lua.txt | librime-lua（BSD-3-Clause） | hchunhui/librime-lua `LICENSE` |
| librime-octagram.txt | librime-octagram（BSD-3-Clause），整句模型插件，随 librime 1.17.0 预编译包 | lotem/librime-octagram `LICENSE` |
| lua.txt | Lua（MIT），静态链接在 librime-lua 里 | lua/lua@v5.4.6 `lua.h` 末尾的许可证 |
| opencc.txt | OpenCC 数据（Apache-2.0） | BYVoid/OpenCC `LICENSE` |
| sherpa-onnx.txt | sherpa-onnx 2.0.1（Apache-2.0） | k2-fsa/sherpa-onnx@v2.0.1 `LICENSE` |
| onnxruntime.txt | onnxruntime（MIT） | microsoft/onnxruntime `LICENSE` |
| pinyinime.txt | pinyin_simp 词典的来源 AOSP PinyinIME（Apache-2.0） | AOSP PinyinIME `NOTICE` |
| rime-essay.txt | 联想词库数据（LGPL-3.0，源自 rime-essay、rime-octagram-data） | rime/rime-essay `LICENSE` |
| librime-predict.txt | 联想词库的发布者 librime-predict（BSD-3-Clause） | rime/librime-predict `LICENSE` |

rime-prelude（LGPL-3.0）和 rime-wubi86-jidian（MIT）的许可证由 `scripts/fetch-rime-data.sh` 放在 `rime-data/` 里，随码表一起打包。

雾凇拼音的英文词库（GPL-3.0，生成为 `RimeData/ergou_en.dict.yaml` 随方案打包）和本项目同一许可证，许可证文本就是根目录的 `LICENSE`；来源提交和作者见 [../THIRD_PARTY.md](../THIRD_PARTY.md) 和词典文件头。
