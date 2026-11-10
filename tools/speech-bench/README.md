# 语音识别复测（speech-bench）

直接编译输入法里的识别代码（`ErgouIME/Speech/Qwen3Transcriber.swift`、`SenseVoiceTranscriber.swift`、`SpeechSegmenter.swift`、`TermStore.swift` 和 `Shared/`），在 Mac 上对录音跑一遍，结果用开发机上 asr-bench 的 `score2.py` 打分。顺带跑“我的词”规则的检查（`terms`，失败时退出码 1）。改识别器、热词规则或分段前后都跑一遍。

```sh
cd tools/speech-bench
./build.sh                    # 需要 vendor/sherpa-onnx（scripts/fetch-sherpa-onnx.sh）
./.speech-bench terms         # 我的词：校验、生效规则、排序、上限、编辑、坏文件
./run-bench.sh ~/Developer/asr-bench   # models/、segs/、rec.wav、hot100.txt
```

单独跑：

```sh
# 一个个文件（每个文件当一段）；热词可以是 "" / "a,b,c" / @文件
./.speech-bench asr qwen3 <模型目录> "二狗输入法,Claude" out/x.txt seg*.wav
# 一整段录音，按输入法的规则分段（停顿切分、静音段跳过、小声放大）
./.speech-bench session qwen3 <模型目录> "" out/y.txt rec.wav
```

FinalPass（输入法里的后台队列、加载、取消）按输入法的用法跑一遍：模型要在 `~/Library/Application Support/ErgouIME/Models/qwen3-asr/`（命令行程序没有 App Group，`Paths` 退回这里；要复制文件，不能用软链接，校验时会拒绝），跑完删掉这个目录。

```sh
./.speech-bench finalpass "二狗输入法,Claude" seg01.wav seg02.wav
```

输出：每段一行（文件、时长、耗时、文字），最后是总耗时和 RTF；`out/*.txt` 是拼起来的全文，作为 `score2.py` 的额外参数。2026-11-10 的结果见 docs/PLAN-v1.md M2.6。
