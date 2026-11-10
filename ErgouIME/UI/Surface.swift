// ergou-ime — one visual language for the candidate window and the voice HUD.
// SPDX-License-Identifier: GPL-3.0-only
//
// From the independent audit (2026-11-09): the two floating surfaces used
// different radii, materials, borders, shadows, type sizes and motion.
// Everything floating now takes its values from here.
//
//   radius   small 5 (keycaps), medium 10 (panels, cards), capsule
//   surface  follows light/dark: .popover in light, .hudWindow + 10 % black
//            in dark; 0.5 pt separator-colour hairline
//   shadow   two soft layers: 14 % r20 y8 + 8 % r1.5 y0.5
//   type     text that will be typed 16 regular; status 13 medium;
//            secondary 12; keycaps 11 medium
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
    static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

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

    /// Material + hairline for SwiftUI surfaces (light/dark aware).
    struct Background: View {
        var corner: CGFloat
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            ZStack {
                MaterialView(material: scheme == .dark ? .hudWindow : .popover)
                if scheme == .dark { Color.black.opacity(0.10) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .overlay(RoundedRectangle(cornerRadius: Surface.radiusSmall, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
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
