// ergou-ime — candidate window (M1 T1.3).
// SPDX-License-Identifier: GPL-3.0-only
//
// A borderless, non-activating panel below the caret, one row:
//
//    ╭──────────────────────────────────────────────╮
//    │ ▕1 世▏  2 按 rpv · rpvg   3 俺 wdjn      ‹ ›  │
//    ╰──────────────────────────────────────────────╯
//
// The highlighted candidate sits on a soft accent-tinted rounded block;
// numbers and comments are quieter. Down arrow expands the row into a grid
// of more candidates (like other Chinese input methods); click any
// candidate to pick it. Styling comes from Surface.swift (shared with the
// voice HUD). No animation: the window must keep up with typing.

import AppKit

final class CandidatePanel {
    static let shared = CandidatePanel()

    /// Called with the index on the current page when a candidate is clicked.
    var onSelect: ((Int) -> Void)?

    private let panel: ClickablePanel
    private let background = NSVisualEffectView()
    private let row = CandidateRowView()
    private var flashWork: DispatchWorkItem?

    private let padding = NSSize(width: 6, height: 5)
    private let gapToCaret: CGFloat = 4

    private init() {
        panel = ClickablePanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.canHide = false                         // survives NSApp.hide (PickListWindow)
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // No fade: with the default behaviour orderOut took 260–490 ms on
        // commit (per-key timing on D's Mac, 2026-11-09).
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Surface.maskImage(radius: Surface.radiusMedium)
        background.wantsLayer = true
        background.layer?.cornerRadius = Surface.radiusMedium
        background.layer?.cornerCurve = .continuous
        background.layer?.borderWidth = 0.5
        background.addSubview(row)
        panel.contentView = background

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
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        let content = row.fittingSize
        let size = NSSize(width: content.width + padding.width * 2,
                          height: content.height + padding.height * 2)
        row.frame = NSRect(origin: NSPoint(x: padding.width, y: padding.height), size: content)
        panel.setFrame(NSRect(origin: origin(for: size, caret: caretRect), size: size), display: true)
        panel.invalidateShadow()
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
    private var pageHint: (text: NSAttributedString, rect: NSRect)?
    private var contentSize = NSSize.zero

    private let itemPadding = NSSize(width: 7, height: 4)
    private let itemGap: CGFloat = 2

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
            let hint = NSMutableAttributedString()
            for (glyph, on) in [("‹", hasPrevious), (" ›", hasNext)] {
                hint.append(NSAttributedString(string: glyph, attributes: [
                    .font: Surface.secondaryFont,
                    .foregroundColor: on ? NSColor.secondaryLabelColor : NSColor.quaternaryLabelColor,
                ]))
            }
            let s = hint.size()
            pageHint = (hint, NSRect(x: x + 10, y: 0, width: ceil(s.width) + 4, height: height))
            x += 10 + ceil(s.width) + 4
        }
        contentSize = NSSize(width: x, height: height)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in items {
            if item.highlighted {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: item.rect, xRadius: 6, yRadius: 6).fill()
            }
            let s = item.text.size()
            item.text.draw(at: NSPoint(x: item.rect.minX + itemPadding.width,
                                       y: item.rect.midY - s.height / 2))
        }
        if let hint = pageHint {
            let s = hint.text.size()
            hint.text.draw(at: NSPoint(x: hint.rect.minX + 2, y: hint.rect.midY - s.height / 2))
        }
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
                .font: Surface.numberFont, .foregroundColor: NSColor.tertiaryLabelColor,
                .baselineOffset: 1,
            ]))
        }
        // One row: show line breaks of 常用语 as ⏎ (the real text is inserted).
        let display = c.text.replacingOccurrences(of: "\n", with: " ⏎ ")
        out.append(NSAttributedString(string: display.count > maxLength ? String(display.prefix(maxLength)) + "…" : display, attributes: [
            .font: selected ? Surface.textFontBold : Surface.textFont,
            .foregroundColor: NSColor.labelColor,
        ]))
        if let comment = c.comment, !comment.isEmpty {
            out.append(NSAttributedString(string: " " + comment, attributes: [
                .font: Surface.secondaryFont, .foregroundColor: NSColor.tertiaryLabelColor,
                .baselineOffset: 1,
            ]))
        }
        return out
    }
}
