//
//  LyceumCoachWindowManager.swift
//  leanring-buddy
//
//  The floating NSPanel that hosts LyceumCoachPanelView.
//
//  Deliberately different from the menu bar dropdown: it stays open while you
//  present, it must not steal keyboard focus from Keynote/PowerPoint, and it parks
//  itself in the bottom-right corner so the slide stays readable. It joins all Spaces
//  and rides above full-screen apps, which is the whole point of a rehearsal coach.
//

import AppKit
import SwiftUI

@MainActor
final class LyceumCoachWindowManager {
    private static let panelWidth: CGFloat = 460
    private static let panelMinimumHeight: CGFloat = 320
    private static let panelMaximumHeight: CGFloat = 620
    private static let trailingMargin: CGFloat = 24
    private static let bottomMargin: CGFloat = 24

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var currentManager: LyceumCoachManager?
    private var hasPlacedPanelOnce = false

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(manager: LyceumCoachManager) {
        if currentManager !== manager || panel == nil {
            currentManager = manager
            buildPanel(with: manager)
        }

        positionPanel()

        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle(manager: LyceumCoachManager) {
        if isVisible {
            hide()
        } else {
            show(manager: manager)
        }
    }

    // MARK: - Panel

    private func buildPanel(with manager: LyceumCoachManager) {
        panel?.orderOut(nil)

        let coachPanelView = LyceumCoachPanelView(coachManager: manager)
            .frame(width: Self.panelWidth)
            .lyceumColorScheme()

        let hostingView = NSHostingView(rootView: AnyView(coachPanelView))
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Self.panelWidth,
            height: Self.panelMinimumHeight
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let newPanel = NonActivatingPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.isExcludedFromWindowsMenu = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.contentView = hostingView

        self.hostingView = hostingView
        self.panel = newPanel
    }

    /// Sizes the panel to the SwiftUI content, clamped, and keeps it anchored to the
    /// bottom-right of the screen it is currently on.
    private func positionPanel() {
        guard let panel, let hostingView else { return }

        hostingView.frame.size = hostingView.fittingSize

        let contentHeight = hostingView.fittingSize.height
        let clampedHeight = min(max(contentHeight, Self.panelMinimumHeight), Self.panelMaximumHeight)

        var targetFrame = NSRect(
            x: 0,
            y: 0,
            width: Self.panelWidth,
            height: clampedHeight
        )

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            panel.setContentSize(targetFrame.size)
            return
        }

        let visibleFrame = screen.visibleFrame
        targetFrame.origin.x = visibleFrame.maxX - Self.panelWidth - Self.trailingMargin
        targetFrame.origin.y = visibleFrame.minY + Self.bottomMargin

        // Respect a panel the user has dragged somewhere they like, unless it has
        // fallen off the visible screen (disconnected monitor).
        if hasPlacedPanelOnce, visibleFrame.intersects(panel.frame) {
            targetFrame.origin = panel.frame.origin
        }

        panel.setFrame(targetFrame, display: true)
        hasPlacedPanelOnce = true
    }

    /// Borderless panels cannot become key by default, which is what keeps focus in
    /// the user's deck app. The topic field still needs typing, so allow key here.
    private final class NonActivatingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}
