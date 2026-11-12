// ergou-ime — the candidate window's surface and its contents.
// SPDX-License-Identifier: GPL-3.0-only
//
// Everything that is drawn, without the window: CandidatePanel puts it in
// the floating panel, and Settings shows the same view as the sample on
// 设置 › 外观 (this file and Surface.swift are in both targets).
//
// Surface: Liquid Glass on macOS 26 and later, the popover material before
// that, and an opaque fill with a firm outline for the 实底 look and when
// Reduce Transparency or Increase Contrast is on.

import AppKit

/// The rounded surface with the row of candidates on it. Its owner sets
/// its frame to the size `update` returns.
final class PanelSurfaceView: NSView {
    let row = CandidateRowView()
    /// True for the sample in Settings: blur what is behind this view in
    /// the same window, not what is behind the window.
    var blendsWithinWindow = false

    private enum Backing: Equatable { case glass, material, solid }
    private var backing: (kind: Backing, radius: CGFloat)?
    private var backingView: NSView?
    private var style = PanelStyle()

    /// Lays out the candidates and returns the size the surface needs.
    func update(candidates: [Candidate], highlighted: Int, hasPrevious: Bool = false, hasNext: Bool = false,
                columns: Int? = nil, isNote: Bool = false, style: PanelStyle) -> NSSize {
        self.style = style
        row.update(candidates: candidates, highlighted: highlighted, hasPrevious: hasPrevious,
                   hasNext: hasNext, columns: columns, isNote: isNote, style: style)
        let content = row.fittingSize
        let padding = style.panelPadding
        let size = NSSize(width: content.width + padding.width * 2, height: content.height + padding.height * 2)
        useBacking(wantedBacking(), radius: style.cornerRadius)
        let bounds = NSRect(origin: .zero, size: size)
        backingView?.frame = bounds
        row.superview?.frame = bounds
        row.frame = NSRect(origin: NSPoint(x: padding.width, y: padding.height), size: content)
        updateColours()
        return size
    }

    private func wantedBacking() -> Backing {
        if Surface.Access.opaqueSurfaces || style.look == .solid { return .solid }
        if #available(macOS 26, *), !Surface.forceLegacyMaterial { return .glass }
        return .material
    }

    /// Swaps the surface under the candidates. Runs only when the kind or
    /// the corner changes (first show, a setting was changed).
    private func useBacking(_ wanted: Backing, radius: CGFloat) {
        if let backing, backing.kind == wanted, backing.radius == radius { return }
        backing = (wanted, radius)
        row.removeFromSuperview()
        backingView?.removeFromSuperview()
        let holder = NSView()
        holder.wantsLayer = true
        holder.addSubview(row)
        let view: NSView
        if wanted == .glass, #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            holder.layer?.cornerRadius = radius
            holder.layer?.cornerCurve = .continuous
            glass.contentView = holder
            view = glass
        } else {
            if wanted == .solid {
                view = NSView()
            } else {
                let effect = NSVisualEffectView()
                effect.material = .popover
                effect.blendingMode = blendsWithinWindow ? .withinWindow : .behindWindow
                effect.state = .active
                effect.maskImage = Surface.maskImage(radius: radius)
                view = effect
            }
            view.addSubview(holder)
            view.wantsLayer = true
            view.layer?.cornerRadius = radius
            // The blur's mask has circular corners; the outline must follow it.
            view.layer?.cornerCurve = wanted == .solid ? .continuous : .circular
            view.layer?.masksToBounds = true
        }
        addSubview(view)
        backingView = view
    }

    /// Glass brings its own rim. The others get a hairline, or a firm line
    /// for Increase Contrast. Layer colours do not follow the appearance
    /// by themselves, so they are set on every update.
    private func updateColours() {
        let kind = backing?.kind
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // Over glass or blur, a scrim under the text keeps it readable
            // whatever is behind the window.
            row.superview?.layer?.backgroundColor = kind == .solid ? nil : Surface.scrim.cgColor
            guard kind != .glass, let layer = backingView?.layer else { return }
            // One device pixel: half a point is half a pixel without Retina
            // scaling, which draws as a broken line.
            let scale = window?.backingScaleFactor ?? 2
            layer.borderWidth = Surface.Access.increaseContrast ? 1 : 1 / max(1, scale)
            layer.borderColor = Surface.outline.cgColor
            layer.backgroundColor = kind == .solid ? Surface.solidFill.cgColor : nil
        }
    }
}

/// The two soft shadow layers of Surface (14 % r20 y8 + 8 % r1.5 y0.5)
/// round the surface, cut out under it so nothing darkens the glass.
final class SurfaceShadowView: NSView {
    var radius = Surface.radiusMedium { didSet { if radius != oldValue { needsLayout = true } } }
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
        let r = min(radius, bounds.width / 2, bounds.height / 2)
        let shape = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)
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

/// Draws the candidates; flipped so layout runs left → right, top → bottom.
final class CandidateRowView: NSView {
    private var items: [(text: NSAttributedString, rect: NSRect, highlighted: Bool)] = []
    /// Previous / next page arrows; a faint arrow means there is no such page.
    private var pageHint: (rect: NSRect, hasPrevious: Bool, hasNext: Bool)?
    private var contentSize = NSSize.zero

    private var style = PanelStyle()
    private var itemPadding: NSSize { style.itemPadding }
    private var itemGap: CGFloat { style.itemGap }
    private let arrowWidth: CGFloat = 12

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { contentSize }

    func index(at point: NSPoint) -> Int? {
        items.firstIndex { $0.rect.contains(point) }
    }

    /// The page arrow under `point`: false = ‹ (previous), true = › (next);
    /// nil for none, or for a faint arrow (no such page). Each arrow takes
    /// half of the hint, the full row height, and 4 pt more on its outer
    /// side: the chevrons are only 4 pt wide. (竖排: the arrows have a line
    /// of their own under the candidates.)
    func pageArrow(at point: NSPoint) -> Bool? {
        guard let hint = pageHint, point.y >= hint.rect.minY, point.y <= hint.rect.maxY else { return nil }
        let previous = (hint.rect.minX - 4)..<(hint.rect.minX + arrowWidth)
        let next = (hint.rect.minX + arrowWidth)...(hint.rect.maxX + 4)
        if previous.contains(point.x) { return hint.hasPrevious ? false : nil }
        if next.contains(point.x) { return hint.hasNext ? true : nil }
        return nil
    }

    func update(candidates: [Candidate], highlighted: Int, hasPrevious: Bool, hasNext: Bool,
                columns: Int? = nil, isNote: Bool = false, style: PanelStyle) {
        self.style = style
        items = []
        let isGrid = (columns ?? 0) > 0
        let texts = candidates.enumerated().map { i, c in
            Self.render(c, index: i, selected: i == highlighted, showNumber: !isNote && !isGrid,
                        maxLength: isGrid ? Self.gridTextLength : Self.rowTextLength, style: style)
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
        if style.layout == .vertical {
            // 竖排: one candidate per line, all as wide as the widest, so
            // the block behind the chosen one does not jump in width.
            let sizes = texts.map { $0.size() }
            var width = ceil(sizes.map(\.width).max() ?? 0) + itemPadding.width * 2
            let showArrows = hasPrevious || hasNext
            if showArrows { width = max(width, arrowWidth * 2 + 8) }
            var y: CGFloat = 0
            for (i, text) in texts.enumerated() {
                let rect = NSRect(x: 0, y: y, width: width, height: ceil(sizes[i].height) + itemPadding.height * 2)
                items.append((text, rect, i == highlighted))
                y = rect.maxY + itemGap
            }
            y -= itemGap
            pageHint = nil
            if showArrows {
                // Under the last candidate, at the right edge.
                let arrowHeight = max(16, style.secondarySize + 6)
                pageHint = (NSRect(x: width - arrowWidth * 2 - 4, y: y + 2, width: arrowWidth * 2, height: arrowHeight),
                            hasPrevious, hasNext)
                y += 2 + arrowHeight
            }
            contentSize = NSSize(width: width, height: y)
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
                Surface.selection(style.accent).fill.setFill()
                NSBezierPath(roundedRect: item.rect, xRadius: style.chosenRadius, yRadius: style.chosenRadius).fill()
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
                               maxLength: Int, style: PanelStyle) -> NSAttributedString {
        let size = CGFloat(style.fontSize)
        let onChosen = Surface.selection(style.accent).text
        // Lifts the smaller text so it sits on the line of the larger.
        let lift = (size / 16).rounded()
        let out = NSMutableAttributedString()
        let label = c.label ?? "\(index + 1)"
        if showNumber, !label.isEmpty {
            out.append(NSAttributedString(string: label + " ", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: style.secondarySize, weight: .medium),
                .foregroundColor: selected ? onChosen : Surface.quietText,
                .baselineOffset: lift,
            ]))
        }
        // One row: show line breaks of 常用语 as ⏎ (the real text is inserted).
        let display = c.text.replacingOccurrences(of: "\n", with: " ⏎ ")
        out.append(NSAttributedString(string: display.count > maxLength ? String(display.prefix(maxLength)) + "…" : display, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: selected ? .semibold : .regular),
            .foregroundColor: selected ? onChosen : NSColor.labelColor,
        ]))
        if let comment = c.comment, !comment.isEmpty {
            out.append(NSAttributedString(string: " " + comment, attributes: [
                .font: NSFont.systemFont(ofSize: style.secondarySize),
                .foregroundColor: selected ? onChosen : Surface.quietText,
                .baselineOffset: lift,
            ]))
        }
        return out
    }
}
