# 隐私说明

二狗输入法（Ergou IME）是开源的 macOS 中文输入法。你打的字和说的话都只属于你。这份说明讲清楚它做什么、不做什么、什么时候会联网、联网时发出什么、数据存在哪里、怎么删除。代码里的对应规则在 [`Shared/Privacy.swift`](Shared/Privacy.swift)，评审代码时以它为准。

## 由哪几个程序组成

| 程序 | 网络权限 | 做什么 |
|---|---|---|
| 输入法本体 `ErgouIME.app` | **没有**（App Sandbox，系统层面禁止联网） | 打字、录音、本机语音识别、候选窗、上屏 |
| 本机整理进程 `ErgouIMECorrector.xpc` | **没有** | 用 Apple 设备端模型或本机大模型整理语音结果 |
| 云端整理进程 `ErgouIMECloud.xpc` | 只有“发出连接”（network.client） | 只在你选了“云端模型”时，把识别出的文字发给你选的服务 |
| 设置程序 `ErgouIME Settings.app`（二狗输入法设置） | 有 | 设置界面、你点“下载”时下载模型和拼音大词库、检查和下载更新 |

可以自己核对：`codesign -d --entitlements - ~/Library/Input\ Methods/ErgouIME.app`。仓库里的 `scripts/check-no-network.sh` 会检查源码和签名后的权限。

## 不做什么

- **没有遥测**，没有统计 SDK，不上报任何使用数据。
- **从不读剪贴板**，没有剪贴板历史。
- **不录音存盘**：录音只在内存里，本机识别完就丢掉，不写临时文件，也不上传。
- **密码框里**不录音、不写剪贴板、不出候选、不学习；录音中途进入密码框，录音在一秒内停止并丢弃。
- **日志**只记事件和耗时，不记你打的字、候选、上屏内容和识别结果，只留在本机。
- **不同步**：词库、设置、我的词都不上传，也不提供云同步。
- 输入法本体不联网、不下载任何东西。每天的更新检查由它叫起设置程序去做（见下一节），它自己只看一下时间。

## 什么时候联网

只有下面这几种情况。除了第 2 条里每天一次的自动检查，都要你自己操作；自动检查可以关掉，而且下载、安装更新一定先问你：

1. **下载语音模型、拼音大词库和整句模型**：你在设置里点“下载”，确认弹窗（写明名称、大小、来源网址、许可证）后，或者在新手引导的下载页（每一项都列出名称、大小、来源网址、许可证和 SHA-256）勾选后点“下载”，设置程序从弹窗里写的地址（GitHub Releases、Hugging Face）下载，下载后校验 SHA-256。除了正常的 HTTPS 请求，不发送任何别的数据。拼音大词库（雾凇拼音）装好后，输入法把它拷进自己的目录、再校验一遍才使用。
2. **检查更新**（自动检查**默认打开**，可以在 设置 › 关于 › 自动检查更新 里关掉）：
   - **什么时候**：你用输入法时，如果离上次检查超过 24 小时，输入法在后台启动设置程序去查一次；也可以在 设置 › 关于 里点“检查更新…”。输入法本体始终没有网络权限。
   - **发出什么**：设置程序向 `api.github.com` 发**一个** HTTPS 请求，问本仓库的最新发布。请求里没有你打的字、设置、词库或任何标识，只有 GitHub 要求的 User-Agent（`ErgouIME-Settings/<当前版本号>`）；和所有联网一样，GitHub 能看到你的 IP 地址。不带 Cookie，不缓存。
   - **没有新版本**：设置程序直接退出，不弹窗。
   - **有新版本**：弹出窗口（不抢键盘焦点），写明新版本号、大小和更新说明。你点“下载并安装”之前**什么都不下载**；也可以选“以后再说”（第二天再提醒）或“跳过这个版本”。
   - **同意之后**：从 GitHub Releases 下载 `ErgouIME-<版本>.pkg` 和它的 `.sha256`，核对 SHA-256、核对安装包是**同一个开发者**（同一个 Apple Team ID）用 Developer ID 签名并经过**苹果公证**的，任何一项不对就丢弃。核对通过后交给系统“安装器”，你在安装器里再确认一次才会安装。安装时输入法和设置程序会自动重启，设置、词库、调频记录和模型都保留。
3. **云端整理**（默认关闭）：只在你在 设置 › 语音 › 自动整理 里选了“云端模型”并填了 API Key 时才用，见下一节。

**每一次联网都能看到**：设置 › 联网记录 列出二狗每一次联网的时间、用途、服务器、发出了什么（只记数量和字数，不记内容）、收发字节数和结果，保留最近 1000 条（文件里最多留到 1500 条就裁剪一次），可以清空。下载在开始时先记一条“开始”，结束时再记结果，所以下到一半退出也查得到。记录由联网的程序自己写；想独立核对，可以在终端运行 `nettop`，或用 Little Snitch、LuLu 这类防火墙看二狗的连接。

**导入个人词库不联网**：设置 › 输入 › 个人词库 › 导入… 只在本机读你选的那一个文件（沙盒只给“读取你选的文件”的权限），导入的词存在本机，见下面“数据存在哪里”。

## 云端整理会发出什么

选了“云端模型”后是**边说边发**：录音过程中每说完一段（在停顿处切开）、这一段识别完，`ErgouIMECloud.xpc` 就把这一段的下列内容发给你选的服务（Anthropic 官方接口、你填的兼容 Anthropic 接口的 https 地址，或 OpenAI 兼容的 https 地址），不发给别处：

- 这一段识别出的文字（**录音从不发送**）；
- 当前 App 的名字（例如“备忘录”）；
- 最多 50 个“我的词”（帮模型认专有名词）；从你的修改里学到的词（“你改过”）不发，除非你自己在设置里也加了这个词；
- 上文，合起来最多 200 字：这次前面几段的文字（它们本来也已发送）；如果打开了“把光标前的文字一起发送”（选云端时默认打开），前面再加开始说话时**光标前的文字**。密码框、终端和密码管理器里不取光标前的文字；录音中途进入密码框就停止发送。

注意：

- 文字在你说话的过程中就发出去了，而不只是说完以后。按 Esc 会取消还在进行的请求，但已经发出的段收不回来。
- 数据到了服务方以后怎么处理，由你和那个服务之间的协议决定，二狗输入法管不了。用转发服务时，转发方也能看到这些内容。
- 某一段出错，或说完 4 秒后还没回来，这一段就直接用本机识别的文字。日志只记耗时、状态码和字数。
- 云端挑出的人名、产品名、术语会经过校验，在文字打出去时存进本机的“我的词”。

### API Key 存在哪里

API Key 存在 App Group 容器的 `Cloud/api-key-<服务>` 文件里（目录 0700、文件 0600、不进时间机器备份）。只有设置程序写，只有 `ErgouIMECloud.xpc` 读，输入法本体不编进读取 Key 的代码。

为什么不用钥匙串：不带描述文件（provisioning profile）的 Developer ID 程序之间没法共享钥匙串条目（实测返回 -34018）。代价是：这台 Mac 上以你的身份运行、**不开沙盒**的程序能读到这个文件（macOS 15 起，别的开发者的程序读之前系统会先问你）。在设置里点“删除”就把文件删掉。如果你介意，就不要用云端整理，或者用权限受限、可随时作废的 Key。

## 剪贴板

只在你自己操作时**写入**一次，从不读取：

- 全局语音识别完，但当前没有输入框：结果放进剪贴板，并弹出“已复制”提示；
- 在“常用语”“语音记录”窗口里点“复制”，或没有输入框时点“插入”。

代价：这会覆盖你原来复制的内容；如果装了剪贴板管理工具，它会记下这段文字。

## 数据存在哪里

全部在这台 Mac 上，`<TeamID>` 是发布者的 Apple Team ID：

| 内容 | 位置 |
|---|---|
| 导入的个人词库 | `~/Library/Group Containers/<TeamID>.com.codamon.ergou/Imported/pinyin-words.txt`（输入法再校验一遍后生成 Rime 目录里的 `ergou_imported*.dict.yaml`） |
| 联网记录 | `~/Library/Group Containers/<TeamID>.com.codamon.ergou/NetworkLog/network-log.jsonl` |
| 设置、常用语、手动添加的“我的词” | `~/Library/Group Containers/<TeamID>.com.codamon.ergou/Library/Preferences/` |
| 下载的更新安装包（超过一小时的在下次检查更新时删除） | `~/Library/Containers/com.codamon.ErgouSettings/Data/Library/Application Support/ErgouIME/Updates/` |
| 下载的模型和拼音大词库 | `~/Library/Group Containers/<TeamID>.com.codamon.ergou/Models/`（拼音大词库在 `Models/pinyin-dict/`，可选的腾讯词库在 `Models/pinyin-dict-tencent/`，整句模型在 `Models/grammar-compact/` 或 `Models/grammar-wanxiang/`（输入法拷走并校验后，下载的原文件会删掉，只留 `VERSION`），输入法用的校验过的副本在下面 Rime 目录的 `cn_dicts/`） |
| 语音模型、本机整理模型的校验副本（APFS 克隆，原文件还在时不多占空间；原文件删除后随之删除） | `~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Application Support/ErgouIME/VerifiedModels/`，本机整理模型在 `com.codamon.inputmethod.Ergou.Corrector` 的同名目录 |
| 学到的“我的词” | `~/Library/Group Containers/<TeamID>.com.codamon.ergou/Terms/learned-terms.json` |
| 云端 API Key | `~/Library/Group Containers/<TeamID>.com.codamon.ergou/Cloud/` |
| 调频记录、用户词库（Rime） | `~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Application Support/ErgouIME/Rime/` |
| 从修改里学到的词对（可关闭） | `~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Application Support/ErgouIME/voice-corrections.json` |
| 语音记录（最近 200 条、30 天，可关闭） | `~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Application Support/ErgouIME/voice-history.json` |
| 每个 App 的中/英状态 | `~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Preferences/` |

**从我的修改里学习**（设置 › 语音 › 语音记录，默认打开）：语音结果打进输入框后，输入法在本机读这段文字，以及它前面约 16 个字符、后面约 80 个字符，最多 60 秒、每秒最多一次，只放在内存里，按回车、Tab、Esc、离开输入框、下一次语音或到 60 秒就丢掉。存下来的只有“听成什么 → 改成什么”这一对词（同样的修改出现两次才自动替换），改成的词也进“我的词”，只在本机当热词用，不发给云端整理。密码框里从不读取、从不学习。在“我的词”里删掉一个词，学到的对应词对也一起删掉。

语音记录不存看起来像密码、验证码、密钥的内容。Rime 用户目录只有输入法本体能写；设置程序（有网络权限）写不进去，防止有人借它把脚本注入能看到按键的输入法进程。

## 这套防护的边界

输入法把设置程序当成不可信的一方：它写的设置逐项校验；下载的词库、整句模型、语音模型都不直接使用，而是先拷贝（克隆）进各进程自己的目录，按代码里写死的 SHA-256 校验副本，只加载副本；“清空”这类请求必须先写进共享设置，输入法才执行，光发一个系统通知不算数。

做不到的也要说清楚：云端整理开不开、发给哪个服务，本来就是设置程序替你保存的选项，输入法照着用。所以如果设置程序被攻破，或者这台 Mac 上有别的程序能写二狗的共享目录（不开沙盒、以你的身份运行的程序可以；macOS 15 起别的开发者的程序读写前系统会先问你），它可以打开云端整理并把地址指向自己的服务器，之后说的话会被发过去。能看到的迹象是语音浮窗上的“云端整理中”和联网记录（同一个攻击者也能清掉记录）。输入法本体仍然联不了网，打字内容不受影响。

## 怎么删除

- 设置里：清空调频记录/用户词库、清空语音记录（也可以关掉语音记录）、删除“我的词”（从修改里学到的词对随之删除；也可以关掉“从我的修改里学习”）、删除云端 Key。
- 拼音大词库、腾讯词库、整句模型：设置 › 输入 › 词库和整句模型 › 删除。
- 个人词库：设置 › 输入 › 个人词库 › 清空。联网记录：设置 › 联网记录 › 清空。
- 模型：设置里暂时没有删除按钮，直接删除上表 `Models/` 下对应的文件夹即可；各进程自己的校验副本（见上表）会在输入法下次启动或下次用到语音时自动删除。
- 卸载并删除全部数据：`bash uninstall.sh --all`（发布页附带，也在仓库 `scripts/uninstall.sh`），会先列出要删的目录再询问。
- 麦克风和输入监控的授权：系统设置 › 隐私与安全性 里移除。

## 权限

- **麦克风**：语音输入要用。只在你按右 Option 开始说话后录音。
- **输入监控**：只在打开“在其他输入法下也能用”时要。只监听、不拦截按键，只用来看右 Option 有没有被按下，不记录、不改动任何按键。
- 不申请辅助功能、通讯录、位置等权限。

---

## Summary (English)

Ergou IME is an open-source Chinese input method for macOS. The input method and its local correction service have **no network entitlement** (App Sandbox). There is no telemetry, the clipboard is never read, audio stays in memory and is never written to disk or uploaded, and nothing is recorded or learned in password fields. Logs never contain typed or dictated text.

The network is used only for what you asked for: the Settings app downloads a model or dictionary after you confirm (name, size, source, licence; verified with SHA-256); once a day at most it asks api.github.com whether there is a newer version (on by default, can be turned off; nothing is downloaded or installed without your consent, and the package's Developer ID signature and notarisation are checked); and — only if you turn on the optional **cloud tidy-up** and enter an API key — `ErgouIMECloud.xpc` sends, per recognised segment while you speak: the segment's text (never audio), the current app's name, up to 50 of your terms (never the ones learned from your edits, unless you also added them in Settings), and up to 200 characters of context (earlier segments and, if enabled, the text before the cursor; never in password fields, terminals or password managers). The API key is a 0600 file in the App Group container, readable by non-sandboxed programs running as you; delete it in Settings. Settings › 联网记录 (network log) lists every request with its time, purpose, server, what was sent (counts only) and result. Importing a personal dictionary reads only the file you pick, locally. **Learning from your edits** (on by default, can be turned off): after a voice result is typed, the input method reads that text plus about 16 characters before and 80 after it, on this Mac, at most once a second for at most 60 seconds, keeps it in memory only, and stores just the "heard → meant" word pair (applied automatically once the same edit was seen twice) in its private container; the learned words are local hotwords and are never sent to the cloud tidy-up; never in password fields. Deleting a word in 我的词 (My terms) also deletes its learned pairs. All data stays on your Mac (paths above) and can be removed in Settings, by deleting the folders above, or with `uninstall.sh --all`.
