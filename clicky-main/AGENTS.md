# The Lyceum (Clicky fork) - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

macOS menu bar companion app. Lives entirely in the macOS status bar (no dock icon, no main window). Clicking the menu bar icon opens a custom floating panel with companion voice controls. Uses push-to-talk (ctrl+option) to capture voice input, transcribes it via AssemblyAI streaming, and sends the transcript + a screenshot of the user's screen to Claude. Claude responds with text (streamed via SSE) and voice (ElevenLabs TTS). A blue cursor overlay can fly to and point at UI elements Claude references on any connected monitor.

This fork is **The Lyceum**, a presentation rehearsal coach. The same ctrl+option shortcut now carries two intents: **hold it** to ask a question (the original push-to-talk flow, unchanged), **tap it** (press and release under 300ms) to start or stop a coaching run. During a run the app streams long-form audio, watches the screen for slide changes, and on stop grades the whole thing — transcript plus the slides that actually held screen time — against one of three drills: Feynman, Debate, Slide review. Output is a structured `LyceumCoachReport` (scores, gaps, per-slide rewrites, speaker notes) shown in its own floating panel, spoken aloud via TTS, saved to Application Support, and exportable as Markdown or JSON.

Two things sit on top of that. **A gate**: a run may only start when the frontmost app is a slide tool (`LyceumAppGate` — bundle id for Keynote/PowerPoint/Impress/Canva desktop, browser tab title for Google Slides/Canva/Gamma/Pitch/Prezi/slides.com, with a poster-vs-deck distinction, a per-app whitelist and an off switch). **A room**: when the run ends — by tap, by a farewell slide, or by heard closing words in any language followed by three seconds of silence (`LyceumClosingDetector`) — `LyceumAudienceManager` convenes five persona agents that watched the same screen and heard the same words, asks each one question out loud in the language the user presented in, takes the user's spoken answer on the same hold gesture, lets the asking agent judge it and push back once, then scores how the talk defended and merges that `defenseScore` into the same saved report. The panel is drawn as a call (`LyceumAudiencePanelView`: tile grid, caption strip, permanent control bar, room code, self tile, People and Chat popovers).

All API keys live on a Cloudflare Worker proxy — nothing sensitive ships in the app.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@Published` state management
- **AI Chat**: Claude (Sonnet 4.6 default, Opus 4.6 optional) via Cloudflare Worker proxy with SSE streaming
- **Speech-to-Text**: AssemblyAI real-time streaming (`u3-rt-pro` model) via websocket, with OpenAI and Apple Speech as fallbacks
- **Text-to-Speech**: ElevenLabs (`eleven_flash_v2_5` model) via Cloudflare Worker proxy
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Push-to-talk via `AVAudioEngine` + pluggable transcription-provider layer. System-wide keyboard shortcut via listen-only CGEvent tap.
- **Element Pointing**: Claude embeds `[POINT:x,y:label:screenN]` tags in responses. The overlay parses these, maps coordinates to the correct monitor, and animates the blue cursor along a bezier arc to the target.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: PostHog via `ClickyAnalytics.swift`
- **Coaching Runs**: `LyceumCoachManager` orchestrates a long-form capture (own `AVAudioEngine`) plus `LyceumSlideWatcher` (luminance-grid slide-change detection), then one multimodal Claude call with a JSON output contract
- **Branding**: `PRODUCT_NAME = Lyceum` and `CFBundleDisplayName = The Lyceum`, but the bundle id (`com.yourcompany.leanring-buddy`), target and directory names stay Clicky's on purpose — changing the bundle id silently invalidates every TCC permission the user granted

### API Proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real API keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Fetches a short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`
Worker vars: `ELEVENLABS_VOICE_ID`

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. This gives full control over appearance (dark, rounded corners, custom shadow) and avoids the standard macOS menu/popover chrome. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks.

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the blue cursor companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Shared URLSession for AssemblyAI**: A single long-lived `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the session). Creating and invalidating a URLSession per session corrupts the OS connection pool and causes "Socket is not connected" errors after a few rapid reconnections.

**Transient Cursor Mode**: When "Show Clicky" is off, pressing the hotkey fades in the cursor overlay for the duration of the interaction (recording → response → TTS → optional pointing), then fades it out automatically after 1 second of inactivity. A live coaching run suppresses this fade so the user can keep seeing where they are in the talk.

**Tap vs Hold on One Shortcut**: `handleShortcutTransition(.pressed)` no longer opens the microphone immediately; it waits out `shortcutTapThresholdSeconds` (300ms) and only then starts dictation. On `.released`, a press shorter than the threshold cancels that pending task and toggles a coaching run instead. The delay is what lets one key do both jobs without a second hotkey. If a coaching run already owns the microphone, holds are swallowed entirely (`isHoldingShortcutForCoachSession`) because a second `AVAudioEngine` cannot capture the same device concurrently.

**A Third Meaning for the Same Key**: while the audience panel is waiting for an answer, `.pressed` sets `shortcutPressIsForPanelAnswer` and the dictation callbacks route the transcript to `LyceumCoachManager.receiveUserAnswer` instead of the screenshot question flow; a tap in that state passes the question. The three intents are distinguished by state, never by a second hotkey.

**Audience Voices**: ElevenLabs voice ids are per agent and optional (`ElevenLabsTTSClient.speakText(_:voiceID:)`, forwarded as `voice_id` to the Worker's `/tts`). With none set, `LyceumVoiceAllocator` gives each member a distinct local `AVSpeechSynthesisVoice` filtered to the spoken language, shaped by the member's tone (rate and pitch) — so the panel sounds like several people with no API key configured. Audio is serialised because the panel shares the coach's `ClaudeAPI` and `ElevenLabsTTSClient` instances: `waitUntilAudioStops` waits for playback to *start* before waiting for it to end, which is what stops one agent talking over another.

**Gate at the Moment of the Press**: `LyceumAppGate.evaluateNow()` reads `NSWorkspace.frontmostApplication` plus the front window title from `CGWindowListCopyWindowInfo` (`kCGWindowName`, only populated for other processes once Screen Recording is granted). It is evaluated on press, never on a timer, and a refusal is always surfaced — in the coach panel and as a transient notice over the cursor overlay — because a silently dead hotkey reads as a broken app.

**Long-Form Transcription**: AssemblyAI temporary streaming tokens expire after 480s, so `LyceumSessionRecorder` rotates the provider session every 300s — it requests the segment's final transcript, commits it to a prefix, opens a new session and flushes the buffers held during the gap. The provider already composes all turns into one transcript, so stitching only needs the committed prefix.

**Slide-Change Detection**: The watcher polls the watched display every 1.6s and compares a 12x8 luminance grid (top-right cell excluded, that is where the menu bar clock lives) against the last committed slide. A change must exceed 0.042 mean absolute difference and survive two polls, or exceed 0.13 outright. Byte-hashing the JPEG would fire on every hover and video tile; a coarse luminance grid does not. Only committed snapshots are kept (max 40 per run), and at most 12 — slide 1, the last slide, then the ones with the longest dwell — are sent for grading.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~97 | Menu bar app entry point. Uses `@NSApplicationDelegateAdaptor` with `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager`. No main window — the app lives entirely in the status bar. Two first-run jobs happen here: `LyceumAppearanceController.shared.apply()` before any window exists, and opening the dashboard when the learner profile has never been filled in, because that is where the questionnaire is hosted. |
| `CompanionManager.swift` | ~1173 | Central state machine. Owns dictation, shortcut monitoring, screen capture, Claude API, ElevenLabs TTS, and overlay management. Tracks voice state (idle/listening/processing/responding), conversation history, model selection, and cursor visibility. Coordinates the full push-to-talk → screenshot → Claude → TTS → pointing pipeline. |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. |
| `CompanionPanelView.swift` | ~927 | SwiftUI panel content for the menu bar dropdown. Shows companion status, push-to-talk instructions, the Practice Run card (drill picker + start/stop), model picker (Sonnet/Opus), permissions UI, DM feedback button, and quit button. Dark aesthetic using `DS` design system. |
| `OverlayWindow.swift` | ~881 | Full-screen transparent overlay hosting the blue cursor, response text, waveform, and spinner. Handles cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping, and fade-out transitions. |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~100 | Protocol surface and provider factory for voice transcription backends. Resolves provider based on `VoiceTranscriptionProvider` in Info.plist — AssemblyAI, OpenAI, or Apple Speech. |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~478 | Streaming transcription provider. Fetches temp tokens from the Cloudflare Worker, opens an AssemblyAI v3 websocket, streams PCM16 audio, tracks turn-based transcripts, and delivers finalized text on key-up. Shares a single URLSession across all sessions. |
| `OpenAIAudioTranscriptionProvider.swift` | ~317 | Upload-based transcription provider. Buffers push-to-talk audio locally, uploads as WAV on release, returns finalized transcript. |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local fallback transcription provider backed by Apple's Speech framework. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~295 | Claude vision API client with streaming (SSE) and non-streaming modes. TLS warmup optimization, image MIME detection, conversation history support. `analyzeImageStreaming` takes `maxTokens` (default 1024) because a graded rehearsal run needs a much longer answer than a spoken one-liner. |
| `OpenAIAPI.swift` | ~142 | OpenAI GPT vision API client. |
| `ElevenLabsTTSClient.swift` | ~81 | ElevenLabs TTS client. Sends text to the Worker proxy, plays back audio via `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| `ElementLocationDetector.swift` | ~335 | Detects UI element locations in screenshots for cursor pointing. |
| `DesignSystem.swift` | ~880 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `ClickyAnalytics.swift` | ~241 | PostHog analytics integration for usage tracking. The Lyceum events are scalars only — grade *kind*, counts, switches, section names. There is deliberately no API that can accept a school name, a competition name or transcript text. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |
| `LyceumCoachManager.swift` | ~1060 | The Lyceum brain. Owns the run lifecycle (idle → preparing → recording → analysing → ready/failed), the slide-tool gate, the closing-signal watch, the optional camera, the audience panel, which slides to grade, the prompt (`systemPrompt(for:) + topicContextLine() + profileContextLine()`), the verdict, the saved session and the export. Also holds `LyceumSessionStore` (Application Support/The Lyceum/Sessions) and the 75s live-nudge loop. |
| `LyceumCoachModels.swift` | ~460 | Drill enum (four drills), session phase, slide snapshot, `LyceumCoachReport` (including `LyceumPresenceNotes`), `LyceumSavedSession` (now with the measured delivery and the still count), tolerant JSON parser that falls back to prose so a 10-minute run is never lost, and the Markdown/JSON exporters. |
| `LyceumCoachPrompts.swift` | ~230 | System prompts for Feynman / Defence / Debate / Slide review, the tiny live-checkpoint prompt, and the transcript+context builder. The builder also carries the measured delivery numbers and, when the camera ran, the rules about what a still is allowed to prove. Every prompt demands one JSON object in the language the user spoke. |
| `LyceumSessionRecorder.swift` | ~420 | Long-form microphone capture on its own `AVAudioEngine`, provider session rotation every 300s, buffered hand-off across the gap, transcript prefix stitching, live audio power metering — and `LyceumDeliveryMeter` fed from the same tap, so pace, silence, loudness, pitch and filler words are measured without capturing anything extra. |
| `LyceumSlideWatcher.swift` | ~314 | Slide-change detection. Polls one latched display via ScreenCaptureKit, compares 12x8 luminance signatures with debounce, emits `LyceumSlideSnapshot`s with dwell time. |
| `LyceumCoachPanelView.swift` | ~1230 | Coach UI: drill picker, live transcript + level meter, live nudge, grading preview, verdict (scores, measured numbers, voice/presence notes, strengths, gaps, slide-edit cards with Copy), the gate card, the room card, the camera/voice card, saved-run history, exports, and the Dashboard button. |
| `LyceumAppGate.swift` | ~409 | The slide-tool gate. Reads the frontmost app and its window title, maps them to a `LyceumSlideTool` (bundle id for native apps, multilingual deck-vs-poster title keywords for browser tabs), decides allow/block, keeps a user whitelist and an off switch. Also declares `Notification.Name.lyceumNeedsAttention`, the only way the Lyceum objects reach the cursor overlay. |
| `LyceumAudience.swift` | ~1138 | Audience data and pure functions: member/tone model with the default five personas and their persistence, plus the three optional criterion arrays (`functions`, `traits`, `focus`) whose raw values come from `LyceumAgentFunction` / `LyceumAgentTrait` / `LyceumAgentFocus`, `maximumCriteria = 5` enforced by the pure `toggling(_:)`, `criteriaSummaryForModel` / `criteriaBriefsForModel` for the prompt, and `hasOwnName`. `LyceumAudienceRoster.maximumMembers` is 5. `LyceumAudienceTuning` turns a learner profile into a room (tone steps, role swaps, never touching a customised seat). Also panel question and exchange types, the tolerant JSON parsers for the panel/reaction/defense contracts, `LyceumClosingDetector` (closing phrases in ~15 languages plus the closing-slide vision prompt), and `LyceumVoiceAllocator`. All prompts live in `LyceumAudiencePrompts`. |
| `LyceumOnboarding.swift` | ~985 | The five first-run questions and `LyceumProfileStore` (`lyceumLearnerProfile`, one JSON blob, decode failure = empty profile). `LyceumGrade` / `LyceumAudienceKind` carry `contextPhrase`; the store exposes one `contextLineForModel` string, and the view owns completion (`profile.markCompleted()` then `onFinish()`), so a host cannot ship a half profile. |
| `LyceumAgentStudio.swift` | ~550 | The studio: list of five seats and an editor for name, icon, tone and up to five criteria, writing straight through `audience.members` (whose `didSet` persists). At the ceiling the unchosen chips are disabled rather than hidden, next to a preview of the sentence the agent will actually receive. |
| `LyceumTheme.swift` | ~145 | `LyceumAppearanceController` (`lyceumAppearanceMode`, `lyceumReduceMotion`): sets `NSApp.appearance` and hands out `colorScheme` for the `.lyceumColorScheme` modifier, which every Lyceum surface uses. Prefer the no-argument form: it keeps a live subscription inside a `ViewModifier`, which matters for panels built once by an `NSHostingView`. The dashboard's old hard-coded `.dark` is gone; a view that forgets the modifier drifts back to the system. |
| `LyceumDashboardSettingsView.swift` | ~1449 | Everything behind the gear, as a 760x560 sheet with its own rail: voice and camera, room (opens the studio), rules, data (counts, open folder, export all as JSON, delete runs older than 30/90 with an inline confirm), appearance, getting started (shows `contextLineForModel`, re-runs onboarding). The three sections that were dashboard tabs moved here — do not leave duplicates behind. |
| `LyceumAudienceManager.swift` | ~760 | The Q&A round state machine: convene (one text-only Claude call over the transcript), ask each agent in turn with captions revealed at speaking pace, take the spoken answer, judge it, push back once, then score the defence and hand the score to the coach. `maximumQuestions` (default 3, keeps the kind opening and the harshest last voice) and `unansweredTimeoutSeconds` (default 45) are user-settable dials, not constants. Owns muting, captions, the pass timer, ambient hand raises and the room code. |
| `LyceumAudiencePanelView.swift` | ~627 | The room drawn as a call: participant tile grid with speaking ring and raised hand, caption strip, "hold ⌃⌥ to answer" hint, permanent control bar (mute, captions, pass, verdict, leave, People, Chat), self tile with live mic level, roster editor and question/answer log popovers. |
| `LyceumAudienceWindowManager.swift` | ~147 | The room's `NSPanel`: borderless, non-activating, joins all Spaces, above full-screen apps, resizable, remembers its frame, opens bottom-left so the verdict panel keeps bottom-right. |
| `LyceumCoachWindowManager.swift` | ~142 | The floating coach `NSPanel`: non-activating, joins all Spaces, rides above full-screen apps, parks bottom-right and respects a user drag. |
| `LyceumDeliveryMeter.swift` | ~420 | Deterministic microphone arithmetic over the buffers the recorder already has: RMS and loudness range in dBFS, spectral flatness for voiced time and longest pause, a zero-crossing pitch proxy, words per minute from the transcript, and filler-word counts per language. No vectors, no model, no ML framework. |
| `LyceumPresenceCamera.swift` | ~350 | The opt-in camera. `AVCapturePhotoOutput` stills on a timer, downscaled to 512px, kept in an array for exactly one review and then dropped: never written to disk, never stored in a session. Holds `LyceumPresencePrompts.rules`, the text that keeps the model inside what a still can actually show. |
| `LyceumInsights.swift` | ~350 | Term-level aggregation over the saved sessions: score trend, runs per day, streak, per-drill averages, and a keyword count over the gap/jargon/counter lists so the same weak spot surfaces across weeks. Pure arithmetic, so it is cheap enough to recompute whenever the dashboard opens. |
| `LyceumDashboardView.swift` | ~1573 | The dashboard, for practising only: overview, progress, every saved run with the full report, and a guide written for a student. `DashboardTab` has those four cases; configuration lives in `LyceumDashboardSettingsView` behind the gear at the foot of the sidebar. It also hosts the onboarding overlay (`!profileStore.hasCompletedOnboarding` covers the whole window) and the agent studio sheet, and `finishOnboarding()` is the only place that applies `LyceumAudienceTuning` and reports the questionnaire to analytics. |
| `LyceumDashboardWindowManager.swift` | ~155 | The app's only real `NSWindow` (titled, focusable, frame-remembered). Borrows the regular activation policy while it is open and hands `LSUIElement` back on close. |
| `worker/src/index.ts` | ~142 | Cloudflare Worker proxy. Three routes: `/chat` (Claude), `/tts` (ElevenLabs), `/transcribe-token` (AssemblyAI temp token). The `/chat` route forwards the request body untouched, so `max_tokens` set by the app is respected without touching the Worker. |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the leanring-buddy scheme, set signing team, Cmd+R to build and run

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Cloudflare Worker

```bash
cd worker
npm install

# Add secrets
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

# Deploy
npx wrangler deploy

# Local dev (create worker/.dev.vars with your keys)
npx wrangler dev
```

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not write presenter camera stills to disk, into a saved session, or into an export. They live in `LyceumPresenceCamera.frames` for one review and are dropped. If a feature needs them later, it has to be re-asked for, visibly.
- Do not install a second tap on the recorder's input node. Everything audio-measurement needs is already inside `updateAudioPowerLevel(from:)`; a second tap on one `AVAudioEngine` input node breaks capture.
- Do not make the panel personas business-y. This product is for students rehearsing in front of a class or a judging panel; the roster, the prompts and the drills are written for that room.
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)
- Do not run `xcodebuild` from the terminal — it invalidates TCC permissions
- Do not remove the gate's escape hatches (per-app whitelist and the off switch) — browser-tab detection is a heuristic and a tool that is not on the list must not become a dead end
- Do not let the coach speak its verdict and convene the panel in the same breath; `deliverVerdict(report:)` picks one, because the room's first line already does the summary job

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
