// ergou-ime — candidate window (M1 T1.3).
// SPDX-License-Identifier: GPL-3.0-only
//
// A borderless, non-activating panel below the caret, one row:
//
//    ╭──────────────────────────────────────────────╮
//    │ ▕1 世▏  2 按 rpv · rpvg   3 俺 wdjn      ‹ ›  │
//    ╰──────────────────────────────────────────────╯
//
// Down arrow expands the row into a grid of more candidates (like other
// Chinese input methods); click any candidate to pick it. With 竖排
// (设置 › 外观) the candidates are one under another and Down moves to the
// next one instead. What is drawn,
// and how it looks, is in PanelSurface.swift and Surface.swift; the look
// follows 设置 › 外观 (PanelStyle). No animation: the window must keep up
// with typing.

import AppKit

final class CandidatePanel {
    static let shared = CandidatePanel()

    /// Called with the index on the current page when a candidate is clicked.
    var onSelect: ((Int) -> Void)?
    /// Called when a page arrow is clicked: true = next page, false = previous.
    var onPage: ((Bool) -> Void)?

    private let panel: ClickablePanel
    private let surface = PanelSurfaceView()
    private var row: CandidateRowView { surface.row }
    private var flashWork: DispatchWorkItem?

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

        let host = NSView()
        host.addSubview(surface)
        panel.contentView = host

        // Clicks are handled at the window level, as in Squirrel's
        // SquirrelPanel.sendEvent: the view's mouseDown never fired in the
        // input method process (D, 2026-11-09).
        panel.onMouseUp = { [weak self] pointInWindow in
            guard let self else { return }
            let p = self.row.convert(pointInWindow, from: nil)
            if let i = self.row.index(at: p) {
                self.onSelect?(i)
            } else if let next = self.row.pageArrow(at: p) {
                self.onPage?(next)        // the ‹ › arrows only drew, clicks did nothing (D, 2026-11-12)
            }
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
        let style = PanelStyle.current
        let size = surface.update(candidates: candidates, highlighted: highlighted, hasPrevious: hasPrevious,
                                  hasNext: hasNext, columns: columns, isNote: isNote, style: style)
        surface.frame = NSRect(origin: .zero, size: size)
        // Clicks only make sense on real candidates (a single 联想 word is one).
        panel.ignoresMouseEvents = isNote
        shadow.radius = style.cornerRadius
        let frame = NSRect(origin: origin(for: size, caret: caretRect, inset: style.panelPadding.width), size: size)
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

    /// Below the caret line; above it if there is no room; always on screen.
    private func origin(for size: NSSize, caret: NSRect, inset: CGFloat) -> NSPoint {
        let caretPoint = NSPoint(x: caret.minX, y: caret.minY)
        let screen = NSScreen.screens.first { $0.frame.contains(caretPoint) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = caret.minX - inset
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
