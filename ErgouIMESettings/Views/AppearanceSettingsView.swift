// ErgouIME Settings — 外观: how the candidate window looks.
// SPDX-License-Identifier: GPL-3.0-only
//
// Three looks, a row or a column, a colour for the chosen candidate and a type size
// (Shared/PanelStyle.swift). The sample at the top is the input method's
// own drawing code (ErgouIME/UI/PanelSurface.swift), not a copy of it. The
// input method reads these settings when it next shows the window; nothing
// is redeployed.

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(SettingKey.panelLook, store: Paths.sharedDefaults)
    private var lookRaw = PanelLook.glass.rawValue
    @AppStorage(SettingKey.panelAccent, store: Paths.sharedDefaults)
    private var accentRaw = PanelAccent.system.rawValue
    @AppStorage(SettingKey.panelFontSize, store: Paths.sharedDefaults)
    private var fontSize = PanelStyle.defaultFontSize
    @AppStorage(SettingKey.panelLayout, store: Paths.sharedDefaults)
    private var layoutRaw = PanelLayout.horizontal.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var style: PanelStyle {
        PanelStyle(look: PanelLook(rawValue: lookRaw) ?? .glass,
                   accent: PanelAccent(rawValue: accentRaw) ?? .system,
                   fontSize: PanelStyle.fontSizes.contains(fontSize) ? fontSize : PanelStyle.defaultFontSize,
                   layout: PanelLayout(rawValue: layoutRaw) ?? .horizontal)
    }

    /// Room for five candidates one under another at the chosen size.
    private var sampleHeight: CGFloat {
        guard style.layout == .vertical else { return 132 }
        let line = CGFloat(style.fontSize) * 1.25 + style.itemPadding.height * 2 + style.itemGap
        return (line * 5 + style.panelPadding.height * 2 + 70).rounded()
    }

    var body: some View {
        Form {
            Section {
                PanelSample(style: style)
                    .frame(height: sampleHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                    .accessibilityLabel("候选窗示例")
            }

            Section {
                Picker(selection: $lookRaw) {
                    ForEach(PanelLook.allCases) { look in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(look.title)
                            Text(look.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(look.rawValue)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .noFocusRing()
                Picker(selection: $layoutRaw) {
                    ForEach(PanelLayout.allCases) { Text($0.title).tag($0.rawValue) }
                } label: {
                    Text("排列")
                    Text(style.layout == .vertical
                         ? "候选一个在另一个下面。上下方向键移动，左右方向键在拼音里移动光标。"
                         : "候选排成一行。左右方向键移动，按下方向键展开更多候选。")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("样式")
            } footer: {
                if reduceTransparency || contrast == .increased {
                    Text("系统的“降低透明度”或“增强对比度”开着，候选窗现在总是用实底。")
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        ForEach(PanelAccent.allCases) { accent in
                            AccentSwatch(accent: accent, isOn: accent.rawValue == accentRaw) {
                                accentRaw = accent.rawValue
                            }
                        }
                    }
                } label: {
                    Text("选中的候选")
                    Text(style.accent == .system ? "跟随 系统设置 › 外观 里的强调色。" : style.accent.title)
                }
                Picker(selection: $fontSize) {
                    ForEach(PanelStyle.fontSizes, id: \.self) { size in
                        Text(size == PanelStyle.defaultFontSize ? "\(size)（默认）" : "\(size)").tag(size)
                    }
                } label: {
                    Text("字号")
                    Text("候选字的大小；序号和编码跟着变。")
                }
            } header: {
                Text("颜色和字号")
            } footer: {
                Text("改完马上生效，下次打字就能看到。每种搭配的文字对比度都不低于 4.5:1。")
            }
        }
        .formStyle(.grouped)
    }
}

/// One colour to pick. The system one is a ring of colours, because it is
/// whatever the user chose in System Settings.
private struct AccentSwatch: View {
    let accent: PanelAccent
    let isOn: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            ZStack {
                if accent == .system {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                  center: .center))
                } else {
                    Circle().fill(Color(nsColor: Surface.selection(accent).fill))
                }
                if isOn {
                    Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4)
                }
            }
            .frame(width: 18, height: 18)
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(accent.title)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The real candidate window surface over a stand-in for a document and a
/// desktop picture, so the difference between glass and solid shows.
private struct PanelSample: NSViewRepresentable {
    let style: PanelStyle

    func makeNSView(context: Context) -> PanelSampleView { PanelSampleView() }
    func updateNSView(_ view: PanelSampleView, context: Context) { view.style = style }
}

final class PanelSampleView: NSView {
    var style = PanelStyle() { didSet { needsLayout = true } }
    private let surface = PanelSurfaceView()
    private let shadowView = SurfaceShadowView()
    private let backdrop = SampleBackdropView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        surface.blendsWithinWindow = true
        addSubview(backdrop)
        addSubview(shadowView)
        addSubview(surface)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        backdrop.needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        let sample = [("世", "an"), ("按", "rpv"), ("俺", "wdjn"), ("安", "pv"), ("暗", "ju")]
            .map { Candidate(text: $0.0, comment: $0.1, label: nil) }
        let size = surface.update(candidates: sample, highlighted: 0, hasPrevious: false, hasNext: true, style: style)
        let frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(),
                           y: ((bounds.height - size.height) / 2 - 8).rounded(),
                           width: size.width, height: size.height)
        surface.frame = frame
        shadowView.radius = style.cornerRadius
        shadowView.frame = frame
    }
}

/// Half a page of text, half a colourful picture.
private final class SampleBackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGradient(colors: [.systemIndigo, .systemPink, .systemOrange])?.draw(in: bounds, angle: 25)
        let page = NSRect(x: 0, y: 0, width: (bounds.width * 0.56).rounded(), height: bounds.height)
        (dark ? NSColor(white: 0.11, alpha: 1) : NSColor.white).setFill()
        page.fill()
        let ink = dark ? NSColor(white: 0.86, alpha: 1) : NSColor(white: 0.12, alpha: 1)
        for (i, line) in ["今天下午两点半开会，记得带上", "预算表和上周的会议记录。", "The quick brown fox jumps over", "序号、编码和箭头都要看得清。"].enumerated() {
            (line as NSString).draw(at: NSPoint(x: 16, y: 12 + CGFloat(i) * 26), withAttributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: ink])
        }
    }
}
