#!/bin/bash
# ergou-ime — 修复“输入法列表里有很多个二狗”，并在桌面生成诊断报告。
# SPDX-License-Identifier: GPL-3.0-only
#
#   bash repair-input-sources.sh
#
# 不需要管理员权限，只动当前用户的东西：
#   1. 注销 LaunchServices 里所有不在 ~/Library/Input Methods/ErgouIME.app 的二狗登记
#      （旧版本、安装包临时目录、废纸篓里的副本……）；
#   2. 去掉“已启用的输入法”里重复的二狗条目（先备份 com.apple.HIToolbox）；
#   3. 删掉提到二狗的输入源缓存（系统会自动重建）；
#   4. 重新登记正式安装的二狗，重启输入法菜单。
# 诊断报告（含候选个数等设置）写到桌面，发给作者即可；里面没有你打过的字。
# 做完后请注销重新登录一次（或重启）。
set -u
ID=com.codamon.inputmethod.Ergou
APP="$HOME/Library/Input Methods/ErgouIME.app"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
OUT="$HOME/Desktop/二狗诊断-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$OUT") 2>&1

section() { printf '\n== %s\n' "$1"; }

# Paths of every LaunchServices record whose identifier is exactly $ID.
registered() {
  "$LSR" -dump 2>/dev/null | awk -v id="$ID" '
    /^-----/ { path = "" }
    /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
    /^identifier:/ { if ($2 == id && path != "") print path }'
}

section "系统和二狗版本"
sw_vers 2>/dev/null
if [[ -d "$APP" ]]; then
  echo "已安装：$APP"
  defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null
else
  echo "没有找到 $APP（二狗没装在默认位置）"
fi

section "磁盘上所有的二狗（Spotlight）"
mdfind "kMDItemCFBundleIdentifier == '$ID'" 2>/dev/null
ls -d /Library/Input\ Methods/ErgouIME*.app "$HOME"/.Trash/ErgouIME*.app 2>/dev/null

section "修复前：LaunchServices 登记"
registered | sort | uniq -c

section "修复前：已启用的二狗条目（com.apple.HIToolbox）"
defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -c "$ID\""
defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources 2>/dev/null | grep -c "$ID\""

section "1. 注销旧登记"
registered | sort -u | while IFS= read -r path; do
  [[ "$path" == "$APP" ]] && continue
  echo "注销：$path"
  "$LSR" -u "$path" 2>/dev/null || true
done

section "2. 去掉重复的启用条目"
backup="$HOME/Library/Preferences/com.apple.HIToolbox.ergou-backup-$(date +%Y%m%d-%H%M%S).plist"
tmp="$(mktemp -t ergou-hitoolbox)"
if defaults export com.apple.HIToolbox "$tmp" 2>/dev/null; then
  cp "$tmp" "$backup" && echo "已备份到 $backup"
  pb() { /usr/libexec/PlistBuddy -c "$1" "$tmp" 2>/dev/null; }
  removed=0
  for key in AppleEnabledInputSources AppleSelectedInputSources AppleInputSourceHistory; do
    n=0; while pb "Print :$key:$n" >/dev/null; do n=$((n + 1)); done
    seen="|"
    i=0
    # Keep the first of each (bundle, kind, mode); delete later duplicates.
    while (( i < n )); do
      b="$(pb "Print :$key:$i:Bundle\ ID")"
      if [[ "$b" == "$ID"* ]]; then
        k="$(pb "Print :$key:$i:InputSourceKind")"; m="$(pb "Print :$key:$i:Input\ Mode")"
        tag="$b/$k/$m"
        if [[ "$seen" == *"|$tag|"* ]]; then
          pb "Delete :$key:$i" >/dev/null; n=$((n - 1)); removed=$((removed + 1)); continue
        fi
        seen="$seen$tag|"
      fi
      i=$((i + 1))
    done
  done
  if (( removed > 0 )); then
    defaults import com.apple.HIToolbox "$tmp" && echo "去掉了 $removed 个重复条目"
  else
    echo "没有重复的启用条目"
  fi
fi
rm -f "$tmp"

section "3. 清输入源缓存"
cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
cleared=0
if [[ -n "$cache" && -d "$cache" ]]; then
  while IFS= read -r f; do
    if strings -a "$f" 2>/dev/null | grep -qF "$ID"; then rm -f "${f%.kbdx}" "$f" && cleared=$((cleared + 1)); fi
  done < <(find "$cache" -maxdepth 2 -name 'com.apple.IntlDataCache.le.kbdx' 2>/dev/null)
fi
echo "清掉 $cleared 份缓存"

section "4. 重新登记正式安装的二狗"
if [[ -d "$APP" ]]; then
  "$LSR" -f "$APP" 2>/dev/null || true
  "$APP/Contents/MacOS/ErgouIME" --register-input-source >/dev/null 2>&1 & pid=$!
  for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill "$pid" 2>/dev/null || true
fi
killall TextInputMenuAgent 2>/dev/null || true

section "修复后：LaunchServices 登记"
registered | sort | uniq -c

section "候选个数等设置（诊断用）"
for plist in "$HOME"/Library/Group\ Containers/*.com.codamon.ergou/Library/Preferences/*.com.codamon.ergou.plist; do
  [[ -f "$plist" ]] || continue
  for k in candidateCount inputScheme frequencyLearning; do
    printf '%s = %s\n' "$k" "$(/usr/libexec/PlistBuddy -c "Print :$k" "$plist" 2>/dev/null || echo 未设置)"
  done
done
R="$HOME/Library/Containers/$ID/Data/Library/Application Support/ErgouIME/Rime"
grep -H "page_size" "$R/default.custom.yaml" "$R"/build/default.yaml "$R"/build/ergou_*.schema.yaml 2>/dev/null
ls -l "$R/build" 2>/dev/null | head -20
pgrep -lf "Input Methods/ErgouIME.app/Contents/MacOS/ErgouIME" || echo "二狗进程没在运行"

section "完成"
echo "请注销重新登录一次（或重启），再看 系统设置 › 键盘 › 输入法。"
echo "诊断报告：$OUT —— 发给二狗的作者即可（里面有你的用户名，没有你打过的字）。"
