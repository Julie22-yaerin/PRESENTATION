//
//  LyceumDashboardWindowManager.swift
//  leanring-buddy
//
//  The one window in this app that is a normal window: titled, closable,
//  minimisable, and willing to take keyboard focus. The panels deliberately are
//  not, because they have to sit over someone else's presentation without
//  stealing it. A dashboard is a place you go on purpose, so it behaves like a
//  window and not like an overlay.
//
//  The catch is that this app is LSUIElement: it has no Dock icon and runs as an
//  accessory. A window that can be typed into needs the regular activation policy
//  while it is open, so the manager borrows it on show and hands it back on close.
//

import AppKit
import SwiftUI

@MainActor
final class LyceumDashboardWindowManager {
    private static let minimumSize = NSSize(width: 940, height: 620)
    private static let defaultSize = NSSize(width: 1180, height: 760)
    private static let frameDefaultsKey = "lyceumDashboardWindowFrame"

    private var window: NSWindow?
    /// Set only when this manager is the reason the app became a regular app, so a
    /// close never changes the policy the user or another window needed.
    private var didBorrowActivationPolicy = false
    private let closeWatcher = LyceumWindowCloseWatcher()

    var isVisible: Bool { window?.isVisible == true }

    func show(coach: LyceumCoachManager,
              audience: LyceumAudienceManager,
              gate: LyceumAppGate,
              companion: CompanionManager) {
        borrowActivationPolicyIfNeeded()

        if let window {
            coach.reloadRecentSessions()
            window.title = "The Lyceum — dashboard"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = LyceumDashboardView(
            coach: coach,
            audience: audience,
            gate: gate,
            companion: companion,
            onClose: { [weak self] in
                Task { @MainActor in self?.close() }
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.setFrameSize(designatedFrameSize: Self.defaultSize)

        let created = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        created.title = "The Lyceum — dashboard"
        created.titlebarAppearsTransparent = false
        created.contentView = hosting
        created.isReleasedWhenClosed = false
        created.minSize = Self.minimumSize
        created.tabbingMode = .disallowed
        created.center()
        restoreFrame(into: created)

        closeWatcher.onClose = { [weak self] in
            Task { @MainActor in self?.releaseActivationPolicy() }
        }
        created.delegate = closeWatcher

        window = created
        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle(coach: LyceumCoachManager,
                audience: LyceumAudienceManager,
                gate: LyceumAppGate,
                companion: CompanionManager) {
        if isVisible {
            close()
        } else {
            show(coach: coach, audience: audience, gate: gate, companion: companion)
        }
    }

    func close() {
        guard let window else { return }
        rememberFrame(of: window)
        window.orderOut(nil)
        window.delegate = nil
        window = nil
        closeWatcher.onClose = nil
        releaseActivationPolicy()
    }

    // MARK: - Accessory app

    private func borrowActivationPolicyIfNeeded() {
        guard !didBorrowActivationPolicy else { return }
        guard NSApp.activationPolicy() == .accessory else {
            // Something else already made this a normal app. Do not take it away on
            // our close.
            return
        }
        NSApp.setActivationPolicy(.regular)
        didBorrowActivationPolicy = true
    }

    private func releaseActivationPolicy() {
        guard didBorrowActivationPolicy else { return }
        didBorrowActivationPolicy = false
        // This app is LSUIElement: the dashboard was the only thing asking for a
        // Dock icon, so the icon goes back the moment its window closes.
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Frame memory

    private func restoreFrame(into window: NSWindow) {
        guard let stored = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) else { return }
        let candidate = NSCoder.rect(for: stored)
        guard candidate.width >= Self.minimumSize.width, candidate.height >= Self.minimumSize.height else { return }
        // A frame remembered from a monitor that is no longer plugged in would open
        // the dashboard off screen with nothing left to click on.
        guard NSScreen.screens.contains(where: { screen in screen.visibleFrame.intersects(candidate) }) else { return }
        window.setFrame(candidate, display: false)
    }

    private func rememberFrame(of window: NSWindow) {
        UserDefaults.standard.set(NSCoder.string(for: window.frame), forKey: Self.frameDefaultsKey)
    }
}

/// NSWindow.delegate is weak, so somebody has to own it for the lifetime of the
/// window. A one-purpose object is cheaper than reasoning about which manager
/// should also become a window delegate.
final class LyceumWindowCloseWatcher: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
