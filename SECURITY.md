# 安全问题报告 / Security Policy

## 怎么报告

请**不要**在公开的 Issue 里报告安全问题。

请用 GitHub 的私密漏洞报告：在本仓库页面点 **Security → Report a vulnerability**（GitHub Security Advisories）。报告只有维护者能看到。

请尽量写明：

- 受影响的版本（设置 › 关于 里的版本号）和 macOS 版本；
- 问题是什么、怎么复现；
- 可能的影响（例如：输入法本体或本机整理进程能联网、密码框里会录音或学习、别的程序能把代码注入输入法、云端整理发出了说明以外的内容、API Key 泄露）。

请不要在报告里附上你真实的 API Key、录音或私人文字。

## 我们会怎么处理

- 尽快确认收到，并告诉你初步判断；
- 修复后发布新版本，在发布说明里致谢（如果你愿意）；
- 修复发布前请不要公开细节。

## 范围

最在意的是 [PRIVACY.md](PRIVACY.md) 和 [`Shared/Privacy.swift`](Shared/Privacy.swift) 里的承诺被打破的情况。第三方组件（librime、sherpa-onnx、llama.cpp 等）本身的漏洞请同时报告给上游。

## Reporting (English)

Please report security issues privately through GitHub Security Advisories (**Security → Report a vulnerability** on this repository), not in public issues. Include the version, macOS version, steps to reproduce and impact. Do not include real API keys, recordings or private text.
