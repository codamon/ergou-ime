// ergou-ime — how the candidate window looks (设置 › 外观).
// SPDX-License-Identifier: GPL-3.0-only
//
// A user asked for a few looks to choose from and for the type to be
// adjustable (2026-11-12). There are three looks, a colour for the chosen
// candidate, and a type size. Colours are not free: every combination here
// keeps the 4.5:1 contrast the candidate window was redrawn for in 0.5.1
// (measured by tools/panel-preview).

import Foundation

extension SettingKey {
    /// String, PanelLook raw value, default glass.
    static let panelLook = "panelLook"
    /// String, PanelAccent raw value, default system.
    static let panelAccent = "panelAccent"
    /// Int, point size of the candidate text, one of PanelStyle.fontSizes, default 16.
    static let panelFontSize = "panelFontSize"
    /// String, PanelLayout raw value, default horizontal.
    static let panelLayout = "panelLayout"
}

/// Candidates in a row (default) or one under another.
enum PanelLayout: String, CaseIterable, Identifiable {
    case horizontal, vertical
    var id: String { rawValue }

    var title: String { self == .horizontal ? "横排" : "竖排" }
}

enum PanelLook: String, CaseIterable, Identifiable {
    case glass, solid, compact
    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "玻璃"
        case .solid: return "实底"
        case .compact: return "紧凑"
        }
    }

    var detail: String {
        switch self {
        case .glass: return "半透明，透出后面的颜色。"
        case .solid: return "不透明，在任何屏幕上都最清楚。"
        case .compact: return "半透明，间距和圆角更小，少占地方。"
        }
    }
}

/// Colour of the block behind the chosen candidate.
enum PanelAccent: String, CaseIterable, Identifiable {
    case system, blue, purple, red, orange, green, teal, graphite
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .red: return "红"
        case .orange: return "橙"
        case .green: return "绿"
        case .teal: return "青"
        case .graphite: return "石墨"
        }
    }
}

struct PanelStyle: Equatable {
    var look = PanelLook.glass
    var accent = PanelAccent.system
    var fontSize = PanelStyle.defaultFontSize
    var layout = PanelLayout.horizontal

    static let fontSizes = [14, 16, 18, 20, 24]
    static let defaultFontSize = 16

    // Sizes that follow the look. Compact is for small screens and for
    // people who want the window out of the way.
    var cornerRadius: CGFloat { look == .compact ? 7 : 10 }
    var chosenRadius: CGFloat { look == .compact ? 4.5 : 6 }
    var panelPadding: CGSize { look == .compact ? CGSize(width: 4, height: 3) : CGSize(width: 6, height: 5) }
    var itemPadding: CGSize { look == .compact ? CGSize(width: 5, height: 2) : CGSize(width: 7, height: 4) }
    var itemGap: CGFloat { look == .compact ? 1 : 2 }
    /// Numbers and codes: three quarters of the text, never under 11 pt.
    var secondarySize: CGFloat { max(11, (CGFloat(fontSize) * 0.75).rounded()) }

    /// Set by tools/panel-preview to draw a style without touching the settings.
    static var override: PanelStyle?

    /// The saved style. Read from the shared settings at most twice a
    /// second: the candidate window asks on every key.
    static var current: PanelStyle {
        if let override { return override }
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, now - cached.at < 0.5 { return cached.style }
        let defaults = Paths.sharedDefaults
        var style = PanelStyle()
        if let raw = defaults.string(forKey: SettingKey.panelLook), let look = PanelLook(rawValue: raw) {
            style.look = look
        }
        if let raw = defaults.string(forKey: SettingKey.panelAccent), let accent = PanelAccent(rawValue: raw) {
            style.accent = accent
        }
        if let size = defaults.object(forKey: SettingKey.panelFontSize) as? Int, fontSizes.contains(size) {
            style.fontSize = size
        }
        if let raw = defaults.string(forKey: SettingKey.panelLayout), let layout = PanelLayout(rawValue: raw) {
            style.layout = layout
        }
        cached = (style, now)
        return style
    }

    private static var cached: (style: PanelStyle, at: TimeInterval)?
}
