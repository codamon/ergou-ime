// ergou-ime — voice HUD, bottom centre of the screen (D, 2026-11-09).
// SPDX-License-Identifier: GPL-3.0-only
//
//            ╭──────────────────────────────────────╮
//            │ 下午两点半开会，预算五万块            │   live text, ≤ 3 lines
//            ╰──────────────────────────────────────╯
//                  ╭──────────────────────────╮
//                  │  ●  ▁▃▅▇▅▃▁▃▅▇▅▃▁   Esc   │       listening
//                  ╰──────────────────────────╯
//
// Always the same place, so the eye learns where to look (like Wispr Flow's
// bar). Styling from Surface.swift, shared with the candidate window, and
// it follows light/dark mode. Motion: the capsule settles in, the bars
// follow the voice, and a soft sheen crosses the label while recognising
// and tidying. Non-activating, ignores the mouse, never takes focus.

import AppKit
import SwiftUI

final class VoiceHUD {
    static let shared = VoiceHUD()

    enum Phase: Equatable {
        case hidden
        case listening
        case working(String, skippable: Bool)   // 识别中 / 整理中 (↩ 跳过)
        case note(String, symbol: String)
    }

    private let model = VoiceHUDModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private static let size = NSSize(width: 600, height: 200)

    private init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.canHide = false                         // survives NSApp.hide (PickListWindow)
        panel.ignoresMouseEvents = true
        panel.hasShadow = false                       // surfaces draw their own
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        let host = NSHostingView(rootView: VoiceHUDView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    // MARK: - API (main thread)

    func listening() {
        hideWork?.cancel()
        model.transcript = ""
        model.levels = Array(repeating: 0, count: VoiceHUDModel.barCount)
        show(.listening)
    }

    func level(_ value: Float) { model.push(level: CGFloat(value)) }

    /// No animation per update: re-fading the text every 0.7 s made it look
    /// unsteady (independent audit, 2026-11-09).
    func transcript(_ text: String) { model.transcript = text }

    func working(_ text: String, skippable: Bool = false) {
        hideWork?.cancel()
        show(.working(text, skippable: skippable))
    }

    func note(_ text: String, symbol: String, for seconds: TimeInterval = 2.2) {
        hideWork?.cancel()
        show(.note(text, symbol: symbol))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        withAnimation(Surface.disappear) { model.phase = .hidden }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.model.phase == .hidden else { return }
            self.panel.orderOut(nil)
            self.model.transcript = ""
        }
    }

    private func show(_ phase: Phase) {
        place()
        if !panel.isVisible { panel.orderFrontRegardless() }
        withAnimation(Surface.appear) { model.phase = phase }
    }

    /// Bottom centre of the screen under the mouse, above the Dock.
    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 24))
    }
}

// MARK: - Model

final class VoiceHUDModel: ObservableObject {
    static let barCount = 23
    @Published var phase: VoiceHUD.Phase = .hidden
    @Published var transcript = ""
    @Published var levels: [CGFloat] = Array(repeating: 0, count: barCount)
    private var smoothed: CGFloat = 0

    /// Newest level enters at the centre and travels outwards, so the bars
    /// read as a voice rather than a scrolling chart.
    func push(level: CGFloat) {
        smoothed = level > smoothed ? level : smoothed * 0.72 + level * 0.28   // fast attack, soft release
        var half = Array(levels[(Self.barCount / 2)...])
        half.insert(smoothed, at: 0)
        half.removeLast()
        let left = Array(half.dropFirst().reversed())
        withAnimation(.linear(duration: 1.0 / 30)) { levels = left + half }
    }
}

// MARK: - Views

private struct VoiceHUDView: View {
    @ObservedObject var model: VoiceHUDModel

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if !model.transcript.isEmpty, model.phase != .hidden {
                TranscriptCard(text: model.transcript)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
            if model.phase != .hidden {
                HUDCapsule(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .frame(width: 600, height: 200, alignment: .bottom)
        .padding(.bottom, 8)
    }
}

/// Subtitle-style live text that hugs its content: a short line gets a
/// small card centred over the capsule; longer text wraps at a fixed width
/// (so it never shifts sideways), grows to 3 lines, then older lines fade
/// out at the top. (A max-height frame made a one-line card 3 lines tall
/// and full width, D's screenshot 2026-11-09.)
private struct TranscriptCard: View {
    let text: String
    private static let maxWidth: CGFloat = 448          // text width; card adds 32
    private static let lineHeight: CGFloat = 23         // 16 pt + spacing 4

    /// Lines the text wraps to at maxWidth, measured with the real font
    /// (a characters-per-line guess was wrong for Latin and mixed text).
    private static func lineCount(_ text: String) -> Int {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16)]
        let bounds = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let height = (text as NSString).boundingRect(with: bounds, options: options, attributes: attributes, context: nil).height
        let oneLine = ("中" as NSString).boundingRect(with: bounds, options: options, attributes: attributes, context: nil).height
        guard oneLine > 0 else { return 1 }
        return max(1, Int((height / oneLine).rounded()))
    }

    var body: some View {
        let lines = Self.lineCount(text)
        let overflowing = lines > 3
        Group {
            if lines == 1 {
                label.fixedSize()
            } else {
                label
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.maxWidth, alignment: .leading)
                    .frame(height: Self.lineHeight * CGFloat(min(lines, 3)) - 4, alignment: .bottom)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: overflowing ? .clear : .black, location: 0),
                                                 .init(color: .black, location: 0.32),
                                                 .init(color: .black, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Surface.Background(corner: Surface.radiusMedium))
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
    }
}

private struct HUDCapsule: View {
    @ObservedObject var model: VoiceHUDModel

    var body: some View {
        HStack(spacing: 12) {
            leading
            center
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Surface.Background(corner: 19))
        .animation(Surface.appear, value: model.phase)
    }

    @ViewBuilder private var leading: some View {
        switch model.phase {
        case .listening:
            BreathingDot()
        case let .note(_, symbol):
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: Surface.quietText))
        case .working, .hidden:
            EmptyView()
        }
    }

    @ViewBuilder private var center: some View {
        switch model.phase {
        case .listening:
            Bars(levels: model.levels)
                .frame(width: 140, height: 20)
        case let .working(text, _):
            SheenLabel(text: text)
        case let .note(text, _):
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 360)
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.phase {
        case .listening: Surface.Keycap(text: "Esc")
        case .working(_, true): Surface.Keycap(text: "↩ 跳过")
        default: EmptyView()
        }
    }
}

/// Mirrored, rounded bars; height follows the voice. Quiet when silent.
private struct Bars: View {
    let levels: [CGFloat]
    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(levels.count)
            let gap: CGFloat = 2.5
            let w = max(2, (geo.size.width - gap * (n - 1)) / n)
            HStack(alignment: .center, spacing: gap) {
                ForEach(levels.indices, id: \.self) { i in
                    let falloff = 1 - abs(CGFloat(i) - (n - 1) / 2) / n * 0.9
                    let level = min(1, levels[i] * 1.25 * falloff)
                    Capsule()
                        .fill(Color.primary.opacity(0.3 + 0.65 * Double(level)))
                        .frame(width: w, height: max(w, geo.size.height * level))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Recording dot: breathes gently instead of flashing like an alarm.
private struct BreathingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Color(nsColor: .systemRed))
            .frame(width: 8, height: 8)
            .shadow(color: Color(nsColor: .systemRed).opacity(on ? 0.35 : 0.15), radius: on ? 4 : 2)
            .opacity(on ? 0.9 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// 识别中 / 整理中 with one soft highlight crossing it every two seconds.
private struct SheenLabel: View {
    let text: String
    @State private var x: CGFloat = -1
    var body: some View {
        let label = Text(text).font(.system(size: 13, weight: .medium))
        label
            .foregroundStyle(Color(nsColor: Surface.quietText))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.5), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: x * geo.size.width * 1.6)
                }
                .mask(label)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).delay(0.4).repeatForever(autoreverses: false)) { x = 1 }
            }
    }
}
