// ergou-ime — candidate window preview and contrast check.
// SPDX-License-Identifier: GPL-3.0-only
//
// Shows the real CandidatePanel (and the voice HUD) over a set of
// backdrops (white document, dark editor, busy picture, pure black, pure
// white), in light, dark, Increase Contrast and Reduce Transparency, takes
// a picture of each and measures the WCAG contrast of every kind of
// candidate text against the pixels actually behind it.
// Run through run.sh; it must start with `open` (a window server session).

import AppKit

struct Candidate: Equatable {
    var text: String
    var comment: String?
    var label: String?
}

// MARK: Backdrops

enum Backdrop: String { case document, editor, busy, black, white }

final class BackdropView: NSView {
    var kind = Backdrop.document { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch kind {
        case .black: NSColor.black.setFill(); bounds.fill()
        case .white: NSColor.white.setFill(); bounds.fill()
        case .document: page(paper: .white, ink: NSColor(white: 0.12, alpha: 1))
        case .editor: page(paper: NSColor(white: 0.11, alpha: 1), ink: NSColor(white: 0.86, alpha: 1))
        case .busy: busy()
        }
    }

    private func page(paper: NSColor, ink: NSColor) {
        paper.setFill(); bounds.fill()
        let lines = ["候选窗就在这一行文字的下面，背后是正在写的文档。",
                     "The quick brown fox jumps over the lazy dog, 1234567890.",
                     "序号、编码和翻页箭头都要在各种屏幕上看得清楚。",
                     "第四行文字，用来垫在候选窗的后面。", "第五行文字。"]
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 24, y: 14 + CGFloat(i) * 26), withAttributes: [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: ink])
        }
    }

    /// Saturated colours, hard light/dark edges and fine detail: the worst
    /// thing to put behind a translucent surface.
    private func busy() {
        NSGradient(colors: [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemIndigo])!
            .draw(in: bounds, angle: 20)
        for i in 0..<14 {
            let x = CGFloat(i) * bounds.width / 14
            (i % 2 == 0 ? NSColor.black : NSColor.white).withAlphaComponent(0.85).setFill()
            NSRect(x: x + 8, y: CGFloat(i % 5) * 22, width: 22, height: bounds.height).fill()
        }
        for i in 0..<9 {
            [NSColor.systemRed, .systemBlue, .white, .black, .systemPurple][i % 5].setFill()
            NSBezierPath(ovalIn: NSRect(x: 30 + CGFloat(i) * 84, y: 20 + CGFloat(i * 37 % 70), width: 58, height: 58)).fill()
        }
    }
}

// MARK: Measuring

typealias CaptureFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
/// CGWindowListCreateImage is no longer in the SDK headers, but a process may
/// still take a picture of its own windows with it (no Screen Recording grant).
let captureFunction = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage")!,
                                    to: CaptureFunction.self)

func capture(_ screenRect: NSRect) -> NSBitmapImageRep? {
    let height = NSScreen.screens[0].frame.height
    let rect = CGRect(x: screenRect.minX, y: height - screenRect.maxY, width: screenRect.width, height: screenRect.height)
    guard let image = captureFunction(rect, 1, 0, 0)?.takeRetainedValue() else { return nil }
    return NSBitmapImageRep(cgImage: image)
}

struct RGB { var r, g, b: CGFloat }

func rgb(_ color: NSColor, in appearance: NSAppearance) -> (RGB, CGFloat) {
    var out = (RGB(r: 0, g: 0, b: 0), CGFloat(1))
    appearance.performAsCurrentDrawingAppearance {
        let c = color.usingColorSpace(.sRGB)!
        out = (RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent), c.alphaComponent)
    }
    return out
}

func over(_ fg: (RGB, CGFloat), _ bg: RGB) -> RGB {
    let a = fg.1
    return RGB(r: fg.0.r * a + bg.r * (1 - a), g: fg.0.g * a + bg.g * (1 - a), b: fg.0.b * a + bg.b * (1 - a))
}

func luminance(_ c: RGB) -> CGFloat {
    func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}

func ratio(_ a: RGB, _ b: RGB) -> CGFloat {
    let la = luminance(a), lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Pixels of the picture inside `rect` (points, origin top-left of the picture).
func pixels(_ rep: NSBitmapImageRep, _ rect: NSRect, scale: CGFloat) -> [RGB] {
    var out: [RGB] = []
    let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale)
    let y0 = Int(rect.minY * scale), y1 = Int(rect.maxY * scale)
    for y in stride(from: y0, to: y1, by: 1) {
        for x in stride(from: x0, to: x1, by: 2) {
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                  let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            out.append(RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent))
        }
    }
    return out
}

// MARK: Scenes

struct Scene {
    var name: String
    var backdrop: Backdrop
    var appearance: NSAppearance.Name
    var increaseContrast = false
    var reduceTransparency = false
    var legacy = false
    var grid = false
    var hud = false
}

let scenes: [Scene] = [
    Scene(name: "light-document", backdrop: .document, appearance: .aqua),
    Scene(name: "light-busy", backdrop: .busy, appearance: .aqua),
    Scene(name: "light-black", backdrop: .black, appearance: .aqua),
    Scene(name: "dark-editor", backdrop: .editor, appearance: .darkAqua),
    Scene(name: "dark-busy", backdrop: .busy, appearance: .darkAqua),
    Scene(name: "dark-white", backdrop: .white, appearance: .darkAqua),
    Scene(name: "contrast-light", backdrop: .busy, appearance: .accessibilityHighContrastAqua, increaseContrast: true),
    Scene(name: "contrast-dark", backdrop: .busy, appearance: .accessibilityHighContrastDarkAqua, increaseContrast: true),
    Scene(name: "opaque-light", backdrop: .busy, appearance: .aqua, reduceTransparency: true),
    Scene(name: "opaque-dark", backdrop: .busy, appearance: .darkAqua, reduceTransparency: true),
    Scene(name: "legacy-light-document", backdrop: .document, appearance: .aqua, legacy: true),
    Scene(name: "legacy-light-black", backdrop: .black, appearance: .aqua, legacy: true),
    Scene(name: "legacy-dark-busy", backdrop: .busy, appearance: .darkAqua, legacy: true),
    Scene(name: "legacy-dark-white", backdrop: .white, appearance: .darkAqua, legacy: true),
    Scene(name: "grid-light", backdrop: .document, appearance: .aqua, grid: true),
    Scene(name: "hud-light-document", backdrop: .document, appearance: .aqua, hud: true),
    Scene(name: "hud-dark-editor", backdrop: .editor, appearance: .darkAqua, hud: true),
    Scene(name: "hud-light-busy", backdrop: .busy, appearance: .aqua, hud: true),
    Scene(name: "hud-dark-white", backdrop: .white, appearance: .darkAqua, hud: true),
    Scene(name: "hud-contrast-light", backdrop: .busy, appearance: .accessibilityHighContrastAqua,
          increaseContrast: true, hud: true),
    Scene(name: "hud-legacy-dark-busy", backdrop: .busy, appearance: .darkAqua, legacy: true, hud: true),
]

let row = [Candidate(text: "世", comment: "an", label: nil), Candidate(text: "按", comment: "rpv", label: nil),
           Candidate(text: "俺", comment: "wdjn", label: nil), Candidate(text: "安", comment: "pv", label: nil),
           Candidate(text: "暗", comment: "ju", label: nil)]
let grid = ["世", "按", "俺", "安", "暗", "案", "岸", "鞍", "氨", "庵", "谙", "胺", "黯", "铵", "桉"]
    .map { Candidate(text: $0, comment: nil, label: nil) }

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// SCREEN=1x runs on a display without Retina scaling, if one is attached.
let wantLowResolution = ProcessInfo.processInfo.environment["SCREEN"] == "1x"
// Not NSScreen.main: that is whichever display has the keyboard focus.
let screen = NSScreen.screens.first { ($0.backingScaleFactor == 1) == wantLowResolution } ?? NSScreen.screens[0]
print("screen", screen.frame, "scale", screen.backingScaleFactor)
let stage = NSRect(x: (screen.visibleFrame.maxX - 800).rounded(), y: (screen.visibleFrame.minY + 40).rounded(),
                   width: 760, height: 230)
let backWindow = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
let backdrop = BackdropView(frame: NSRect(origin: .zero, size: stage.size))
backWindow.contentView = backdrop
backWindow.level = .floating
backWindow.orderFrontRegardless()

// Tuning aids: ONLY="light-black,dark-white" limits the run,
// TINT="0.4,0.72" sets the scrim under the text (light, dark).
let environment = ProcessInfo.processInfo.environment
if let tint = environment["TINT"]?.split(separator: ",").compactMap({ Double($0) }), tint.count == 2 {
    Surface.scrimAlpha = (CGFloat(tint[0]), CGFloat(tint[1]))
}
let only = environment["ONLY"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
let jobs = scenes.filter { only?.contains($0.name) ?? true }
var results: [[String: Any]] = []

func runNext(_ index: Int) {
    guard index < jobs.count else {
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: outDir.appendingPathComponent("contrast.json"))
        exit(0)
    }
    let scene = jobs[index]
    let appearance = NSAppearance(named: scene.appearance)!
    app.appearance = appearance
    backdrop.kind = scene.backdrop
    Surface.Access.override = (scene.increaseContrast, scene.reduceTransparency)
    CandidatePanel.forceLegacyMaterial = scene.legacy
    // The caret sits under the first line of the backdrop.
    let caret = NSRect(x: stage.minX + 60, y: stage.maxY - 40, width: 1, height: 20)
    let panel = CandidatePanel.shared
    panel.hide()
    VoiceHUD.shared.panel.orderOut(nil)
    if scene.hud {
        VoiceHUD.shared.listening()
        for i in 0..<40 { VoiceHUD.shared.level(Float(abs(sin(Double(i) * 0.7))) * 0.8) }
        VoiceHUD.shared.transcript("下午两点半开会，预算五万块")
        VoiceHUD.shared.panel.setFrameOrigin(NSPoint(x: stage.midX - 300, y: stage.minY + 10))
    } else if scene.grid {
        panel.showGrid(candidates: grid, highlighted: 6, caretRect: caret, columns: 5)
    } else {
        panel.show(candidates: row, highlighted: 0, caretRect: caret, hasPrevious: false, hasNext: true)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + (scene.hud ? 1.2 : 0.7)) {
        guard let rep = capture(stage) else { print("capture failed", scene.name); exit(1) }
        let file = "\(scene.name).png"
        try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(file))
        let scale = CGFloat(rep.pixelsWide) / stage.width
        var entry: [String: Any] = ["scene": scene.name, "file": file]
        if !scene.grid, !scene.hud {
            entry["contrast"] = measure(rep, scale: scale, appearance: appearance)
            entry["clicks"] = checkClicks()
        }
        results.append(entry)
        runNext(index + 1)
    }
}

/// Would a click reach the panel, and does it pick the right candidate?
/// Asks the window server which window a mouse-down at a point would hit,
/// then hands the panel a mouse-up there (posting real events would need
/// the Accessibility permission).
func checkClicks() -> [String: Any] {
    let panel = CandidatePanel.shared
    let window = panel.panel
    var picked = -1
    let previous = panel.onSelect
    panel.onSelect = { picked = $0 }
    defer { panel.onSelect = previous }
    let item = panel.row.items[2].rect
    let inWindow = panel.row.convert(NSPoint(x: item.midX, y: item.midY), to: nil)
    let onScreen = window.convertPoint(toScreen: inWindow)
    let hit = NSWindow.windowNumber(at: onScreen, belowWindowWithWindowNumber: 0)
    if let event = NSEvent.mouseEvent(with: .leftMouseUp, location: inWindow, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 0) {
        window.sendEvent(event)
    }
    // In the shadow, 12 pt left of the surface: must fall through to what is below.
    let beside = NSPoint(x: window.frame.minX - 12, y: window.frame.midY)
    let besideHit = NSWindow.windowNumber(at: beside, belowWindowWithWindowNumber: 0)
    return ["candidate.reaches-panel": hit == window.windowNumber, "candidate.picked": picked,
            "beside.blocked-by-panel": besideHit == window.windowNumber
                || besideHit == panel.shadowPanel.windowNumber,
            "ignoresMouseEvents": window.ignoresMouseEvents]
}

/// Worst contrast of each kind of text against the pixels behind it. The
/// backdrop is read from the strips above and below the glyphs inside each
/// item (the item's vertical padding), where no text is drawn.
func measure(_ rep: NSBitmapImageRep, scale: CGFloat, appearance: NSAppearance) -> [String: Double] {
    let panel = CandidatePanel.shared
    let rowView = panel.row
    let frame = panel.panel.frame
    func strips(_ rect: NSRect) -> [RGB] {
        // rect is in the row view (flipped); convert to picture points.
        let inWindow = rowView.convert(rect, to: nil)
        let x = frame.minX + inWindow.minX - stage.minX
        let top = stage.maxY - (frame.minY + inWindow.maxY)
        // Stay clear of the rounded corners of the chosen block.
        let a = NSRect(x: x + 7, y: top + 0.5, width: rect.width - 14, height: 2)
        let b = NSRect(x: x + 7, y: top + rect.height - 2.5, width: rect.width - 14, height: 2)
        return pixels(rep, a, scale: scale) + pixels(rep, b, scale: scale)
    }
    func worst(_ fg: NSColor, on bgs: [RGB], extra: ((RGB) -> RGB)? = nil) -> Double {
        let color = rgb(fg, in: appearance)
        return Double(bgs.map { bg -> CGFloat in
            let under = extra?(bg) ?? bg
            return ratio(over(color, under), under)
        }.min() ?? 0)
    }
    var out: [String: Double] = [:]
    var plain: [RGB] = [], chosen: [RGB] = []
    for item in rowView.items {
        if item.highlighted { chosen += strips(item.rect) } else { plain += strips(item.rect) }
    }
    out["candidate"] = worst(.labelColor, on: plain)
    out["candidate.chosen"] = worst(Surface.onSelection, on: chosen)
    out["number"] = worst(Surface.quietText, on: plain)
    out["number.chosen"] = out["candidate.chosen"]
    out["code"] = worst(Surface.quietText, on: plain)
    if let hint = rowView.pageHint {
        let bg = strips(hint.rect)
        out["arrow"] = worst(Surface.quietText, on: bg)
        out["arrow.unavailable"] = worst(Surface.disabledText, on: bg)
    }
    // How much lighter or darker the chosen block is than the surface next to it.
    if !chosen.isEmpty, !plain.isEmpty {
        out["chosen.block-vs-surface"] = Double(plain.map { p in chosen.map { ratio($0, p) }.min()! }.min()!)
    }
    return out
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runNext(0) }
app.run()
