# 二狗输入法 Ergou IME

网站：<https://ergou.signalhouse.nz>

隐私优先的开源 macOS 中文输入法：拼音（全拼、双拼）、五笔 86 拼音混输、本机语音输入。打的字和说的话默认不出这台 Mac。

## 安装

从 [Releases](https://github.com/codamon/ergou-ime/releases) 下载 `ErgouIME-<版本>.pkg`（Developer ID 签名并经过苹果公证），双击安装（只装给当前用户，装到 `~/Library/Input Methods`）。然后：

1. 系统设置 → 键盘 → 输入法 → 编辑… → “+” → 简体中文 → **二狗**。列表里还没有就注销再登录一次。
2. 切到二狗输入法，第一次用时会弹出**新手引导**：选拼音还是五笔拼音混输，一键下载推荐的拼音大词库、整句模型和语音模型（列出大小、来源和许可证，点“下载”才下载），导入原来输入法的个人词库，试一下语音。都可以跳过，以后在输入法菜单 → “打开设置…”里改（“关于”页可以重新打开引导）。
3. 第一次说话时系统会询问麦克风权限；要在其他输入法下也能按右 Option 说话，还要在“隐私与安全性 → 输入监控”里打开二狗输入法。

更新：有新版本时会弹窗问你（每天最多检查一次，设置 › 关于 里可以关掉或手动检查），同意后下载、核对签名，再交给系统安装器安装，设置和词库都保留。也可以随时到 Releases 下载新的安装包直接装。

卸载：`bash uninstall.sh`（发布页附带，也在 `scripts/uninstall.sh`；加 `--all` 同时删除设置、词库和模型）。

要求 macOS 13 Ventura 或更新，Apple 芯片和 Intel 都支持（Universal）。隐私说明见 [PRIVACY.md](PRIVACY.md)，安全问题请按 [SECURITY.md](SECURITY.md) 私密报告。

## 目标

- **外壳**：Swift + InputMethodKit 写的原生 macOS 输入法
- **打字引擎**：[librime](https://github.com/rime/librime) + [雾凇拼音](https://github.com/iDvel/rime-ice) 词库（拼音大词库，在设置里下载）+ [rime-wubi86-jidian](https://github.com/KyleBing/rime-wubi86-jidian)（五笔 86 极点码表）
- **离线语音**：[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + [Qwen3-ASR 0.6B](https://github.com/QwenLM/Qwen3-ASR)（高精度，出最终结果，认“我的词”）+ SenseVoice Small（轻量，边说边显示），在本机完成语音转文字

## 程序组成

- **二狗输入法 `ErgouIME.app`**：输入法本体（拼音、五笔、语音、候选窗）。开 App Sandbox，**没有网络权限**，系统层面就不能联网。
- **二狗输入法设置 `ErgouIME Settings.app`**：嵌在 `ErgouIME.app/Contents/Library/LoginItems/` 里，从输入法菜单“打开设置…”打开。负责设置、下载语音模型和词库、检查更新。也开沙盒，有网络权限，只在你点按钮时、以及每天检查一次更新时联网。
- **两个辅助进程**（`ErgouIME.app/Contents/XPCServices/`，都开沙盒，用到时才启动，闲置后自己退出）：
  - `ErgouIMECorrector.xpc`：用 Apple 设备端模型或本机模型整理语音结果。**没有网络权限**。
  - `ErgouIMECloud.xpc`：云端整理。只有它（和设置程序）有网络权限，而且只有“发出连接”（network.client）一项；只在你选了“云端模型”时才会被调用。

两个程序通过 App Group 容器 `~/Library/Group Containers/<TeamID>.com.codamon.ergou/` 共享模型和设置。Rime 用户目录（词频、配置）只在输入法自己的沙盒容器里，Settings 不能写，输入法从校验过的设置自己生成配置（原因见 `docs/PLAN-v1.md` 的“数据位置”）。

## 隐私原则

这些规则写在 [`Shared/Privacy.swift`](Shared/Privacy.swift) 里，所有代码都要遵守：

1. **输入法本体从不联网**。没有网络权限（可以用 `codesign -d --entitlements - ErgouIME.app` 自己查），代码里也不用任何网络接口（`scripts/check-no-network.sh` 检查）。
2. **设置程序只在你主动操作和每天检查更新时联网，每一次都记在 设置 › 联网记录 里**：点“下载”、点“检查更新”；另外每天最多一次自动检查有没有新版本（默认打开，可以在 设置 › 关于 里关掉），只发一个请求问 GitHub，不带任何输入内容或设置。**下载和安装更新一定先问你**，安装包要核对签名和苹果公证。除此之外不在后台联网。
3. **模型要你确认才下载**：弹窗写明模型名、大小、来源和许可证，下载后校验 SHA-256。安装包和仓库里都不带模型。
4. **没有遥测**。日志只记事件，不记打的字、候选词、上屏内容和语音转写结果，只留在本机。
5. **从不读剪贴板**。只在你自己操作时写一次：全局语音识别完但当前没有输入框，这时把结果放进剪贴板，并弹出“已复制”提示；或者在“常用语”“语音记录”窗口里点“复制”（没有输入框时点“插入”也一样）。注意这会覆盖你原来复制的内容，剪贴板管理工具也会记下这段文字。
6. **密码框里不录音、不写剪贴板、不学习**。
7. **录音只在内存里**，本机识别完就丢掉，不写盘、不上传。
8. **自动调频默认打开**（常用字词排到前面），可以在设置里关掉或清空，数据只在本机。五笔拼音混输不自动造词，新词由你在设置里手动添加；只用拼音模式会记住你打过的词，存在它自己的词库里，不会混进五笔拼音混输。
9. **“我的词”只在本机**：你手动加的词存在共享设置里，学到的词由输入法写在 App Group 容器的 `Terms/learned-terms.json`，设置程序只读、不写，删除和固定是请输入法去改。两边读到的内容都重新校验（不收邮箱、网址、纯数字、像密码或验证码的串）。这些词用来提示本机的识别模型；只有打开云端整理时，每次请求会带上最多 50 个（见下一条）。词表文件本身从不上传。
10. **云端整理只在你选了才用**（设置 › 语音 › 自动整理 › 云端模型，默认不开）。选了之后是**边说边发**：录音过程中每说完一段（在停顿处切开）、这一段识别完，`ErgouIMECloud.xpc` 就把这一段的下列内容发给你选的服务（Anthropic 或你填的兼容 Anthropic 接口的 https 地址，或 OpenAI 兼容接口），不发给别处：
    - 这一段识别出的文字（录音从不发送）；
    - 当前 App 的名字；
    - 最多 50 个“我的词”；
    - 上文，合起来最多 200 字：这次前面几段的文字（它们本来也已发送），如果打开了“把光标前的文字一起发送”（选云端时默认打开），前面再加开始说话时光标前的文字。密码框、终端和密码管理器里不取光标前的文字；录音中途进入密码框就停止发送。

    所以文字在你说话的过程中就会发出，而不只是说完以后；按 Esc 会取消还在进行的请求，但已经发出的段收不回来。云端挑出的人名、产品名、术语会经过同样的校验，在文字打出去时存进本机的“我的词”。某一段出错，或说完 4 秒后还没回来，这一段就直接用本机识别的文字。日志只记耗时、状态码和字数。API Key 存在 App Group 容器的 `Cloud/api-key-<服务>` 文件里（目录 0700、文件 0600、不进备份），只有设置程序写、只有 `ErgouIMECloud.xpc` 读，输入法本体不读。没用钥匙串，是因为不带描述文件的 Developer ID 程序之间没法共享钥匙串条目（实测返回 -34018）；代价是这台 Mac 上以你的身份运行、不开沙盒的程序能读到这个文件（macOS 15 起，别的开发者的程序读之前系统会先问你）。在设置里点“删除”就把文件删掉。

## 第一版范围

1. 拼音（默认；整句、简拼、模糊音、容错、双拼，拼音大词库和整句模型在设置里下载），五笔打字（自动调频，不自动造词），五笔拼音混输（拼音候选显示五笔码、模糊音、容错；先按 `` ` `` 只打拼音），Shift 中英切换
2. 点一下右 Option 开始说话、再点一下结束（全局生效），本机识别后直接上屏；没有输入框时复制到剪贴板并提示
3. 候选窗口
4. 设置程序：模型和词库下载、手动导入、检查更新（每天自动检查一次，可关；安装前征得同意）

设计结论见 [docs/DESIGN.md](docs/DESIGN.md)，里程碑 M0–M6 和任务拆分见 [docs/PLAN-v1.md](docs/PLAN-v1.md)。

## 目录

```
site/                    网站 ergou.signalhouse.nz（纯静态，Cloudflare Pages 项目 ergou；改完用
                         `npx wrangler pages deploy site --project-name ergou --branch main` 发布）
project.yml              XcodeGen 工程描述（.xcodeproj 不进仓库）
Config/                  Common / ErgouIME / ErgouIMESettings 的 xcconfig；
                         Team ID 和可选依赖由生成的 Local.xcconfig 提供（不进仓库）
ErgouIME/                输入法本体
  App/                   main.swift（启动 IMKServer）、输入源注册
  Controller/            IMKInputController 子类（含输入法菜单）
  Engine/                InputEngine 接口、直通引擎、librime 引擎、按键映射、Rime 配置生成
  Speech/                语音：录音、分段、SenseVoice（边说边显示）和 Qwen3-ASR（最终结果）、我的词
  UI/                    候选窗口（占位）
  Support/               密码框检测、打开设置程序
  Supporting/            Info.plist、entitlements、bridging header
  Resources/             菜单栏图标
RimeData/                自己的 Rime 方案（ergou_pinyin_ime 拼音、ergou_wubi 五笔拼音混输、ergou_pinyin 拼写、
                         ergou_pinyin_dict 拼音词典入口）和 lua/ergou 脚本
ErgouIMESettings/        设置程序（SwiftUI）：通用（调频、混输、模糊音、容错）、语音（模型、我的词、自动整理）、关于
ErgouIMECorrector/       辅助进程：本机整理（Apple 设备端模型、llama.cpp），不联网
ErgouIMECloud/           辅助进程：云端整理（Anthropic / OpenAI 兼容接口），只有 network.client
CloudShared/             云端 API Key 文件，只编进设置程序和 ErgouIMECloud
Shared/                  各程序共用：隐私规则、日志、路径、共享设置和通知、设置校验、云端整理的提示词和结果校验
scripts/                 在 Mac 上运行：下载依赖、生成工程、安装、发布（release.sh）、卸载
docs/                    设计、计划、第三方说明和随包分发的许可证文本
```

## 在 Mac 上编译

需要 macOS 13+、Xcode 15+、[Homebrew](https://brew.sh)，以及 Apple Developer 账号（签名用，不用 ad-hoc 签名：ad-hoc 每次重编都会让输入监控和麦克风授权失效）。

```sh
brew install xcodegen
git clone https://github.com/codamon/ergou-ime.git && cd ergou-ime

export ERGOU_TEAM_ID=XXXXXXXXXX  # 你的 Team ID（Xcode → Settings → Accounts），只写进不进仓库的 Config/Local.xcconfig
./scripts/bootstrap.sh           # 只编直通版（直接上屏英文），不下载任何东西
# 或者
./scripts/bootstrap.sh --rime    # 加上 librime + 五笔码表
./scripts/bootstrap.sh --all     # 再加上 sherpa-onnx + SenseVoice 模型（约 158 MB，开发用；用户在设置程序里下载，高精度的 Qwen3-ASR 也在设置里下载）

open ErgouIME.xcodeproj          # 用 Xcode 编译；或者直接：
./scripts/install.sh             # 编译 Debug 版并装到 ~/Library/Input Methods
```

第一次安装后，系统可能要**注销再登录**才会列出新的输入源。然后在“系统设置 → 键盘 → 输入法”里添加“简体中文 → 二狗输入法”。

改了 `project.yml` 或者新增了源文件，要重新跑 `xcodegen generate`；下载或删除了依赖，要重新跑 `./scripts/configure.sh`。

Debug 只编当前架构；Release 编 Universal（arm64 + x86_64）。

调试日志：`log stream --predicate 'subsystem BEGINSWITH "com.codamon"'`。

检查输入法本体和本机整理进程没有联网能力、云端整理进程只有 network.client：`./scripts/check-no-network.sh`（编译后加上 app 路径，还会检查签名里的权限和导入的符号）。

云端整理的离线检查和真实调用：`tools/cloud-bench/build.sh && tools/cloud-bench/.cloud-bench tests`（`call` 用法见 `tools/cloud-bench/main.swift`，Key 从标准输入读）。

## 发布安装包

维护者在 Mac 上运行 `./scripts/release.sh`：Developer ID 签名（Hardened Runtime、安全时间戳，嵌套代码由内向外签）、打 `.pkg`（Developer ID Installer 签名）、`notarytool` 公证并 staple，产出 `build/release/ErgouIME-<版本>.pkg` 和 SHA-256。签名钥匙串和公证配置的位置见 `scripts/lib/common.sh` 的 `load_signing_env`，不进仓库。

## 第三方组件

见 [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md)。本项目参考了[鼠鬚管 Squirrel](https://github.com/rime/squirrel)（GPL-3.0）的做法，目前没有直接复制它的文件；以后如果借用，会保留原文件的版权声明。

## 许可证

[GPL-3.0-only](LICENSE)。语音模型另有许可证，见 [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md)。
