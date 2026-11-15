//
//  LyceumAudienceWindowManager.swift
//  leanring-buddy
//
//  The room window: a Meet-shaped NSPanel that sits opposite the written verdict
//  panel. Same rules as the coach panel — it must never take keyboard focus away
//  from the deck app, it joins every Space, and it rides above full-screen apps —
//  plus one that differs: it is resizable and remembers the frame you left it at,
//  because a 5-tile grid at 1.5 metres from a projector is a different size than a
//  5-tile grid on a laptop.
//

import AppKit
import SwiftUI

@MainActor
final class LyceumAudienceWindowManager {
    private static let defaultWidth: CGFloat = 600
    private static let defaultHeight: CGFloat = 420
    private static let minimumWidth: CGFloat = 420
    private static let minimumHeight: CGFloat = 300
    private static let bottomMargin: CGFloat = 24
    private static let leadingMargin: CGFloat = 24

    private static let frameDefaultsKey = "lyceumAudienceWindowFrame"

    private var panel: NSPanel?
    private var currentAudience: LyceumAudienceManager?
    private var hasPlacedPanelOnce = false

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(audience: LyceumAudienceManager, coach: LyceumCoachManager) {
        if currentAudience !== audience || panel == nil {
            currentAudience = audience
            buildPanel(with: audience, coach: coach)
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        rememberFrame()
        panel?.orderOut(nil)
    }

    func toggle(audience: LyceumAudienceManager, coach: LyceumCoachManager) {
        if isVisible {
            hide()
        } else {
            show(audience: audience, coach: coach)
        }
    }

    // MARK: - Panel

    private func buildPanel(with audience: LyceumAudienceManager, coach: LyceumCoachManager) {
        panel?.orderOut(nil)

        let roomView = LyceumAudiencePanelView(audience: audience, coach: coach) { [weak self] in
            Task { @MainActor in
                self?.hide()
            }
        }
        .frame(minWidth: Self.minimumWidth, maxWidth: .infinity, minHeight: Self.minimumHeight, maxHeight: .infinity)
        .lyceumColorScheme()

        let hostingView = NSHostingView(rootView: AnyView(roomView))
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.defaultWidth, height: Self.defaultHeight)
        hostingView.autoresizingMask = [.width, .height]

        let newPanel = NonActivatingPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = true
        newPanel.backgroundColor = NSColor(white: 0.062, alpha: 1)
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        newPanel.isExcludedFromWindowsMenu = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.contentMinSize = NSSize(width: Self.minimumWidth, height: Self.minimumHeight)
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.contentView = hostingView

        self.panel = newPanel
    }

    /// Restores the last frame the user chose. Otherwise the room opens on the left
    /// edge, leaving the right edge to the written verdict panel.
    private func positionPanel() {
        guard let panel else { return }

        if hasPlacedPanelOnce, let savedFrame = savedFrame(),
           NSScreen.screens.contains(where: { $0.frame.intersects(savedFrame) }) {
            panel.setFrame(savedFrame, display: true)
            return
        }

        let targetScreen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            panel.setContentSize(NSSize(width: Self.defaultWidth, height: Self.defaultHeight))
            return
        }

        let visibleFrame = screen.visibleFrame
        let width = min(Self.defaultWidth, visibleFrame.width - 2 * Self.leadingMargin)
        let height = min(Self.defaultHeight, visibleFrame.height - 2 * Self.bottomMargin)
        let origin = NSPoint(
            x: visibleFrame.minX + Self.leadingMargin,
            y: visibleFrame.minY + Self.bottomMargin
        )

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        hasPlacedPanelOnce = true
    }

    private func savedFrame() -> NSRect? {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.frameDefaultsKey),
              let string = stored["frame"] as? String else { return nil }
        let rect = NSRectFromString(string)
        guard rect.width >= Self.minimumWidth, rect.height >= Self.minimumHeight else { return nil }
        return rect
    }

    private func rememberFrame() {
        guard let panel else { return }
        UserDefaults.standard.set(["frame": NSStringFromRect(panel.frame)], forKey: Self.frameDefaultsKey)
    }

    /// Key is allowed because the roster popover contains text fields. Activation
    /// is still refused, so the deck app keeps the keyboard while nobody is typing.
    private final class NonActivatingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}
