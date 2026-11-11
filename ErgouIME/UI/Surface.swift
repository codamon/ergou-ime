// ergou-ime — one visual language for the candidate window and the voice HUD.
// SPDX-License-Identifier: GPL-3.0-only
//
// From the independent audit (2026-11-09): the two floating surfaces used
// different radii, materials, borders, shadows, type sizes and motion.
// Everything floating now takes its values from here.
//
//   radius   small 5 (keycaps), medium 10 (panels, cards), capsule
//   surface  Liquid Glass on macOS 26 and later, a blur material before
//            that, each with a scrim under the text; opaque with an
//            outline for Reduce Transparency and Increase Contrast
//   shadow   two soft layers: 14 % r20 y8 + 8 % r1.5 y0.5, drawn by us
//            (the window server's shadow has a hard, jagged rim at 1x)
//   type     text that will be typed 16 regular; status 13 medium;
//            secondary 12; keycaps 11 medium
//   colour   quieter text is smaller, not fainter: every text colour
//            keeps 4.5:1 on the surface (measured by tools/panel-preview)
//   motion   appear/change spring(0.35, 0.9); disappear easeOut 0.2;
//            the candidate window itself never animates (latency)

import AppKit
import SwiftUI

enum Surface {
    static let radiusSmall: CGFloat = 5
    static let radiusMedium: CGFloat = 10

    static let textFont = NSFont.systemFont(ofSize: 16)
    static let textFontBold = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let secondaryFont = NSFont.systemFont(ofSize: 12)
    static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    // MARK: Colours for text on a floating surface
    //
    // The system's tertiary and quaternary label colours are too faint on a
    // translucent surface: a user could not see the candidate numbers at all
    // on a washed-out display (2026-11-11). Quieter text is told apart by
    // size and weight; its colour keeps at least 4.5:1 against the surface.

    /// Numbers, codes and other secondary text.
    static let quietText = NSColor(name: nil) { appearance in
        switch Look(appearance) {
        case .light: return NSColor(white: 0, alpha: 0.68)
        case .dark: return NSColor(white: 1, alpha: 0.78)
        case .lightHighContrast: return NSColor(white: 0, alpha: 0.9)
        case .darkHighContrast: return NSColor(white: 1, alpha: 0.92)
        }
    }

    /// Something that is there but cannot be used now (no previous page).
    static let disabledText = NSColor(name: nil) { appearance in
        switch Look(appearance) {
        case .light: return NSColor(white: 0, alpha: 0.30)
        case .dark: return NSColor(white: 1, alpha: 0.32)
        case .lightHighContrast: return NSColor(white: 0, alpha: 0.5)
        case .darkHighContrast: return NSColor(white: 1, alpha: 0.5)
        }
    }

    /// Fill behind the chosen item: the system's selection colour, which
    /// follows the accent colour the user picked, darkened a little when
    /// white text on it would fall short of 4.5:1 (the stock blue measured 4.2).
    static let selectionFill = NSColor(name: nil) { appearance in
        var fill = NSColor.systemBlue
        appearance.performAsCurrentDrawingAppearance {
            fill = NSColor.selectedContentBackgroundColor.usingColorSpace(.sRGB) ?? fill
        }
        guard contrast(.white, fill) >= 3 else { return fill }      // light accent: dark text instead
        var steps = 0
        while contrast(.white, fill) < selectionContrast, steps < 12 {
            fill = fill.blended(withFraction: 0.06, of: .black) ?? fill
            steps += 1
        }
        return fill
    }
    /// Aim above 4.5: colours measured on screen come out a little lower
    /// than the arithmetic on their nominal values.
    static var selectionContrast: CGFloat = 6

    /// Text on `selectionFill`: white, or near-black on a light accent
    /// colour such as yellow.
    static let onSelection = NSColor(name: nil) { appearance in
        var fill = NSColor.white
        appearance.performAsCurrentDrawingAppearance {
            fill = selectionFill.usingColorSpace(.sRGB) ?? .white
        }
        return contrast(.white, fill) >= 4.5 ? .white : NSColor(white: 0.1, alpha: 1)
    }

    /// Opaque surface used instead of glass or blur (Reduce Transparency,
    /// Increase Contrast).
    static let solidFill = NSColor(name: nil) { appearance in
        switch Look(appearance) {
        case .light, .lightHighContrast: return NSColor(white: 0.98, alpha: 1)
        case .dark, .darkHighContrast: return NSColor(white: 0.13, alpha: 1)
        }
    }

    /// Outline of a surface: a hairline normally, a firm line for Increase Contrast.
    static let outline = NSColor(name: nil) { appearance in
        switch Look(appearance) {
        case .light: return NSColor(white: 0, alpha: 0.14)
        case .dark: return NSColor(white: 1, alpha: 0.18)
        case .lightHighContrast: return NSColor(white: 0, alpha: 0.75)
        case .darkHighContrast: return NSColor(white: 1, alpha: 0.75)
        }
    }

    /// Laid over Liquid Glass or a blur material, under the text. Either
    /// alone lets too much through: dark glass over a white page measured
    /// 1.5:1 for white text. This keeps the surface light enough (or dark
    /// enough) for the text on it whatever is behind.
    /// (NSGlassEffectView.tintColor did not do it: a dark tint made the
    /// glass lighter over white.)
    static var scrimAlpha: (light: CGFloat, dark: CGFloat) = (0.4, 0.72)
    static let scrim = NSColor(name: nil) { appearance in
        switch Look(appearance) {
        case .light, .lightHighContrast: return NSColor(white: 1, alpha: scrimAlpha.light)
        case .dark, .darkHighContrast: return NSColor(white: 0.1, alpha: scrimAlpha.dark)
        }
    }

    enum Look {
        case light, dark, lightHighContrast, darkHighContrast
        init(_ appearance: NSAppearance) {
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let high = Access.increaseContrast || match == .accessibilityHighContrastAqua
                || match == .accessibilityHighContrastDarkAqua
            self = dark ? (high ? .darkHighContrast : .dark) : (high ? .lightHighContrast : .light)
        }
    }

    /// WCAG contrast ratio of two opaque sRGB colours.
    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ c: NSColor) -> CGFloat {
            guard let c = c.usingColorSpace(.sRGB) else { return 0 }
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: Accessibility settings

    /// System Settings › Accessibility › Display. Read once and kept up to
    /// date by a notification, so showing the candidate window stays cheap.
    enum Access {
        /// Set by the preview tool to draw a setting without changing the system.
        static var override: (increaseContrast: Bool, reduceTransparency: Bool)?

        private static var cached: (increaseContrast: Bool, reduceTransparency: Bool) = {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main) { _ in cached = read() }
            return read()
        }()

        private static func read() -> (increaseContrast: Bool, reduceTransparency: Bool) {
            (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
             NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        }

        static var increaseContrast: Bool { (override ?? cached).increaseContrast }
        /// Increase Contrast also asks for opaque surfaces, as the system does.
        static var opaqueSurfaces: Bool {
            let v = override ?? cached
            return v.increaseContrast || v.reduceTransparency
        }
    }

    static let appear = Animation.spring(response: 0.35, dampingFraction: 0.9)
    static let disappear = Animation.easeOut(duration: 0.2)

    /// Soft two-layer shadow for SwiftUI surfaces.
    struct Shadowed: ViewModifier {
        func body(content: Content) -> some View {
            content
                .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 1.5, x: 0, y: 0.5)
        }
    }

    /// The surface for SwiftUI views; same rules as the candidate window.
    struct Background: View {
        var corner: CGFloat
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            let firm = contrast == .increased || Access.increaseContrast
            Group {
                if firm || reduceTransparency || Access.opaqueSurfaces {
                    Color(nsColor: Surface.solidFill)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(Color(nsColor: Surface.outline), lineWidth: firm ? 1 : 0.5))
                } else if #available(macOS 26, *), !CandidatePanel.forceLegacyMaterial {
                    Color(nsColor: Surface.scrim)
                        .clipShape(shape)
                        .glassEffect(.regular, in: shape)
                } else {
                    ZStack {
                        MaterialView(material: scheme == .dark ? .hudWindow : .popover)
                        Color(nsColor: Surface.scrim)
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color(nsColor: Surface.outline), lineWidth: 0.5))
                }
            }
            .modifier(Shadowed())
        }
    }

    struct MaterialView: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        func makeNSView(context: Context) -> NSVisualEffectView {
            let v = NSVisualEffectView()
            v.material = material
            v.blendingMode = .behindWindow
            v.state = .active
            return v
        }
        func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
    }

    /// A small key, e.g. Esc or ↩ 跳过.
    struct Keycap: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(nsColor: Surface.quietText))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .overlay(RoundedRectangle(cornerRadius: Surface.radiusSmall, style: .continuous)
                    .strokeBorder(Color(nsColor: Surface.quietText).opacity(0.6), lineWidth: 0.5))
        }
    }

    /// Rounded-rect mask for an AppKit NSVisualEffectView, so the blur itself
    /// has round corners (a layer cornerRadius can leave square blur edges).
    static func maskImage(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
