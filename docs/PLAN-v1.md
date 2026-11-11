# ergou-ime 第一版计划

依据：[docs/DESIGN.md](DESIGN.md)（前期讨论的设计结论，D 2026-11-08 的 13 个决定，第 13 个是五笔拼音混输）。里程碑 M0–M6（含 M1.5）；每个里程碑再拆成 T 编号的小任务，T 编号的第一位就是里程碑号（T1.3 属于 M1）。

第一版要做到：五笔打字（自动调频，不自动造词）、五笔拼音混输（拼音候选显示五笔码、模糊音、容错）、Shift 中英切换、候选窗、右 Option 全局语音（结果进候选窗确认）、配套设置程序，全部本地完成，用 Developer ID 签名。

代码主要在 Linux 开发机上写，只做到“静态正确”。每个任务都标出**要在 Mac 上验证**的点。

---

## 总体结构

### 两个程序，都开 App Sandbox

| 程序 | target | 网络 | entitlements |
|---|---|---|---|
| 输入法本体 `ErgouIME.app` | `ErgouIME` | **从不联网** | app-sandbox、device.audio-input、application-groups、mach-register 临时例外（IMK 连接名） |
| 配套程序 `ErgouIME Settings.app` | `ErgouIMESettings` | 用户操作时，和每天一次的自动检查更新 | app-sandbox、network.client、application-groups、files.user-selected.read-only（导入个人词库时读用户选的文件） |

- App Group：`<TeamID>.com.codamon.ergou`（构建设置 `ERGOU_APP_GROUP_ID = $(ERGOU_TEAM_ID).com.codamon.ergou`，和 `$(TeamIdentifierPrefix)com.codamon.ergou` 是同一个字符串）。macOS 上用 Team ID 前缀的写法，macOS 13 起可用，Developer ID 分发不需要在描述文件里登记；`group.` 前缀是 iOS 的写法，在 macOS 13/14 的 Developer ID 应用上不适用。
- Team ID 只写进 git-ignored 的 `Config/Local.xcconfig`（`scripts/configure.sh` 读环境变量 `ERGOU_TEAM_ID`），不进仓库。
- 签名：Automatic + Apple Development（开发）/ Developer ID（发版），Hardened Runtime 开。不用 ad-hoc：ad-hoc 每次重编签名都变，输入监控和麦克风授权会失效。
- 架构：Universal（arm64 + x86_64），最低 macOS 13。Debug 只编当前架构，Release `ONLY_ACTIVE_ARCH = NO`。librime、sherpa-onnx 都用 universal 预编译包。

### 打包与安装（决定）

**输入法是外层，Settings 嵌在里面：**

```
ErgouIME.app                                   ← 装到 ~/Library/Input Methods（开发）或 /Library/Input Methods（pkg）
└─ Contents/
   ├─ MacOS/ErgouIME
   ├─ Frameworks/librime.1.dylib, libsherpa-onnx-c-api.dylib, libonnxruntime.dylib
   ├─ SharedSupport/rime-data/
   └─ Library/LoginItems/ErgouIME Settings.app  ← Sparkle 在这里
```

理由：
1. 输入法必须放在 Input Methods 目录才能被系统可靠地注册；反过来把输入法嵌在 /Applications 的 Settings 里，沙盒里的 Settings 没法把它装进 Input Methods。
2. 一个包就是全部：Sparkle 更新时替换整个 `ErgouIME.app`，两个程序版本永远一致。Sparkle 2 支持更新“宿主以外的 bundle”（`SPUUpdater(hostBundle:applicationBundle:…)`，两者都指向外层 `ErgouIME.app`）。
3. 放在 `Contents/Library/LoginItems/` 是 Apple 规定的登录项位置，留出“Settings 作为登录项常驻”这条后路（见 M3 的热键方案 B）。
4. 代价：Settings 不出现在“应用程序”文件夹和启动台，只能从输入法菜单“打开设置…”打开。以后可以在 pkg 里往 /Applications 放一个替身。

### 数据位置

**App Group 容器** `~/Library/Group Containers/<TeamID>.com.codamon.ergou/`，只放两个程序都要用、而且不会被当作代码执行的东西：

- `Models/sense-voice/`：模型。Settings 写，输入法读；输入法加载前校验 SHA-256（onnx 模型会被解析，也是攻击面）。
- 共享设置：`UserDefaults(suiteName: appGroupID)`。Settings 写设置值和手动造词条目；**输入法把它们当作不可信输入**，用 `Shared/SettingsValidation.swift` 校验（设置值走白名单；手动造词只允许 1–8 个汉字 + 1–4 位 a–y 编码，最多 2000 条）。

**输入法自己的沙盒容器** `~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Application Support/ErgouIME/`：

- `Rime/`：librime 用户目录（userdb、custom.yaml、编译缓存）。**只有输入法读写，Settings 不碰。** 原因：librime-lua 会先在用户目录的 `lua/` 里找脚本，用户目录里有 `rime.lua` 也会直接执行（librime-lua `modules.cc` 的 `lua_init`）。如果这个目录放在有网络权限的 Settings 也能写的地方，Settings 一旦被攻破，就能把代码注入能看到所有按键、能录音的输入法进程。
  - 输入法每次部署前用 `ErgouIME/Engine/RimeUserConfig.swift` 从校验过的设置生成 `default.custom.yaml`、`ergou_wubi.custom.yaml`、`ergou_pinyin.custom.yaml`、`wubi86_jidian_user.dict.yaml`。
  - 用户目录里如果出现 `rime.lua` 或 `lua/`，先挪到 `Quarantine/<时间>/`，挪不动就删掉，然后才加载 librime。
  - “清空用户词库”通过 Darwin 通知让输入法自己去做（`Shared/SharedSettings.swift`）。
- 注意：沙盒里 `~/Library/Application Support` 会被重定向到各自容器，两个程序互相看不到。M0 之前写在 `~/Library/Application Support/ErgouIME` 的东西都作废。

---

## M0 骨架

完成标准：在 D 的 Mac 上能切换到 ergou-ime，按键能被接收。

- **T0.1 骨架（已完成，本分支）**：XcodeGen 两个 target、Info.plist（IMK/TIS）、entitlements、`main.swift`、`ErgouInputController`（直通引擎：可打印 ASCII 直接上屏）、librime/sherpa-onnx 接入位置、Settings 骨架（通用 / 语音模型占位 / 关于）、`scripts/`、`check-no-network.sh`。
- **T0.2 第一次在 Mac 上编译安装**：`ERGOU_TEAM_ID=… ./scripts/bootstrap.sh` → Xcode 编译 → `./scripts/install.sh`。
  - 验证：签名后 `codesign -d --entitlements - ErgouIME.app` 里有 app-sandbox、没有 network；Settings 嵌在 `Contents/Library/LoginItems/` 并且签名有效（`codesign --verify --deep --strict`）。
  - 验证：**沙盒里 IMKServer 能注册**连接名；去掉 `mach-register` 例外试一次，看是否真的需要。
  - 验证：App Group 容器能创建，两个程序都能读写（`Paths.sharedContainer` 不为 nil）。
  - 验证：TextEdit、Safari、终端里打英文正常；⌘C/⌘V、方向键、回车不受影响；菜单里三项可用，“打开设置…”能打开 Settings。
  - 记录：首次安装要不要注销重登；重编后怎么让系统加载新版本。写回 README。

## M1 五笔

完成标准：在备忘录、浏览器、终端、微信里都能正常打五笔。

- **T1.1 链接 librime 并部署**：`bootstrap.sh --rime`，确认 `RimeEngine` 编译通过、在沙盒里能读 `SharedSupport/rime-data`、能在输入法自己容器的 `Rime/` 里写 userdb；首次部署在后台线程，期间按键直通。
- **T1.2 按键细节**：补全 `KeyMapping`（小键盘、F 键、不同键盘布局的标点）；`consumedKey` 的各种情况（回车上屏编码、Esc 清空、退格）；`commitComposition` 时上屏原始编码而不是丢掉。
- **T1.3 候选窗**：无边框、不抢焦点的 `NSPanel`，显示在光标旁；横排 5 个候选、高亮、翻页、鼠标点选；深浅色；多屏和屏幕边缘不越界。2026-11-09 已做第一版：横排、高亮、注释变淡、深浅色、贴屏幕边缘翻到光标上方；还没有鼠标点选和翻页提示。语音结果以后也走这个窗（M2）。
- **T1.4 Shift 中英切换**：单按 Shift（按下又松开、中间没按别的键）切 `ascii_mode`；有编码时按 Rime 规则处理；切换提示。验证快速连按、Shift+字母、Shift+鼠标选择不误切。
- **T1.5 自动调频（默认开）、不自动造词**：`RimeData/ergou_wubi.schema.yaml` 里 `translator/enable_user_dict: true`，`enable_encoder`、`encode_commit_history` 显式 false（D 2026-11-08 选方案 A）；开关由 `RimeUserConfig` 写进 `ergou_wubi.custom.yaml`（五笔和拼音两个翻译器一起）。
  - 为什么不自动造词（读 librime 1.17.0 源码得出）：`encode_commit_history` 会把每段连续上屏的字（中间没有标点）切成 2–5 字的新词写进用户词库，大部分是垃圾词；新词会让原来唯一的四码变得不唯一，这些码就不再自动上屏、要按空格或数字，而且越用越多。
  - 为什么只开调频是安全的（同样读源码得出）：上屏时 `TableTranslator::Memorize` 只对上屏的那个词条调用 `UserDictionary::UpdateEntry`，编码和文字都和系统码表里那条一样，不会给任何码新增文字不同的词条。查询结果经过 `DistinctTranslation`，按文字去重，所以用户词库和系统码表里的同一个词只出现一次，`auto_select` 的唯一性判断（`Prepare(2) == 1`）不变。影响只有一个：同一个码有多个候选时，用过的词排到前面（`PreferUserPhrase`）。所以“顶字上屏”在这类码上会选中调频后排第一的词，这正是调频本身的效果。
  - Settings 的“自动调频”开关：只写共享设置，输入法生成 `ergou_wubi.custom.yaml` 里的 `translator/enable_user_dict` 和 `pinyin/enable_user_dict` 后重新部署；关掉后 userdb 保留但不使用。“清空用户词库”：输入法 finalize librime → 删 `*.userdb` → 重新初始化和部署（librime 没有现成的清空接口）。
  - 验收：打一段话后 `Rime/` 里出现 userdb，多候选的码里常用词排到前面；四码唯一的码照常自动上屏；没有出现自己没打过的新词。
- **T1.6 输入法菜单**：只留“打开设置…”“重新部署”“关于二狗输入法”，其他设置都在 Settings。

## M1.5 五笔拼音混输

依据：DESIGN.md 的五笔拼音混输一节（D 2026-11-08）。完成标准：默认模式下五笔和拼音混排正常；打开“四码唯一自动上屏”后，长拼音（如 `shang`）不被截断、常用五笔四码自动上屏、拼音排在五笔后；拼音候选旁边能看到五笔码。

文件：`RimeData/ergou_wubi.schema.yaml`（方案）、`RimeData/ergou_pinyin.schema.yaml`（只用来编拼音的 prism 和纠错表）、`RimeData/lua/ergou/*.lua`、`ErgouIME/Engine/RimeUserConfig.swift`。极点的文件只当数据用，不改。**全部没有部署过。** Lua 里我们自己的逻辑（拼音前缀判断、五笔容错的变体生成、自动上屏的分支）有单元测试，librime-lua 的接口用假对象代替：`scripts/test-lua.sh`（2026-11-08 在 Linux 上 25 项通过）。真实的 librime-lua 接口只能在 Mac 上验证。

**2026-11-09 在 D 的 MacBook Pro（macOS 27.0.1、Xcode 27.2、arm64）上的结果**（不装输入法，只编译和用 `tools/rime-harness` 直接驱动 librime 1.17.0 + librime-lua）：

- 不签名编译通过（直通引擎版本，以及链接 librime + librime-lua + sherpa-onnx 的版本），没有警告。签名编译、安装、沙盒里的行为还没测。
- librime-lua 能从 `rime-plugins/` 加载，`lua/ergou/*.lua` 从共享数据目录加载，`Menu:prepare`、`get_candidate_at`、`Context:select/commit/push_input`、`ReverseLookup`、`ShadowCandidate`、`Memory:dict_lookup/iter_dict` 都按预期工作。
- 已确认可用：拼音候选显示五笔码；`` ` `` 只出拼音；模糊音（`zang` → 张）；打反的拼音（`shagn` → 上）；五笔空码容错（`tnrt` → 我〔纠 trnt〕）；自动上屏、严格模式；四码顶字（`trntkhlg` → 我 + 中国）。
- 发现并已修正：混输时拼音的相邻键纠错（`enable_correction`）会把五笔码变成一堆不相干的拼音候选（`trnt` → 也嗯、人、仍），所以混输里关掉，只在 `` ` `` 后面开；没有四码顶字，连续打 `trntkhlg` 会卡住，已经补上（只在“四码唯一自动上屏”打开时）。
- 排序问题（D 2026-11-09 定）：按词频混排时拼音会压住短的五笔码（`an`、`de` 第一页全是拼音）；把拼音整体降到五笔后面又降过头（打 `wo` 第一页全是还没打完的五笔码，没有“我”）。现在两种模式都用 `lua/ergou/rank.lua` 排：**五笔码完全对上的 → 拼音 → 还没打完的五笔码 → 纠错**。实测 `an` → 世、按、俺…；`de` → 胡、的、得…；`wo` → 伙、我、喔…。“四码唯一自动上屏”不再改排序，只管自动上屏和顶字。

- **T1.5.1 librime-lua 接入**：`fetch-librime.sh` 只拷 `rime-plugins/librime-lua.dylib`；`embed-vendor.sh` 把它放进 `Contents/Frameworks/rime-plugins/`（librime 从 `librime.1.dylib` 所在目录的 `rime-plugins/` 加载插件，见 librime 1.17.0 `plugins/plugins_module.cc`）并签名，把 `RimeData/` 叠加到 `SharedSupport/rime-data/`。
  - 验证：`otool -L` 看插件链接的是 `@rpath/librime.1.dylib`、能解析；沙盒 + Hardened Runtime 下插件能加载（日志里有 `loaded plugin: lua`）；`lua/ergou/*.lua` 从 `rime-data/lua` 加载；在用户目录放一个 `lua/ergou/pinyin.lua` 和 `rime.lua`，确认启动时被挪进 `Quarantine/`、没有被执行。
- **T1.5.2 方案 ergou_wubi**：五笔 `table_translator` + 拼音 `script_translator@pinyin`（同一段输入，`tag: abc`）+ `` ` `` 前缀的纯拼音（`affix_segmentor@pinyin_only`）+ `uniquifier`。`speller/auto_select` 两种模式下都关，自动上屏只由 lua 做。
  - **纯拼音前缀用 `` ` ``，不用 `z`**：极点方案拿 `z` 做拼音反查，但混输时 z/zh 开头的拼音是直接打的，`z` 前缀会把 `zhong` 变成 `z` + `hong`。
  - 验证：两个翻译器的候选都出现；同一个字只出现一次；`` `zhong `` 只出拼音；拼音候选排序（`pinyin_simp` 很多词条权重是 0，排序差的话换词库，另核许可证）。
- **T1.5.3 拼音候选显示五笔码**：`lua_filter@*ergou.code_hint`，用 `ReverseLookup("wubi86_jidian")`，显示“简码 · 全码”，例如 `我 q · trnt`。五笔候选和纠错候选不加。
  - 验证：词组也能查到码；`ShadowCandidate` 保留了原来的候选类型（自动上屏靠类型区分五笔和拼音）。
- **T1.5.4 四码唯一自动上屏（选项，默认关）**：`lua_processor@*ergou.auto_commit`。候选顺序不随这个选项变（`lua/ergou/rank.lua`），它只加自动上屏和四码顶字。规则：只数类型为 `table`/`user_table` 的候选；四码唯一而且不是拼音前缀 → 用 `context:select` + `commit` 上屏（这样调频照样记录）；是拼音前缀 → 等下一个键，还能组成拼音就继续，否则上屏五笔字、把这个键当新码第一码（顶字）。`ergou/auto_commit_strict` 是严格模式：不等，四码唯一就上屏。
  - 验证：librime-lua 的 `Menu:prepare`、`get_candidate_at`、`Context:select/commit/push_input` 的实际名字和行为；用 D 的真实打字统计多少常用四码要等一个键；`shang`、`zhuang`、`xiang` 这类长拼音不被截断；空格总是上屏五笔。
- **T1.5.5 模糊音和拼音容错**：模糊音是 `ergou_pinyin` 的 `speller/algebra` 里的 `derive` 规则，Settings 逐项勾选，默认开 z/zh、c/ch、s/sh、n/l、en/eng、in/ing；容错是 `pinyin/enable_correction`（相邻键，`ergou_pinyin` 编出纠错表）加几条打反规则（`shagn→shang`、`zhon→zhong`、`hoa→hao`、`xaing→xiang`）。`lua/ergou/pinyin.lua` 镜像同一套拼写，只用来判断“还能不能是拼音”。
  - 验证：借用 prism（`pinyin/prism: ergou_pinyin`）能生效；改了模糊音重新部署后 prism 重编；纠错候选排在正确候选后面；模糊音全开时混输和自动上屏的变化。
- **T1.5.6 五笔容错（尽量第一版，做不完放 1.x）**：`lua_translator@*ergou.wubi_correction`，只在空码时（五笔查不到、也不是完整拼音）试“相邻两码对调”和“换成键盘相邻键”，最多 5 个结果，标“纠 <码>”，quality -100，类型 `correction`，永远不自动上屏、不顶字。
  - 验证：`Memory:dict_lookup` / `iter_dict` 的用法；常见打错能纠回来；正常打字时不出现纠错候选。
- **T1.5.7 拼音调频**：`pinyin/enable_user_dict` 跟“自动调频”开关一起开关。验证拼音那边开着用户词典会不会产生新词：就算产生，自动上屏也只数五笔候选，不受影响；但要确认拼音用户词不会出现在五笔候选的类型里。

## M2 语音（输入法内）

完成标准：ergou-ime 是当前输入法时，一句 5–10 秒中英混合的话能识别、经候选窗确认上屏；测出延迟和内存。

- **T2.1 链接 sherpa-onnx**：`bootstrap.sh --speech`（开发用脚本把模型放进 App Group 容器）。验证 librime 和 sherpa-onnx/onnxruntime 在同一进程里没有符号冲突；冲突的话把识别放进 XPC 辅助进程。
- **T2.2 录音**：ergou-ime 是当前输入法时，在 `flagsChanged` 里认右 Option（keyCode 61）：按住约 250 ms 才开始录，按住期间按了别的键就取消（是组合键，不是语音）。`AVAudioEngine` 采集，转 16 kHz 单声道 Float32，只在内存里，最长 60 秒。首次使用弹麦克风授权（沙盒 + Hardened Runtime 下的 TCC 行为要验证）。密码框里不录音。
- **T2.3 识别结果进候选窗**：松开后在后台队列识别；结果作为候选显示在候选窗：**Enter 上屏、Esc 取消、数字键选其他候选**（如果有）。不直接 `insertText`。识别器只创建一次复用；闲置一段时间释放模型（实测后定时长）。
- **T2.4 测量**：5 / 15 / 30 秒音频的识别延迟、内存峰值、模型冷启动时间；ITN 和标点效果。
- **T2.5 没有模型时**：提示“还没有语音模型”，点提示打开 Settings 的模型页下载弹窗（`SettingsLauncher.open(page: .models)`）。不自动下载。

## M2.6 高精度识别（Qwen3-ASR）和我的词（阶段 A，2026-11-10）

**选型依据**：D 的声音实测对比（不在仓库里；USB 动圈麦，桌面稿 14 句，109 s，按停顿切 16 段，sherpa-onnx v2.0.1，4 线程）：

| 配置 | 错字率 | 专有词 | RTF |
|---|---|---|---|
| SenseVoice（原来用的） | 3.9% | 6/10 | 0.013 |
| Qwen3-ASR 0.6B | 2.9% | 8/10 | 0.069 |
| Qwen3-ASR 0.6B + 11 个热词 | 0.3% | 10/10 | 0.078 |
| Qwen3-ASR 0.6B + 107 个热词 | 0.3% | 10/10 | 0.155 |

- 选 Qwen3-ASR 0.6B int8：本机方案里最准，热词效果最好（比 SenseVoice + 云端整理还好），Apache-2.0（SenseVoice 是 FunASR 模型协议，不是开源许可证）。Fun-ASR-Nano 热词多了会崩（107 个热词错字率 79.5%），不用。
- 代价：慢约 6 倍（5 秒话约 0.4 秒，107 个热词时约 0.8 秒），模型 879 MB（压缩包），内存 1.5～2.2 GB。所以**边说边出的文字仍用 SenseVoice**，分段的最终结果用 Qwen3；两个都装最好，只装一个也能用。

**做法**（`ErgouIME/Speech/Qwen3Transcriber.swift`、`FinalPass.swift`、`TermStore.swift`，`Shared/VoiceTerms.swift`，设置 › 我的词）：

- 录音一开始就在后台队列加载 Qwen3（第一次约 0.9 s，另加一次性的 SHA-256 校验）；说话时停顿切出的每一段立刻交给它，说完只剩最后一段要等。闲置 10 分钟释放。日志只记加载、解码耗时和段数，不记文字。
- Qwen3 自带标点，不再过 CT-Transformer（避免双重标点）；数字仍是汉字（“二点零点一”），交给自动整理改成阿拉伯数字。
- 热词走 sherpa-onnx 的**每个 stream 的选项**（`SherpaOnnxOfflineStreamSetOption(stream, "hotwords", "a,b,c")`，ASCII 逗号分隔），不在模型配置里，所以词表变了不用重新加载模型；TermStore 只在有变化时重算热词串。
- KV 长度（`max_total_len`）设 768：默认 512 时，25 秒一段（328 个音频 token）加上 107 个热词（271 token）会超长，sherpa-onnx 会**悄悄截掉后面的音频**。热词总量按估算控制在约 200 token 以内、最多 100 个。
- 近乎无声的一段（1.1 s 呼吸声）带 107 个热词时，模型会把热词表念一遍。对策：每段的输出上限按时长定（16 + 8×秒 个 token）；输出明显不合理（太长、大半是热词拼起来的、只有 `language`）就去掉热词重解一次，还不行就用 SenseVoice 那段的结果。
- 我的词：手动添加的词（共享设置，1–24 字，不能是纯数字、邮箱、网址、像密钥/验证码的串，最多 300 个）和学到的词（App Group 里的 `Terms/learned-terms.json`，只有输入法写；设置程序的删除/固定通过共享设置里的编辑列表 + Darwin 通知交给输入法）。生效规则：手动和固定的总在；学到的词被听错过的出现 1 次就生效，否则 2 次；按次数×新近度（半衰期 30 天）排序。学的接口 `TermStore.record(term:heard:source:)` 已就绪，下一阶段由云端整理调用。

**输入法自己的代码复测**（`tools/speech-bench`，直接编译上面的 Swift 文件，D 的 Mac 2026-11-10，按字计错字率）：

| 配置 | 错字率 | 专有词 | 总耗时 / RTF |
|---|---|---|---|
| Qwen3，按原来的 16 段，无热词 | 2.9% | 8/10 | 6.1 s / 0.072 |
| Qwen3，16 段，11 个热词 | 0.3% | 10/10 | 6.8 s / 0.080 |
| Qwen3，16 段，107 个热词 | 0.3% | 10/10 | 12.5 s / 0.148 |
| Qwen3，整段录音用输入法的分段（20 段，2 段静音跳过），无热词 | 1.0% | 9/10 | 6.8 s / 0.064 |
| 同上，11 个热词 | 0.3% | 10/10 | 7.6 s / 0.072 |
| SenseVoice，输入法的分段（不含标点模型） | 3.6% | 5/10 | 1.7 s / 0.016 |

每段（2.5–8.5 秒）的解码时间：Qwen3 无热词 0.20–0.58 s，11 个热词 0.25–0.61 s，107 个热词 0.64–0.96 s；SenseVoice 0.04–0.13 s。Qwen3 模型加载 0.89–0.91 s；按输入法的用法跑 FinalPass（`speech-bench finalpass`），第一次连 SHA-256 校验约 1.4 s，校验结果记住以后约 0.9 s，`begin` 本身 2–4 ms 就返回（不卡主线程）。内存峰值（`/usr/bin/time -l`）：短句 1.5 GB，17 秒一段 1.9 GB，25 秒一段 2.2 GB。

**要在 Mac 上实测**：第一次说话时 Qwen3 还在加载（含校验），说完要等多久；说长段话时说完后的等待；输入法进程的内存（活动监视器）和 10 分钟后是否释放；只装 Qwen3、不装 SenseVoice 时（没有边说边出的文字）是否正常；设置 › 我的词 的添加、删除和“现在生效”数字；`log stream` 里的 `Qwen3-ASR loaded` / `decoded` 行。

## M2.7 云端整理和自动学词（阶段 B，2026-11-10）

**为什么**：实测本机 Qwen2.5-7B 整理改对的少、还会乱改，以后不推荐（设置里“本机小模型”标为不推荐，没在用、也没下载模型的人看不到这一项；代码和已下载的模型照常能用）。云端大模型整理很有效（SenseVoice 3.9%→1.6%，Fun-ASR-Nano 2.0%→0%）。Apple 设备端模型保留。

**结构**（隐私规则 11，`Shared/Privacy.swift`）：

```
输入法（无网络） ──XPC，CloudTidy.Request（JSON）──▶ ErgouIMECloud.xpc（沙盒 + network.client + App Group）──▶ 服务商
               ◀──CloudTidy.Reply────────────────
设置程序 ──写──▶ App Group/Cloud/api-key-<服务>（0600） ◀──读── ErgouIMECloud.xpc
```

- `ErgouIMECloud.xpc` 是新的 XPC 服务，和 Corrector 一样嵌在 `ErgouIME.app/Contents/XPCServices`；只有选了“云端模型”才会被连接，闲置 5 分钟退出。每次调用都重新读设置和 Key，不缓存。
- 输入法和 Corrector 仍然没有网络权限。`scripts/check-no-network.sh` 现在：扫描 `ErgouIME/`、`Shared/`、`ErgouIMECorrector/`、`CloudShared/` 里的网络接口；输入法源码不能提到 Key；`CloudShared/` 只能编进 Cloud 和 Settings 两个 target；Cloud 的 entitlements 必须**恰好**是 app-sandbox + application-groups + network.client；仓库里除 Settings 和 Cloud 外的 entitlements 都不能有 network；给了 app 路径时再查签名后的四个包和两个二进制的导入符号。
- **Key 放哪（Mac 上实测，macOS 27）**：先试了钥匙串——两个同 team、同 App Group 的沙盒测试程序用 `kSecUseDataProtectionKeychain` + access group = App Group ID，读写都返回 `-34018 errSecMissingEntitlement`（要描述文件里的 application-identifier，这些 Apple Development / Developer ID 构建没有）；加 `keychain-access-groups` 权限而没有描述文件，程序启动就被系统杀掉（137）。所以退而用 App Group 容器里的文件：`Cloud/api-key-anthropic`、`Cloud/api-key-openai`，目录 0700、文件 0600、不进备份，先写临时文件再改名。代价写进了隐私规则 11 和 README。第一阶段存在设置程序自己钥匙串里的 Key，打开设置时自动搬到文件里并删掉钥匙串条目。
- **设置 › 语音 › 自动整理 › 云端模型**：服务（Anthropic（Claude），默认模型 `claude-haiku-5-5`；OpenAI 兼容接口，要填 https 地址和模型名）、API Key（保存/替换/删除）、“把光标前的文字一起发送（帮助判断同音字）”（默认开）、测试连接。测试连接走的是真实路径：设置程序写一个请求 id、发 Darwin 通知 → 输入法让 ErgouIMECloud 发一句固定的短句 → 结果（不含用户数据）写回共享设置 → 设置程序显示耗时和结果或错误。所以设置程序自己不发这类请求；输入法没在运行时提示先切到二狗输入法。
- **请求内容**：识别出的文字；当前 App 名（`NSRunningApplication.localizedName`）；最多 50 个生效的我的词；开关打开时，开始录音那一刻从 client 取光标前最多 200 个字（`selectedRange` + `attributedSubstring`），只随第一段发送。密码框里不录音，也就不取。上下文和 App 名里的 `<` `>` 换成全角，不能闭合我们的标签。
- **提示词**：`CloudTidy.system` = `CorrectionPrompt.system` 把最后一条“只输出修正后的文本”换成三条：只改 `<识别结果>`，`<上下文>/<应用>/<我的词>` 只用来判断写法；只输出 JSON `{"text": "...", "terms": [{"term": "...", "heard": "..."}]}`；terms 只收专有名词、产品/品牌名、人名地名、中英混说的术语，不收普通词、数字、敏感信息，最多 10 个。
- **两种服务的请求**（Anthropic 部分已改，见下面“边说边整理”）：Anthropic Messages API，`output_config.format` = json_schema（结构化输出，Haiku 5.5 支持），`effort: low`，不发 temperature；OpenAI 兼容 `/chat/completions` + `response_format: json_object`。两边都容错：剥 `</think>`、```json 围栏、对象前后的废话；HTTP 400 时（服务不认 output_config / response_format）去掉这些参数再试一次；`stop_reason` 是 refusal / max_tokens、`finish_reason` 是 length 都算失败。解析后 `text` 过 `CorrectionPrompt.lengthOK`（0.3～1.3 倍）；JSON 坏了、没有 text、长度不对都算失败，上屏原文。
- **超时与回退**（说完后的等待已改，见下面“边说边整理”）：每段 `CloudTidy.timeout` = 12 秒（代码常量），各段同时发出；服务里有硬截止，输入法这边再多等 1 秒。失败、超时就用本机识别结果；“云端整理中”时按 ↩ 或右 Option 跳过仍然有效（跳过后回来的结果丢掉，也不学词）。日志：服务记 `status、耗时、进出字数、上下文字数、发出/收回词数`，输入法记总耗时和词数，都不记文字。
- **学词**：每个 term 要能通过 `VoiceTermRules.term`、出现在修正后的文字里；`heard` 要出现在识别原文里且和 term 不同，否则当作没听错。服务的回复在输入法里再校验一遍（服务有网络，视为不可信）。然后 `TermStore.record(term:heard:source: .cloud)`，生效规则不变（听错过的出现 1 次生效，否则 2 次）。密码框里不学（TermStore 自己也查）。

**验证（2026-11-10，D 的 Mac，无人值守）**：

- Mac 上 `build-signed.sh` 编译、安装通过；`check-no-network.sh <安装好的 ErgouIME.app>` 通过。签名后的权限：ErgouIME.app = sandbox、App Group、audio-input、mach-register 例外，**没有 network**；ErgouIMECorrector.xpc = sandbox、App Group，**没有 network**；ErgouIMECloud.xpc = sandbox、App Group、network.client；Settings = sandbox、App Group、network.client（`get-task-allow` 是开发签名自动加的）。另外在复制的仓库里故意改坏 5 处（Corrector 加 network.client、Cloud 加 network.server、Corrector 用 URLSession、输入法源码引用 Key、把 CloudShared 加进输入法 target），脚本都报错。
- `tools/cloud-bench tests`：70 项离线检查全过（提示词替换、标签注入、上下文截 200 字、最多发 50 个词、各种坏 JSON / 围栏 / think、长度守卫、term 过滤、最多收 10 个、地址和模型名校验、两种请求的 URL 和头、Key 不在请求体里、两种回复的解析含 refusal 和截断、TermStore 用 `.cloud` 记录、密码框里不学、存盘后再读）。
- **Key 读取机制**：用一个和设置程序同样权限（sandbox + App Group，同一签名身份）的测试程序，编进同一份 `CloudKeyFile.swift`，用 `open` 在图形会话里启动，写入 Key：`save true; file mode 600; dir mode 700`。然后用 `defaults` 把服务设成一个 OpenAI 兼容的转发服务，`open` 启动刚装好的输入法，写请求 id 并 `notifyutil -p com.codamon.ergou.cloud-test`：输入法连上 ErgouIMECloud.xpc，服务读到了 Key，4.2 s 后共享设置里出现结果 `{"text":"明天下午3点在2楼会议室开会，记得带上电脑，用 Claude 和 GPT 对比一下。","terms":[{"term":"Claude","heard":"cloud"},{"term":"GPT"}],"status":200}`。把服务切到没有 Key 的 Anthropic 再测，返回 `noKey`。服务日志只有一行：`test openai: status 200, ok, 4236 ms, 41 chars in, 42 out, context 0, terms 2 sent / 2 back`。
- **真实调用**（`tools/cloud-bench call`，即服务用的请求和解析代码，经一个 OpenAI 兼容的转发服务调用 GPT 系列模型，按输入法的 300 字分块、同时发出；输入是对比稿的识别全文；“+热词”= 对比时用的 11 个词，结果偏乐观；上下文是一句无关的假上文；按字计错字率）：

| 输入 | 条件 | 超时 12 s | 错字率 | 专有词 | 耗时 |
|---|---|---|---|---|---|
| Qwen3-ASR（2.9%） | + 热词 + 上下文 | 2/2 段成功 | **0.7%** | 10/10 | 10.8 s（两段 10.8 / 4.8 s） |
| Qwen3-ASR | 无热词、无上下文 | 1/2（第 1 段超时） | 2.3% | 9/10 | 12.9 s |
| 同上 | 超时放宽到 40 s | 2/2 | 2.3% | 9/10 | 9.2 s |
| SenseVoice（3.9%，没过标点模型，342 字一段） | + 热词 + 上下文 | 0/1（超时） | 3.9%（原文） | 6/10 | 13.0 s |
| 同上 | 超时放宽到 40 s | 1/1 | **0.7%** | 10/10 | 14.0 s |
| SenseVoice | 无热词、无上下文，40 s | 1/1 | 1.6% | 9/10 | 14.4 s |

  对比：之前不带 JSON、整段一次的 gpt 整理是 SenseVoice 1.6%、Qwen3 2.0%。拿到 HTTP 200 的 8 次回复（7 次分段 + 1 次测试连接）**JSON 全部解析成功**、全部过了长度守卫；失败的都是转发服务太慢（按 12 秒超时跑的 6 段里 3 段没回来）。挑出的词：有热词时基本就是热词表，加上 heard（输入法的名字←净输入法、五笔←无比、Claude←CLOUD、GPT←GT、基督城←机督场、右 Option←右选项）；没热词时还会收“李总”“BUG”“SHIFT”“OPTION”这类——“李总”算人名可以接受，大写的 BUG/SHIFT 偏普通词，不过没有 heard、要出现两次才生效。

**已知问题**：

- 那个转发服务一段要 5～14 秒，12 秒超时下长段经常落空；Anthropic Haiku 5.5 可能快很多，但没有 Key，未测。超时要不要按段长放宽，等 D 用 Haiku 实测后再定。
- 测试连接依赖输入法进程在运行（全局语音打开时一直在）。
- Key 文件不如钥匙串严：同一用户下不开沙盒的程序能读。以后有描述文件（或上 Mac App Store）再换成共享钥匙串。输入法进程也在同一个 App Group 里，“输入法不读 Key”靠的是代码约束（`check-no-network.sh` 1b/1c），不是沙盒。
- 审计（2026-11-10）后：终端和密码管理器里不取光标前文字（`CloudTidy.noContextApps`）；回复里出现我们的标签算失败；服务只在“云端”模式下接整理请求、回复超过 1 MB 不解析；测试连接的请求 id 只用一次；我的词不收总共 6 位以上数字、不收带“密码 / 验证码”等字样的词。
- 本机测试只用 OpenAI 兼容接口；Anthropic 路径（结构化输出、400 后去掉 output_config 重试）只有离线检查。

**要在 Mac 上实测**（第一版；边说边整理的实测点见下）：设置 › 语音 › 自动整理 选“云端模型”，看服务、地址、模型、Key 的显示，点测试连接；在备忘录/微信里说一段带专有词的话，看“云端整理中”的等待、↩ 跳过、结果；换成 Anthropic + Haiku 5.5 的 Key 再测速度；说完后到“我的词”看学到的词和“听成”；密码框里确认不录音不学词；关掉“把光标前的文字一起发送”后再说一段（`log stream --predicate 'subsystem == "com.codamon.inputmethod.Ergou.Cloud"'` 里 context 应为 0）。

### 边说边整理（2026-11-10 晚）

**为什么**：D 的 Mac 实测，整段（340 字，两块）发 Haiku 5.5，原来的请求（json_schema + effort low）说完后要等 4–11 s。Haiku 5.5 一句话：`thinking: disabled` + 提示词要求 JSON ≈ 1.0–1.1 s；adaptive + effort low 2.4–3.1 s；json_schema + 不思考 1.3–2.2 s。所以改成每段识别完就发、说完只等最后一段，请求也换成最快的那种。

**请求**（`ErgouIMECloud/CloudClient.swift`）：Anthropic 发 `thinking: {"type": "disabled"}`，不发 `output_config`（没有 json_schema、没有 effort；Haiku 5.5 默认 effort 是 medium，允许关思考），JSON 靠提示词第 7 条，解析本来就容错。模型名含 `sonnet-5-5` 时发 `{"type": "between_tools"}`（Sonnet 5.5 不收 disabled）。别的模型不认 disabled 时 400，按原来的逻辑去掉 thinking 再试一次。OpenAI 兼容不变（`response_format: json_object`，DashScope qwen-flash 测过可用）。Anthropic 加了可选的“接口地址”（`cloudBaseURLAnthropic`，空 = 官方 `https://api.anthropic.com`；只收 https，校验同 OpenAI 兼容那项；请求发到 `<地址>/messages`，只填域名时补 `/v1/messages`，填了完整 `/messages` 原样用；地址填错就不发，不会退回官方地址），给同接口的转发服务用。

**流程**（`ErgouIME/Speech/CloudStream.swift`，输入法和 cloud-bench 共用）：
- 每段的最终文字一出来就发：用 Qwen3-ASR 时在它解完这一段时（`FinalPass.submit(…decoded:)`），Qwen3 没出字就用 SenseVoice 的；只有 SenseVoice 时切段就发。说完后 `finish` 再对一遍最终文字：已经发过、文字相同的不再发；不同的（比如 Qwen3 没加载、改用 SenseVoice）重发，旧回复作废。
- 每个请求：这一段文字（超过 300 字按原来的分块）、App 名、最多 50 个我的词、上文 = 光标前文字（允许时）+ 本次前面各段（已整理的用整理后，没回来的用原文），合起来取最后 200 字。分块时后一块的上文接着前一块。
- 结果按段号存，乱序回来也按顺序拼。失败、被长度守卫或标签检查拒掉的段用原文。
- 说完后：只等没回来的段，最多 `CloudTidy.finishWait` = 4 s（从最后一段识别完算），到时没回来的用原文，并取消它们的请求。单个请求的上限仍是 12 s（录音中发的段用得上）。
- 跳过（整理中按 ↩ / 右 Option）：已回来的段用整理结果，没回来的用原文。理由：已回来的结果更好、也不用再等，跳过的目的只是“别等了”；全部用原文反而把已经到手的修正丢掉。
- Esc：`CloudStream.cancel` 丢掉所有迟到的回复，输入法再让服务 `cancel(batch:)` 取消这次录音还在跑的请求（`CloudCall` 取消 URLSessionTask，回 `.cancelled`）。不学词。
- 中途切出“云端”或进了密码框：停止发送，丢掉这次的整理。
- HUD：录音中已整理好的段显示整理后的文字，没回来的显示 SenseVoice 原文；说完后每回来一段刷新一次。
- 学词：每段回复的 terms 在输入法里重新校验；文字真正上屏时才 `record`（跳过时只记已用上的段；Esc 不记）。
- 提示词：云端版第 3 条改成更明确的说法（本机引擎的提示词不变）：连着说两遍的词或句子只删多余的一遍；单位照说的写（两百兆→200兆，不换成 MB）。原因：逐段发时 Haiku 5.5 把“要用这个功能，要用这个功能，”两遍都删了（3/3 次），还把“两百兆”写成 200MB。
- 隐私规则 11、README、设置里的说明都改成：选了云端后录音过程中就会发文字（每段识别完发这一段），Esc 收不回已发的段。

**验证（2026-11-10，D 的 Mac）**：编译安装通过；`check-no-network.sh <ErgouIME.app>` 通过；`cloud-bench tests` 113 项全过（新加：请求体没有 output_config、Haiku 是 disabled、Sonnet 5.5 是只有 type 的 between_tools、重试不带 thinking、Anthropic 接口地址的读取和拼接；CloudStream 的乱序拼接、上文、同文字不重发、文字变了重发并丢旧回复、跳过、4 s 超时、Esc、标签回声被拒、长段分块）。

**模拟**（`cloud-bench simulate`：对比稿 16 段的 Qwen3-ASR 0.6B 识别文本，不带热词，就是之前整段测试用的输入；每段按 wav 时长（字节/32000）实时播放，第 i 段说完那一刻发出；第 9 段识别为空不发；上文是一句假上文；11 个热词；按字计错字率。只算网络和模型，不含 Qwen3 解码最后一段的时间）：

| 服务 | 次数 | 说完后等待 | 每段耗时 | 错字率 | 专有词 |
|---|---|---|---|---|---|
| Anthropic 官方 Haiku 5.5，改提示词后 | 4 | **0.97 / 1.06 / 1.20 / 1.02 s** | 中位 0.95 s（0.80–1.88） | **0.0 / 0.3 / 0.3 / 0.0%** | 10/10 |
| 转发服务转 Haiku 5.5，改提示词后 | 1 | 1.36 s | 1.2–1.7 s | 0.3% | 10/10 |
| 官方，改提示词前 | 2 | 1.06 / 1.20 s | 0.85–1.47 s | 2.3 / 2.3%（两遍都删 + 200MB） | 10/10 |
| 转发服务，改提示词前 | 3 | 1.55–1.69 s | 1.5–2.2 s | 0.7 / 0.7 / 1.0% | 10/10 |
| 对照：官方整段（`call`，新请求 + 新提示词，两块同时发） | 1 | 1.8 s（说完后才发） | — | 0.7% | 10/10 |
| 对照：旧请求整段（json_schema + effort low） | — | 4–11 s | — | 0.0–0.3% | 10/10 |

剩下的错都是同一处：识别结果是“需要系统设置里”，参考稿是“需要在系统设置里”，模型有时补“在”、有时不补。模型对“我刚才说错了，不是周三，应该是周五见面”有时保留“不是周三”（这句不计分）。

**已知问题**：
- 等待的下限就是最后一段的一次请求（官方约 1 s，转发服务约 1.2–1.7 s），再加 Qwen3 解最后一段的时间（模拟里没算）。
- 逐段整理时，上文里后面的段还没说，模型看不到下文；本次测试没看到因此变差。
- 每段都发一次请求，请求数从 2 个变成 15 个；Haiku 5.5 很便宜（每次约几百 token），但用转发服务时要看它的计费方式。
- 4 s 上限是常量，网络很慢时最后一段会经常用原文；日志里有“tidied / still out”可以看。

**要在 Mac 上实测**：打开设置 › 语音，选云端模型 / Anthropic / 接口地址空 / 模型 haiku 5.5 并保存 Key，点测试连接；在备忘录里说 1 分钟左右、中间有停顿的话，录音中看浮窗里的段是否变成整理后的文字，说完后等待是否约 1 s；说长一点的话中途按 Esc，`log stream --predicate 'subsystem == "com.codamon.inputmethod.Ergou.Cloud"'` 里应有 “cancelled N requests”；整理中按 ↩ 跳过；断网时说一段，确认 4 s 后上屏原文。

## M3 全局语音 + 配套 App

完成标准：在别的输入法下按右 Option 能识别上屏并切回；没有输入框时能复制并提示；Fn 不被截断。

- **T3.1 热键放在哪个进程（先做的验证）**：
  - 风险：输入法进程只有被选中过才会启动，不一定常驻；全局热键依赖它在运行。
  - **方案 A（首选）**：listen-only `CGEventTap` 放在输入法进程里（它本来就负责录音、识别、候选窗，麦克风和输入监控权限都给同一个签名稳定的程序）。保证常驻：输入法用 `SMAppService.agent` 注册一个 LaunchAgent，`MachServices` 声明 IMK 连接名、`KeepAlive`，由 launchd 在登录时拉起并在崩溃后重启。
  - **方案 B（A 不行时）**：Settings 作为登录项常驻（`SMAppService.loginItem`，所以放在 `Contents/Library/LoginItems/`），在 Settings 里建 tap；按下/松开通过 Darwin 通知或 XPC 告诉输入法，必要时先 `TISSelectInputSource` 把输入法拉起来。缺点：多一个常驻进程，有网络权限的进程能看到按键时序（只看右 Option，不看内容）。
  - 验证步骤：① 登录后不选 ergou-ime，`pgrep ErgouIME` 看进程在不在；② 方案 A 的 LaunchAgent 和系统按需启动的输入法会不会起两个实例、抢连接名；③ 沙盒里 `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` 能否弹出输入监控授权，`CGEvent.tapCreate(… .listenOnly …)` 能否创建；④ 授权在重编（同一签名）后是否保留；⑤ 两个方案各自从按键到开始录音的延迟。
- **T3.2 全局右 Option 监听**：listen-only tap，只听 `flagsChanged`/`keyDown`，**从不吞事件**，只需要输入监控权限，**不申请辅助功能权限**。只认右 Option（keyCode 61），不允许把语音键设成单按 Fn；Fn、Option 照常传给系统和程序（不能像微信输入法那样截断 Fn）。保留按住约 250 ms 才开始录、按住期间按了别的键就取消。M3 起这里是唯一的检测点，M2 的 `flagsChanged` 路径只转发给它，避免同一次按键处理两次。
  - 验证：终端（Option 当 Meta）、VS Code、浏览器里单按右 Option 不触发奇怪行为。
- **T3.3 当前是别的输入法时**：按下热键时**立刻开始录音**（不等切换完成），同时 `TISSelectInputSource` 临时切到 ergou-ime；识别结果进候选窗，确认上屏（或 Esc 取消）后切回原输入法。验证：切换是否够快、会不会丢开头的录音、能否可靠切回。
- **T3.4 没有光标时**：切过去约 100 ms 内没有 `activateServer`、拿不到可用的 client，就判定为没有光标。识别结果**写一次剪贴板**（从不读），同时弹一个不抢焦点的泡泡（non-activating `NSPanel`），显示文字和“已复制”，几秒后消失。这条路径不出候选窗。密码框里不写剪贴板。验证：桌面、Finder、全屏视频、游戏、多显示器、台前调度下的判断和显示；判断不可靠时再考虑辅助功能权限（要先和 D 商量）。
- **T3.5 Settings：模型下载和导入**：把模型页的占位换成真下载：点“下载…” → 弹窗写明模型名、约 158 MB、来源网址、SHA-256、FunASR 模型协议要点和全文链接，确认/取消 → `URLSession` 下载（可取消、有进度）→ 校验 SHA-256 → 解压到 App Group 的 `Models/`。手动导入（`NSOpenPanel`，加 `files.user-selected.read-only`），同样校验。
- **T3.6 Settings：其余设置**：“自动调频”开关和清空用户词库（接 T1.5）、混输的开关（四码唯一自动上屏、严格模式、模糊音、拼音容错、五笔容错，接 M1.5；界面占位已有）、语音引擎选择（`SharedSettings.speechEngine`，第一版只有 SenseVoice 可用）、权限状态（麦克风、输入监控）和跳转系统设置。
- **T3.7 自动更新**：已做（2026-11-10），没有用 Sparkle，做法和理由见 DESIGN.md §3.5。下面是原来的 Sparkle 计划，留作记录。原计划：只加在 Settings target。`SUEnableAutomaticChecks = NO`，界面只有“检查更新…”按钮，用户可以自己打开自动检查。EdDSA 签名（`SUPublicEDKey`），appcast 放 GitHub Releases/Pages。`SPUUpdater` 的 host/application bundle 都是外层 `ErgouIME.app`。沙盒里要加 Sparkle 的 Installer XPC 服务和 `-spks`/`-spki` mach-lookup 例外。验证：更新后系统能否加载新版输入法——计划让输入法在 `deactivateServer` 时比对磁盘上的 `CFBundleVersion`，不一致就退出，下次使用时系统拉起新版本；看是否还需要注销。
- **T3.8 手动造词（M3 其余部分完成后）**：Settings 里加“我的词”页，用户输入词和五笔编码（可以按码表的编码规则自动算出编码，用户再改），列表可删改。
  - 实现：Settings 把条目（`词<Tab>编码`）写进共享设置 `manualPhrases`；输入法校验后（`SettingsValidation.manualPhrase`）由 `RimeUserConfig` 生成 Rime 用户目录里的 `wubi86_jidian_user.dict.yaml`，然后重新部署。极点码表的主词典 `wubi86_jidian.dict.yaml` 本来就在 `import_tables` 里引用了这个文件（作者留给“个人私有词库”的位置）；用户目录里的同名文件应该优先于安装包里的那份（要验证）。Settings 不直接写这个文件，理由见“数据位置”。
  - 为什么不写进 userdb：userdb 是 LevelDB，只能有输入法一个进程写；librime 也没有“插入单条用户词”的接口（levers API 只有整库导入导出）。
  - 为什么用 custom 词典：它是纯文本（`词<Tab>编码`），能看懂、能备份；不碰 userdb，也不需要跨进程写库；“清空用户词库”只清调频记录，手动加的词不受影响。代价是每次修改后要重新部署（几秒），只适合偶尔加词。
  - 注意：手动加的词如果和某个四码唯一的字同码，这个码就会变得不唯一、不再自动上屏。这是用户自己选的，界面上要提示。
  - 验证：生成的 `wubi86_jidian_user.dict.yaml` 覆盖了安装包里的那份；重新部署后新词能打出来；非法条目（带换行、tab、非汉字、5 位编码）被丢掉；安装包更新码表后用户目录里的这个文件不被覆盖。

## M4 隐私加固

完成标准：`codesign` 查到输入法本体没有网络权限；Little Snitch 或 `nettop` 观察输入法进程无连接；密码框里不录音。

- **T4.1 网络扫描进 CI**：`scripts/check-no-network.sh` 只扫输入法本体（`ErgouIME/` 和编进它的 `Shared/`），**不扫 `ErgouIMESettings/`**；再对签好名的 app 查 entitlements 和导入符号。以后有 macOS runner 时放进 CI。
- **T4.2 密码框**：Safari 登录页、终端 `sudo`、系统设置密码框里，输入法是否被切走、能否收到事件；`IsSecureEventInputEnabled()` 在输入法进程里的结果；全局热键在密码框里不录音、不写剪贴板。
- **T4.3 实测零联网**：输入法进程用 `nettop`/LuLu 观察一天；Settings 只在点下载、点检查更新时有连接。
- **T4.4 无临时文件**：`fs_usage` 确认录音、识别期间不写音频文件。
- **T4.5 `PRIVACY.md`**：程序会做什么、不会做什么、唯一联网的时机、剪贴板写入的代价（会覆盖原内容，剪贴板管理工具会记下）。

## M5 日常使用

完成标准：D 卸载或停用旧输入法。

- **T5.1** D 用一到两周替代微信/网易输入法，问题记 issue。
- **T5.2** 检查自动调频的效果：常用词是否排到前面，四码唯一自动上屏有没有被意外打断。如果被打断，查 userdb 里多出来的词条是从哪来的。

## M6 公开发布

完成标准：语音输入稳定可用；Universal 安装包公证通过。

- **T6.1 Intel 测试**：CI 的 Intel 机器跑构建和自动测试；找人在 Intel 真机上测识别延迟。
- **T6.2 Whisper 引擎**：`SpeechTranscriberFactory` 的第二个实现（MIT 权重），Settings 里可选，防止 FunASR 协议改成不能接受的条款。
- **T6.3 签名、公证、安装包**：Developer ID + Hardened Runtime，内层先签（dylib、Settings），外层后签；`notarytool` 公证；`pkgbuild`/`productbuild` 打包装到 `/Library/Input Methods`，postinstall 注册、启用输入源。
- **T6.4 许可证文本**：把各组件许可证放进 `Contents/Resources/Licenses/`，“关于”页能看全文。
- **T6.5 公开前检查**：公开前清单（密钥、邮箱、路径、git 历史、`NOTICE`、`SECURITY.md`、`PRIVACY.md`），然后公开仓库。

## 之后（不在第一版）

模型对比（Paraformer / Whisper）、标点模型、本地 LLM 纠错、大模型润色（付费，Settings 里明确开启才联网）、拼音、繁体、Windows、iOS、Android。
