//
//  LyceumAppGate.swift
//  leanring-buddy
//
//  The Lyceum is a rehearsal coach for presentations, so a practice run only makes
//  sense while a slide tool is in front of you. This gate is what enforces that,
//  in the same spirit as assistants that only wake up inside a meeting app.
//
//  Native apps (Keynote, PowerPoint, Impress) are identified by bundle id and are
//  therefore exact. Web tools (Google Slides, Canva, Gamma, Pitch, Prezi) live
//  inside a browser, and a sandboxed app cannot read the page — the only legal
//  signal is the window title, which CoreGraphics exposes as kCGWindowName once
//  Screen Recording is granted (this app needs that permission anyway). A Canva
//  tab is titled "Quarterly review – Canva", so decks match and posters, which
//  the user explicitly does not want coached, are recognised by their own nouns.
//
//  Everything here is a heuristic with an escape hatch: the panel can whitelist the
//  app you are actually in, and enforcement can be switched off entirely.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

extension Notification.Name {
    /// Posted by The Lyceum when it needs to say something briefly over the cursor
    /// overlay (a refused start, an automatic end). The object is the message string.
    static let lyceumNeedsAttention = Notification.Name("lyceumNeedsAttention")
    /// Posted when something wants the dashboard window opened. The dashboard needs
    /// CompanionManager, which owns the coach, so the request travels by notification
    /// rather than by another reference held sideways.
    static let lyceumOpenDashboard = Notification.Name("lyceumOpenDashboard")
}

// MARK: - What counts as a slide tool

enum LyceumSlideTool: String, CaseIterable, Codable {
    case keynote
    case powerpoint
    case googleSlides
    case canva
    case libreOfficeImpress
    case gamma
    case pitch
    case slidesCom
    case prezi
    case unknownSlideTool

    var displayName: String {
        switch self {
        case .keynote: return "Keynote"
        case .powerpoint: return "PowerPoint"
        case .googleSlides: return "Google Slides"
        case .canva: return "Canva"
        case .libreOfficeImpress: return "LibreOffice Impress"
        case .gamma: return "Gamma"
        case .pitch: return "Pitch"
        case .slidesCom: return "slides.com"
        case .prezi: return "Prezi"
        case .unknownSlideTool: return "a slide tool"
        }
    }

    var symbolName: String {
        switch self {
        case .keynote, .powerpoint, .libreOfficeImpress: return "rectangle.on.rectangle"
        case .googleSlides: return "doc.on.doc"
        case .canva: return "paintpalette"
        case .gamma, .pitch, .slidesCom, .prezi: return "play.rectangle"
        case .unknownSlideTool: return "questionmark.app"
        }
    }

    /// Tools that can only ever be seen through a browser window title.
    var isWebBased: Bool {
        switch self {
        case .googleSlides, .canva, .gamma, .pitch, .slidesCom, .prezi: return true
        default: return false
        }
    }
}

// MARK: - What is in front of the user right now

struct LyceumFrontmostApp: Equatable {
    let bundleID: String?
    let localizedName: String
    let windowTitle: String

    /// True when the frontmost process is a browser, which is the only reason the
    /// window title has to be interpreted instead of trusted as a document name.
    let isBrowser: Bool

    static let nothing = LyceumFrontmostApp(bundleID: nil, localizedName: "", windowTitle: "", isBrowser: false)

    /// True when nothing has been read yet, so the panel and the dashboard can
    /// disable "Allow this app" instead of letting a user whitelist an empty fact.
    var isNothing: Bool { localizedName.isEmpty && windowTitle.isEmpty && bundleID == nil }

    /// One line for the panel: "Canva · Quarterly review".
    var shortDescription: String {
        let namePart = localizedName.isEmpty ? "no app" : localizedName
        guard !windowTitle.isEmpty else { return namePart }
        let trimmedTitle = windowTitle.count > 48 ? String(windowTitle.prefix(48)) + "…" : windowTitle
        return "\(namePart) · \(trimmedTitle)"
    }
}

// MARK: - Decision

enum LyceumGateBlockReason: Equatable {
    /// Nothing to inspect (no frontmost app, or the app is this one).
    case nothingToCoach
    /// A browser tab that is clearly a non-slide design document.
    case designDocumentIsNotASlide(frontmost: LyceumFrontmostApp)
    /// Something we cannot recognise as a slide tool.
    case notASlideTool(frontmost: LyceumFrontmostApp)

    /// The window that caused the refusal, for the panel line that shows it.
    var frontmost: LyceumFrontmostApp {
        switch self {
        case .nothingToCoach: return .nothing
        case .designDocumentIsNotASlide(let frontmost): return frontmost
        case .notASlideTool(let frontmost): return frontmost
        }
    }

    var analyticsName: String {
        switch self {
        case .nothingToCoach: return "nothing"
        case .designDocumentIsNotASlide: return "design_document"
        case .notASlideTool: return "not_a_slide_tool"
        }
    }

    var userFacingMessage: String {
        switch self {
        case .nothingToCoach:
            return "The Lyceum needs a slide tool in front of you. Open Keynote, PowerPoint, Google Slides or Canva and tap again."
        case .designDocumentIsNotASlide(let frontmost):
            return "\(frontmost.localizedName) is showing a design document, not a deck. The Lyceum coaches presentations — posters and one-pagers are out of scope."
        case .notASlideTool(let frontmost):
            let what = frontmost.localizedName.isEmpty ? "this window" : frontmost.localizedName
            return "\(what) is not a slide tool. The Lyceum only starts inside Keynote, PowerPoint, Google Slides, Canva, Gamma, Pitch, Prezi or Impress."
        }
    }
}

enum LyceumGateDecision: Equatable {
    case allowed(tool: LyceumSlideTool, frontmost: LyceumFrontmostApp, viaWhitelist: Bool)
    case blocked(reason: LyceumGateBlockReason)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

// MARK: - The gate

@MainActor
final class LyceumAppGate: ObservableObject {
    /// Refreshed whenever a run is attempted and whenever the panel opens, so the
    /// user always sees why the app did or did not start.
    @Published private(set) var latestFrontmost: LyceumFrontmostApp = .nothing
    @Published private(set) var latestDecision: LyceumGateDecision = .blocked(reason: .nothingToCoach)

    /// Turning this off is a supported choice, not a bug: someone may rehearse in a
    /// tool this list has never heard of.
    @Published var enforcesSlideTool: Bool {
        didSet { UserDefaults.standard.set(enforcesSlideTool, forKey: Self.enforcementDefaultsKey) }
    }

    /// Bundle ids (or "browser|title keyword" pairs) the user added by hand.
    @Published private(set) var whitelistedIdentifiers: [String]

    private static let enforcementDefaultsKey = "lyceumEnforcesSlideTool"
    private static let whitelistDefaultsKey = "lyceumSlideToolWhitelist"

    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.ChromeDev",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Canary",
        "com.brave.Browser", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.vivaldi.Vivaldi", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"
    ]

    /// Tools recognised by bundle id alone. Exact, no title parsing involved.
    private static let nativeToolBundleIDs: [String: LyceumSlideTool] = [
        "com.apple.Keynote": .keynote,
        "com.microsoft.Powerpoint": .powerpoint,
        "com.apple.PresentationConverter": .keynote,
        "org.libreoffice.script": .libreOfficeImpress,
        "com.libreoffice.impress": .libreOfficeImpress,
        "com.canva.CanvaDesktop": .canva,
        "com.prezi.PreziDesktop": .prezi,
        "com.gamma.app": .gamma
    ]

    /// Title nouns that mean "this is a deck".
    private static let deckTitleKeywords: [String] = [
        "google slides", "slides", "slide deck", "slidedeck", "presentation", "deck",
        "bài thuyết trình", "trang trình chiếu", "präsi", "presentazione", "презентация",
        "プレゼン", "演示文稿", "発表", "slide", "pitch", "prezi", "keynote"
    ]

    /// Title nouns that mean "this is a different kind of document". The user asked
    /// for slide tools only, so a poster in Canva must not open a coaching run.
    private static let nonDeckDocumentKeywords: [String] = [
        "poster", "brochure", "flyer", "leaflet", "instagram", "linkedin post", "logo",
        "business card", "card", "invitation", "resume", "cv", "résumé", "banner",
        "thumbnail", "wallpaper", "sticker", "menu", "certificate", "wedding", "moodboard",
        "mockup", "wireframe", "whiteboard", "t-shirt", "book cover", "album cover",
        "tờ rơi", "ap phích", "name card", "thumbnail youtube"
    ]

    init() {
        self.enforcesSlideTool = UserDefaults.standard.object(forKey: Self.enforcementDefaultsKey) as? Bool ?? true
        self.whitelistedIdentifiers = UserDefaults.standard.stringArray(forKey: Self.whitelistDefaultsKey) ?? []
    }

    // MARK: - Entry points

    /// Reads the screen, decides, and publishes both for the UI. Call this at the
    /// moment of the hotkey tap, never from a timer: the answer has to describe the
    /// app the user was actually looking at when they pressed.
    func evaluateNow() -> LyceumGateDecision {
        let frontmost = Self.readFrontmostApp()
        latestFrontmost = frontmost

        let decision = decide(for: frontmost)
        latestDecision = decision
        return decision
    }

    private func decide(for frontmost: LyceumFrontmostApp) -> LyceumGateDecision {
        guard enforcesSlideTool else {
            return .allowed(tool: .unknownSlideTool, frontmost: frontmost, viaWhitelist: false)
        }

        guard !frontmost.localizedName.isEmpty else {
            return .blocked(reason: .nothingToCoach)
        }

        // The Lyceum's own panel being frontmost must not block its own run.
        if Self.isOwnProcess(frontmost) {
            return .allowed(tool: .unknownSlideTool, frontmost: frontmost, viaWhitelist: false)
        }

        if let identifier = Self.whitelistIdentifier(for: frontmost),
           whitelistedIdentifiers.contains(identifier) {
            return .allowed(tool: .unknownSlideTool, frontmost: frontmost, viaWhitelist: true)
        }

        if let tool = Self.matchNativeTool(for: frontmost) {
            return .allowed(tool: tool, frontmost: frontmost, viaWhitelist: false)
        }

        if frontmost.isBrowser {
            return Self.decideForBrowserTab(frontmost)
        }

        // Some tools report no bundle id we know but say so in the window title
        // ("Monthly deck — Slide Deck Maker"). Cheap catch-all before refusing.
        let loweredTitle = frontmost.windowTitle.lowercased()
        if Self.deckTitleKeywords.contains(where: { loweredTitle.contains($0) }),
           !Self.looksLikeNonDeckDocument(loweredTitle) {
            return .allowed(tool: .unknownSlideTool, frontmost: frontmost, viaWhitelist: false)
        }

        return .blocked(reason: .notASlideTool(frontmost: frontmost))
    }

    /// Adds whatever is in front of the user right now to the whitelist. This is the
    /// escape hatch for a slide tool the lists above have never seen.
    func whitelistCurrentApp() {
        let frontmost = Self.readFrontmostApp()
        latestFrontmost = frontmost
        guard let identifier = Self.whitelistIdentifier(for: frontmost) else { return }
        guard !whitelistedIdentifiers.contains(identifier) else { return }
        whitelistedIdentifiers.append(identifier)
        UserDefaults.standard.set(whitelistedIdentifiers, forKey: Self.whitelistDefaultsKey)
        latestDecision = .allowed(tool: .unknownSlideTool, frontmost: frontmost, viaWhitelist: true)
    }

    func removeWhitelistEntry(_ identifier: String) {
        whitelistedIdentifiers.removeAll { $0 == identifier }
        UserDefaults.standard.set(whitelistedIdentifiers, forKey: Self.whitelistDefaultsKey)
    }

    /// Short, honest description of what the gate can see, shown in the guide.
    static var detectionCaveat: String {
        "Browser-based decks are recognised from the tab title, which requires Screen Recording. Keynote, PowerPoint and Impress are matched by bundle id and are exact."
    }

    // MARK: - Reading the front window

    private static func readFrontmostApp() -> LyceumFrontmostApp {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .nothing
        }

        let bundleID = application.bundleIdentifier
        let localizedName = application.localizedName ?? ""
        let isBrowser = bundleID.map { browserBundleIDs.contains($0) } ?? false
        let windowTitle = frontmostWindowTitle(forPID: application.processIdentifier)

        return LyceumFrontmostApp(bundleID: bundleID, localizedName: localizedName, windowTitle: windowTitle, isBrowser: isBrowser)
    }

    /// kCGWindowName is only populated for other processes when this app holds
    /// Screen Recording permission — which The Lyceum needs for the slide watcher
    /// anyway, so the gate costs no extra permission prompt.
    private static func frontmostWindowTitle(forPID pid: pid_t) -> String {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ""
        }

        var fallbackTitle = ""
        for info in windowInfos {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }

            // Layer 0 is an ordinary window; menus, panels and the desktop are others.
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            guard layer == 0 else { continue }

            guard let title = info[kCGWindowName as String] as? String else { continue }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty { continue }

            // The list is front-to-back, so the first usable title is the active window.
            if fallbackTitle.isEmpty { fallbackTitle = trimmedTitle }
            return trimmedTitle
        }

        return fallbackTitle
    }

    // MARK: - Matching helpers

    private static func isOwnProcess(_ frontmost: LyceumFrontmostApp) -> Bool {
        guard let bundleID = frontmost.bundleID else { return false }
        return bundleID == Bundle.main.bundleIdentifier
    }

    private static func whitelistIdentifier(for frontmost: LyceumFrontmostApp) -> String? {
        if let bundleID = frontmost.bundleID, !bundleID.isEmpty { return bundleID }
        let name = frontmost.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : "name:\(name.lowercased())"
    }

    private static func matchNativeTool(for frontmost: LyceumFrontmostApp) -> LyceumSlideTool? {
        if let bundleID = frontmost.bundleID, let tool = nativeToolBundleIDs[bundleID] {
            return tool
        }

        // Fall back to the app name so a rebranded or MAS build still matches.
        let loweredName = frontmost.localizedName.lowercased()
        if loweredName.contains("keynote") { return .keynote }
        if loweredName.contains("powerpoint") { return .powerpoint }
        if loweredName.contains("impress") { return .libreOfficeImpress }
        if loweredName.contains("canva") { return .canva }
        return nil
    }

    private static func decideForBrowserTab(_ frontmost: LyceumFrontmostApp) -> LyceumGateDecision {
        let loweredTitle = frontmost.windowTitle.lowercased()

        // An empty title means the tab is not readable (permission revoked, or a
        // browser that hides it). Refuse with the honest reason rather than guess.
        guard !loweredTitle.isEmpty else {
            return .blocked(reason: .notASlideTool(frontmost: frontmost))
        }

        if looksLikeNonDeckDocument(loweredTitle) {
            return .blocked(reason: .designDocumentIsNotASlide(frontmost: frontmost))
        }

        if loweredTitle.contains("google slides") || loweredTitle.contains("docs.google.com") {
            return .allowed(tool: .googleSlides, frontmost: frontmost, viaWhitelist: false)
        }
        if loweredTitle.contains("canva") {
            // Canva titles every document "… – Canva". Without a deck noun it is a
            // social graphic, which is exactly what the user excluded.
            guard deckTitleKeywords.contains(where: { loweredTitle.contains($0) }) else {
                return .blocked(reason: .designDocumentIsNotASlide(frontmost: frontmost))
            }
            return .allowed(tool: .canva, frontmost: frontmost, viaWhitelist: false)
        }
        if loweredTitle.contains("gamma.app") || (loweredTitle.contains("gamma") && loweredTitle.contains("presentation")) {
            return .allowed(tool: .gamma, frontmost: frontmost, viaWhitelist: false)
        }
        if loweredTitle.contains("pitch.com") || loweredTitle.hasSuffix("– pitch") || loweredTitle.hasSuffix("- pitch") {
            return .allowed(tool: .pitch, frontmost: frontmost, viaWhitelist: false)
        }
        if loweredTitle.contains("slides.com") {
            return .allowed(tool: .slidesCom, frontmost: frontmost, viaWhitelist: false)
        }
        if loweredTitle.contains("prezi") {
            return .allowed(tool: .prezi, frontmost: frontmost, viaWhitelist: false)
        }
        if loweredTitle.contains("powerpoint") || (loweredTitle.contains("office.com") && loweredTitle.contains("present")) {
            return .allowed(tool: .powerpoint, frontmost: frontmost, viaWhitelist: false)
        }
        if deckTitleKeywords.contains(where: { loweredTitle.contains($0) }) {
            return .allowed(tool: .unknownSlideTool, frontmost: frontmost, viaWhitelist: false)
        }

        return .blocked(reason: .notASlideTool(frontmost: frontmost))
    }

    private static func looksLikeNonDeckDocument(_ loweredTitle: String) -> Bool {
        nonDeckDocumentKeywords.contains { loweredTitle.contains($0) }
    }
}
