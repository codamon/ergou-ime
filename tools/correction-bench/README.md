# 语音纠错对比

同一份提示词（`Shared/CorrectionPrompt.swift`）、同一组句子（`samples.json`，D 的真实识别结果加几句典型错误），对比各个纠错模型。改提示词或换模型前后都要跑一遍。

在 Mac 上：

```sh
cd tools/correction-bench
# 本机模型（需要 scripts/fetch-llama.sh 和一个 .gguf）
swiftc -O -D ERGOU_WITH_LLAMA -o .llama-bench llama/main.swift ../../ErgouIMECorrector/LlamaCorrector.swift ../../Shared/CorrectionPrompt.swift \
  -import-objc-header bridge.h -I../../vendor/llama/include -L../../vendor/llama/lib -lllama \
  -Xlinker -rpath -Xlinker "$PWD/../../vendor/llama/lib"
./.llama-bench /path/to/model.gguf samples.json
# Apple 设备端模型（macOS 26+，需要打开 Apple 智能）
swiftc -O -parse-as-library -o .apple-bench apple-bench.swift ../../Shared/CorrectionPrompt.swift
./.apple-bench samples.json
```

2026-11-09 在 D 的 MacBook Pro 上的结果见 docs/PLAN-v1.md M2.5。
