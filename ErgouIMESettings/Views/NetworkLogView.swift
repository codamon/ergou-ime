// ErgouIME Settings — 联网记录: every request ErgouIME made (Shared/NetworkLog.swift).
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import SwiftUI

struct NetworkLogView: View {
    @State private var entries: [NetworkLogEntry] = []
    @State private var confirmClear = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Text("二狗输入法每一次联网都记在这里：什么时候、做什么、连了哪个服务器、发出了什么。输入法本体没有网络权限，从来不会出现在这里；会联网的只有设置程序（下载、检查更新）和你打开了才用的云端整理。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("“发出了什么”只记数量和字数，不记内容。这份记录由联网的程序自己写，想独立核对，可以在终端运行 nettop，或者用 Little Snitch、LuLu 这类防火墙看二狗的连接。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if entries.isEmpty {
                    Text("还没有联网记录。").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { NetworkLogRow(entry: $0) }
                }
            } header: {
                HStack {
                    Text(entries.isEmpty ? "记录" : "记录（最近 \(entries.count) 条）")
                    Spacer()
                    Button("清空…", role: .destructive) { confirmClear = true }
                        .disabled(entries.isEmpty)
                }
            } footer: {
                Text("只存在这台 Mac 上，保留最近 \(NetworkLog.maxEntries) 条。")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            NetworkLog.trimIfNeeded()
            entries = NetworkLog.load()
        }
        .onReceive(timer) { _ in
            let now = NetworkLog.load()
            if now != entries { entries = now }
        }
        .confirmationDialog("清空联网记录？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) {
                NetworkLog.clear()
                entries = []
            }
        }
    }
}

private struct NetworkLogRow: View {
    let entry: NetworkLogEntry

    private var ok: Bool { entry.result.hasPrefix("HTTP 2") || entry.result.hasPrefix("HTTP 3") }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.purpose).fontWeight(.medium)
                Text(entry.program).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(entry.host + entry.path)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            HStack(spacing: 10) {
                Text("发出：\(entry.sent)")
                Spacer(minLength: 8)
                Text("↑ \(size(entry.bytesSent))  ↓ \(size(entry.bytesReceived))").monospacedDigit()
                Label(entry.result, systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(ok ? Color.secondary : Color.orange)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
