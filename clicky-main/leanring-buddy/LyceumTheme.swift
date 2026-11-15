//
//  LyceumTheme.swift
//  leanring-buddy
//
//  One place that decides whether the app looks light or dark, and whether it
//  moves too much. Until now the dashboard hard-coded `.dark` and every other
//  window followed whatever macOS felt like; this is the switch that was
//  supposed to exist before there were three windows to agree about.
//
//  The rule for views: never write `.environment(\.colorScheme, .dark)` again.
//  Read `LyceumAppearanceController.shared` and apply it through
//  `lyceumColorScheme(_:)`, which leaves the environment untouched when the
//  user chose System.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Mode

enum LyceumAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: LyceumAppearanceMode { self }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }

    /// The one line under the button row in settings.
    var brief: String {
        switch self {
        case .system: return "Follow whatever macOS is set to."
        case .light: return "Pin the app to light, sheets and panels included."
        case .dark: return "Pin the app to dark, the way the palette was drawn."
        }
    }
}

// MARK: - Controller

@MainActor
final class LyceumAppearanceController: ObservableObject {
    static let shared = LyceumAppearanceController()

    static let modeDefaultsKey = "lyceumAppearanceMode"
    static let reduceMotionDefaultsKey = "lyceumReduceMotion"

    /// Persisted choice. The default is `.dark`, not `.system`, on purpose: the
    /// design system palette is dark-tokened and the dashboard used to force
    /// `.dark`, so an install that never opens this settings sheet keeps
    /// looking exactly the way it did the day before this file existed.
    @Published var mode: LyceumAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeDefaultsKey)
            apply()
        }
    }

    /// An app-level "hold your motion" switch on top of the macOS accessibility
    /// one. Views that animate should check this and fall back to a plain
    /// transition; the settings sheet offers it because not everyone reaches
    /// System Settings for reduce-motion.
    @Published var reduceMotion: Bool {
        didSet {
            UserDefaults.standard.set(reduceMotion, forKey: Self.reduceMotionDefaultsKey)
        }
    }

    private init() {
        let storedRaw = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
        mode = LyceumAppearanceMode(rawValue: storedRaw ?? "") ?? .dark

        if UserDefaults.standard.object(forKey: Self.reduceMotionDefaultsKey) == nil {
            #if os(macOS)
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #else
            reduceMotion = false
            #endif
        } else {
            reduceMotion = UserDefaults.standard.bool(forKey: Self.reduceMotionDefaultsKey)
        }
    }

    /// What a view should put into `\.colorScheme`. nil means "no override":
    /// the window follows the system (or the app appearance `apply()` set).
    /// Callers must route this through `lyceumColorScheme(_:)` rather than
    /// forcing nil into the environment key, which wants a real scheme.
    var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Sets `NSApp.appearance`, which is what native controls inside sheets,
    /// save panels and hosting views actually obey. Called from the app
    /// delegate / window manager at launch and again after every mode change,
    /// so a user who picks System gets their real system appearance back.
    func apply() {
        #if os(macOS)
        guard let application = NSApp else { return }
        switch mode {
        case .system:
            application.appearance = nil
        case .light:
            application.appearance = NSAppearance(named: .aqua)
        case .dark:
            application.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }
}

// MARK: - View plumbing

extension View {
    /// Applies the appearance controller's scheme when there is one, and no
    /// override at all when the user chose System. This is the only sanctioned
    /// way to colour-scheme a Lyceum view.
    @ViewBuilder
    func lyceumColorScheme(_ override: ColorScheme?) -> some View {
        if let override {
            self.environment(\.colorScheme, override)
        } else {
            self
        }
    }
    /// Follows the controller from then on. Panels are hosted by an `NSHostingView`
    /// built once and left on screen, so a call site that reads `colorScheme` when the
    /// window is created freezes the theme until the app restarts; this version keeps a
    /// live subscription and repaints the moment the dial in Settings moves.
    func lyceumColorScheme() -> some View {
        modifier(LyceumAppearanceModifier())
    }
}
private struct LyceumAppearanceModifier: ViewModifier {
    @ObservedObject private var appearance = LyceumAppearanceController.shared
    func body(content: Content) -> some View {
        content.lyceumColorScheme(appearance.colorScheme)
    }
}
