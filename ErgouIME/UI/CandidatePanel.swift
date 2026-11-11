// ergou-ime — candidate window (M1 T1.3).
// SPDX-License-Identifier: GPL-3.0-only
//
// A borderless, non-activating panel below the caret, one row:
//
//    ╭──────────────────────────────────────────────╮
//    │ ▕1 世▏  2 按 rpv · rpvg   3 俺 wdjn      ‹ ›  │
//    ╰──────────────────────────────────────────────╯
//
// The highlighted candidate sits on the system's selection colour, as in
// a menu; numbers and codes are smaller, not fainter (a user could not see
// faint numbers on a washed-out display, 2026-11-11). Down arrow expands
// the row into a grid of more candidates (like other Chinese input
// methods); click any candidate to pick it.
//
// Surface: Liquid Glass on macOS 26 and later, the popover material before
// that, and an opaque fill with a firm outline when Reduce Transparency or
// Increase Contrast is on. Styling comes from Surface.swift (shared with
// the voice HUD). No animation: the window must keep up with typing.

import AppKit

final class CandidatePanel {
    static let shared = CandidatePanel()

    /// Called with the index on the current page when a candidate is clicked.
    var onSelect: ((Int) -> Void)?

    /// For tools/panel-preview: draw the pre-macOS 26 material on a newer system.
    static var forceLegacyMaterial = false

    private enum Backing { case glass, material, solid }

    private let panel: ClickablePanel
    private let host = NSView()
    private var backingView: NSView?
    private var backing: Backing?
    private let row = CandidateRowView()
    private var flashWork: DispatchWorkItem?

    private let padding = NSSize(width: 6, height: 5)
    private let gapToCaret: CGFloat = 4
    /// The shadow has a window of its own, under the panel, that lets the
    /// mouse through: the panel stays exactly as large as what you can click.
    private let shadowPanel: NSPanel
    private let shadowRoom: CGFloat = 56              // the 20 pt blur reaches about 48 pt
    private let shadow = SurfaceShadowView()

    private init() {
        panel = ClickablePanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.becomesKeyOnlyIfNeeded = true
        // The window server's own shadow traces the window's shape with a
        // hard one-pixel dark rim. On a display without Retina scaling that
        // rim is a staircase round the corners (D, 2026-11-12), so the
        // shadow is drawn here instead, antialiased.
        panel.hasShadow = false
        shadowPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        for window in [panel, shadowPanel] as [NSPanel] {
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.canHide = false                    // survives NSApp.hide (PickListWindow)
            window.hasShadow = false
            window.backgroundColor = .clear
            window.isOpaque = false
            // No fade: with the default behaviour orderOut took 260–490 ms
            // on commit (per-key timing on D's Mac, 2026-11-09).
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
        shadowPanel.ignoresMouseEvents = true
        shadowPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        let shadowHost = NSView()
        shadowHost.addSubview(shadow)
        shadowPanel.contentView = shadowHost
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)

        panel.contentView = host

        // Clicks are handled at the window level, as in Squirrel's
        // SquirrelPanel.sendEvent: the view's mouseDown never fired in the
        // input method process (D, 2026-11-09).
        panel.onMouseUp = { [weak self] pointInWindow in
            guard let self else { return }
            let p = self.row.convert(pointInWindow, from: nil)
            if let i = self.row.index(at: p) { self.onSelect?(i) }
        }
    }

    /// Expanded grid: `columns` per row, any number of rows.
    func showGrid(candidates: [Candidate], highlighted: Int, caretRect: NSRect, columns: Int) {
        show(candidates: candidates, highlighted: highlighted, caretRect: caretRect, columns: columns)
    }

    /// - Parameters:
    ///   - caretRect: caret line rectangle in screen coordinates.
    ///   - isNote: a mode note (中 / 英), not candidates: no number, no clicks.
    func show(candidates: [Candidate], highlighted: Int, caretRect: NSRect,
              hasPrevious: Bool = false, hasNext: Bool = false, columns: Int? = nil,
              isNote: Bool = false) {
        guard !candidates.isEmpty else { hide(); return }
        flashWork?.cancel()
        row.update(candidates: candidates, highlighted: highlighted,
                   hasPrevious: hasPrevious, hasNext: hasNext, columns: columns, isNote: isNote)
        // Clicks only make sense on real candidates (a single 联想 word is one).
        panel.ignoresMouseEvents = isNote
        let content = row.fittingSize
        let size = NSSize(width: content.width + padding.width * 2,
                          height: content.height + padding.height * 2)
        useBacking(wantedBacking())
        let bounds = NSRect(origin: .zero, size: size)
        backingView?.frame = bounds
        row.superview?.frame = bounds
        row.frame = NSRect(origin: NSPoint(x: padding.width, y: padding.height), size: content)
        updateOutline()
        let frame = NSRect(origin: origin(for: size, caret: caretRect), size: size)
        shadow.frame = NSRect(origin: NSPoint(x: shadowRoom, y: shadowRoom), size: size)
        shadowPanel.setFrame(frame.insetBy(dx: -shadowRoom, dy: -shadowRoom), display: true)
        shadowPanel.orderFrontRegardless()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// A short mode note next to the caret, e.g. 中 / 英 after a Shift tap.
    func flash(_ text: String, caretRect: NSRect) {
        show(candidates: [Candidate(text: text, comment: nil, label: "")], highlighted: -1, caretRect: caretRect,
             isNote: true)
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        shadowPanel.orderOut(nil)
    }

    // MARK: Surface

    private func wantedBacking() -> Backing {
        if Surface.Access.opaqueSurfaces { return .solid }
        if #available(macOS 26, *), !Self.forceLegacyMaterial { return .glass }
        return .material
    }

    /// Swaps the surface under the candidates. Runs only when the kind
    /// changes (first show, or an accessibility setting was switched).
    private func useBacking(_ wanted: Backing) {
        guard wanted != backing else { return }
        backing = wanted
        row.removeFromSuperview()
        backingView?.removeFromSuperview()
        let holder = NSView()
        holder.wantsLayer = true
        holder.addSubview(row)
        let view: NSView
        switch wanted {
        case .glass:
            guard #available(macOS 26, *) else { fallthrough }
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Surface.radiusMedium
            holder.layer?.cornerRadius = Surface.radiusMedium
            holder.layer?.cornerCurve = .continuous
            glass.contentView = holder
            view = glass
        case .material:
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Surface.maskImage(radius: Surface.radiusMedium)
            effect.addSubview(holder)
            view = effect
        case .solid:
            let solid = NSView()
            solid.addSubview(holder)
            view = solid
        }
        if wanted != .glass {
            view.wantsLayer = true
            view.layer?.cornerRadius = Surface.radiusMedium
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
        if wanted == .material { view.layer?.cornerCurve = .circular }   // same curve as the blur's mask
        host.addSubview(view)
        backingView = view
    }

    /// Glass brings its own rim. The others get a hairline, or a firm line
    /// for Increase Contrast. Layer colours do not follow the appearance
    /// by themselves, so they are set on every show.
    private func updateOutline() {
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            // Over glass or blur, a scrim under the text keeps it readable
            // whatever is behind the window.
            row.superview?.layer?.backgroundColor = backing == .solid ? nil : Surface.scrim.cgColor
            guard backing != .glass, let layer = backingView?.layer else { return }
            // One device pixel: half a point is half a pixel without Retina
            // scaling, which draws as a broken line.
            layer.borderWidth = Surface.Access.increaseContrast ? 1 : 1 / max(1, panel.backingScaleFactor)
            layer.borderColor = Surface.outline.cgColor
            layer.backgroundColor = backing == .solid ? Surface.solidFill.cgColor : nil
        }
    }

    /// Below the caret line; above it if there is no room; always on screen.
    private func origin(for size: NSSize, caret: NSRect) -> NSPoint {
        let caretPoint = NSPoint(x: caret.minX, y: caret.minY)
        let screen = NSScreen.screens.first { $0.frame.contains(caretPoint) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = caret.minX - padding.width
        var y = caret.minY - gapToCaret - size.height
        if y < visible.minY { y = caret.maxY + gapToCaret }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

/// The two soft shadow layers of Surface (14 % r20 y8 + 8 % r1.5 y0.5)
/// round the surface, cut out under it so nothing darkens the glass.
private final class SurfaceShadowView: NSView {
    private let layers = [CALayer(), CALayer()]
    private let cutout = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        let specs: [(Float, CGFloat, CGFloat)] = [(0.14, 20, -8), (0.08, 1.5, -0.5)]
        for (shadow, spec) in zip(layers, specs) {
            shadow.shadowColor = NSColor.black.cgColor
            shadow.shadowOpacity = spec.0
            shadow.shadowRadius = spec.1
            shadow.shadowOffset = CGSize(width: 0, height: spec.2)
            layer?.addSublayer(shadow)
        }
        cutout.fillRule = .evenOdd
        layer?.mask = cutout
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shape = CGPath(roundedRect: bounds, cornerWidth: Surface.radiusMedium,
                           cornerHeight: Surface.radiusMedium, transform: nil)
        for shadow in layers {
            shadow.frame = bounds
            shadow.shadowPath = shape
        }
        let outside = CGMutablePath()
        outside.addRect(bounds.insetBy(dx: -80, dy: -80))
        outside.addPath(shape)
        cutout.frame = bounds
        cutout.path = outside
        CATransaction.commit()
    }
}

/// Delivers mouse-up positions; the panel never becomes key.
private final class ClickablePanel: NSPanel {
    var onMouseUp: ((NSPoint) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseUp { onMouseUp?(event.locationInWindow) }
        super.sendEvent(event)
    }
}

/// Draws the candidates; flipped so layout runs left → right, top → bottom.
private final class CandidateRowView: NSView {
    private var items: [(text: NSAttributedString, rect: NSRect, highlighted: Bool)] = []
    /// Previous / next page arrows; a faint arrow means there is no such page.
    private var pageHint: (rect: NSRect, hasPrevious: Bool, hasNext: Bool)?
    private var contentSize = NSSize.zero

    private let itemPadding = NSSize(width: 7, height: 4)
    private let itemGap: CGFloat = 2
    private let arrowWidth: CGFloat = 12

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { contentSize }

    func index(at point: NSPoint) -> Int? {
        items.firstIndex { $0.rect.contains(point) }
    }

    func update(candidates: [Candidate], highlighted: Int, hasPrevious: Bool, hasNext: Bool,
                columns: Int? = nil, isNote: Bool = false) {
        items = []
        let isGrid = (columns ?? 0) > 0
        let texts = candidates.enumerated().map { i, c in
            Self.render(c, index: i, selected: i == highlighted, showNumber: !isNote && !isGrid,
                        maxLength: isGrid ? Self.gridTextLength : Self.rowTextLength)
        }
        if let columns, columns > 0 {
            // Grid: equal cells, sized to the widest candidate (texts are
            // cut shorter than in the row, so 5 columns of 常用语 still fit
            // on the screen).
            let sizes = texts.map { $0.size() }
            let cellW = ceil(sizes.map(\.width).max() ?? 0) + itemPadding.width * 2
            let cellH = ceil(sizes.map(\.height).max() ?? 0) + itemPadding.height * 2
            for (i, text) in texts.enumerated() {
                let rect = NSRect(x: CGFloat(i % columns) * (cellW + itemGap),
                                  y: CGFloat(i / columns) * (cellH + itemGap),
                                  width: cellW, height: cellH)
                items.append((text, rect, i == highlighted))
            }
            let rows = (texts.count + columns - 1) / columns
            let cols = min(columns, texts.count)
            pageHint = nil
            contentSize = NSSize(width: CGFloat(cols) * (cellW + itemGap) - itemGap,
                                 height: CGFloat(rows) * (cellH + itemGap) - itemGap)
            needsDisplay = true
            return
        }
        var x: CGFloat = 0
        var height: CGFloat = 0
        for (i, text) in texts.enumerated() {
            let s = text.size()
            let rect = NSRect(x: x, y: 0, width: ceil(s.width) + itemPadding.width * 2,
                              height: ceil(s.height) + itemPadding.height * 2)
            items.append((text, rect, i == highlighted))
            x = rect.maxX + itemGap
            height = max(height, rect.height)
        }
        x -= itemGap
        pageHint = nil
        if hasPrevious || hasNext {
            pageHint = (NSRect(x: x + 8, y: 0, width: arrowWidth * 2, height: height), hasPrevious, hasNext)
            x += 8 + arrowWidth * 2 + 2
        }
        contentSize = NSSize(width: x, height: height)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in items {
            if item.highlighted {
                Surface.selectionFill.setFill()
                NSBezierPath(roundedRect: item.rect, xRadius: 6, yRadius: 6).fill()
            }
            let s = item.text.size()
            item.text.draw(at: NSPoint(x: item.rect.minX + itemPadding.width,
                                       y: item.rect.midY - s.height / 2))
        }
        if let hint = pageHint {
            drawArrow(pointingLeft: true, enabled: hint.hasPrevious,
                      centre: NSPoint(x: hint.rect.minX + arrowWidth / 2, y: hint.rect.midY))
            drawArrow(pointingLeft: false, enabled: hint.hasNext,
                      centre: NSPoint(x: hint.rect.minX + arrowWidth * 1.5, y: hint.rect.midY))
        }
    }

    /// A chevron drawn as a path: the "‹ ›" glyphs are hairlines at 12 pt.
    private func drawArrow(pointingLeft: Bool, enabled: Bool, centre: NSPoint) {
        let w: CGFloat = 4, h: CGFloat = 4.5
        let tip = pointingLeft ? -w / 2 : w / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre.x - tip, y: centre.y - h))
        path.line(to: NSPoint(x: centre.x + tip, y: centre.y))
        path.line(to: NSPoint(x: centre.x - tip, y: centre.y + h))
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (enabled ? Surface.quietText : Surface.disabledText).setStroke()
        path.stroke()
    }

    /// Characters of a candidate's text shown before "…" (常用语 can be long).
    private static let rowTextLength = 40
    private static let gridTextLength = 12

    private static func render(_ c: Candidate, index: Int, selected: Bool, showNumber: Bool,
                               maxLength: Int) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let label = c.label ?? "\(index + 1)"
        if showNumber, !label.isEmpty {
            out.append(NSAttributedString(string: label + " ", attributes: [
                .font: Surface.numberFont,
                .foregroundColor: selected ? Surface.onSelection : Surface.quietText,
                .baselineOffset: 1,
            ]))
        }
        // One row: show line breaks of 常用语 as ⏎ (the real text is inserted).
        let display = c.text.replacingOccurrences(of: "\n", with: " ⏎ ")
        out.append(NSAttributedString(string: display.count > maxLength ? String(display.prefix(maxLength)) + "…" : display, attributes: [
            .font: selected ? Surface.textFontBold : Surface.textFont,
            .foregroundColor: selected ? Surface.onSelection : NSColor.labelColor,
        ]))
        if let comment = c.comment, !comment.isEmpty {
            out.append(NSAttributedString(string: " " + comment, attributes: [
                .font: Surface.secondaryFont,
                .foregroundColor: selected ? Surface.onSelection : Surface.quietText,
                .baselineOffset: 1,
            ]))
        }
        return out
    }
}
