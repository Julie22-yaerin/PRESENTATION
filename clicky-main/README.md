## The Lyceum

The Lyceum is this repo turned into a rehearsal coach. Same engine, same hotkey, one new idea: **tap** the hotkey instead of holding it, and the app watches your screen and listens to you present, then grades the run.

Tap `Control + Option` to start a run. Talk through your deck like you would in the room — slides change are detected automatically. Tap it again to stop. A few seconds later you get a verdict: scores, what landed, where it broke, and per-slide edits you can copy straight back into Keynote or PowerPoint. Export the whole thing as Markdown or JSON.

Three drills, picked in the panel:

- **Feynman** — teach a concept out loud. It flags the jargon you used without defining, the mechanism you hand-waved past, and the exact step where your chain breaks.
- **Debate** — argue a position under time pressure. It reconstructs your case, lists the objections you never answered, and scores structure, evidence, delivery and rebuttal.
- **Slide review** — present the deck. It reads density, checks whether what you *said* matches what's *on* the slide, and rewrites bullets plus speaker notes for each one.

Holding `Control + Option` still does the original thing: push-to-talk, screenshot, question, answer. Nothing was taken away.

Built on [Clicky](https://github.com/farzaa/clicky) by [@farzatv](https://x.com/FarzaTV), MIT licensed. The product name changed; the original code, license and author notes below stay exactly as they were.

---

## Get HeyClicky for Mac and Windows

The official app is **[HeyClicky](https://www.heyclicky.com/)**, an AI buddy for Mac and Windows, made by me and the team.

- **Mac:** [download HeyClicky for Mac](https://www.heyclicky.com/for-mac) (macOS 14.2 or later)
- **Windows:** [download HeyClicky for Windows](https://www.heyclicky.com/for-windows) (Windows 10 and 11)

Those are the only official downloads. Other Windows apps built from this repo are community ports, not made by us.

---

Update: April 27, 2026.

Hi there! I'm Farza, the guy that made Clicky.

The existing codebase remains open source. Tinker with it, make it yours, start a company out of it, do whatever you want I don't mind. But, for all the new stuff I'm hacking on, gonna keep it private. To get the latest version, HeyClicky for Mac or Windows, go to [heyclicky.com](https://www.heyclicky.com/).

I also tweeted about this [here](https://x.com/FarzaTV/status/2043402737828962489).

Go crazy with this repo!! It's an MIT license.

# Hi, this is Clicky.
It's an AI teacher that lives as a buddy next to your cursor. It can see your screen, talk to you, and even point at stuff. Kinda like having a real teacher next to you.

Download HeyClicky for free for [Mac](https://www.heyclicky.com/for-mac) or [Windows](https://www.heyclicky.com/for-windows).

Here's the [original tweet](https://x.com/FarzaTV/status/2041314633978659092) that kinda blew up for a demo for more context.

![Clicky — an ai buddy that lives on your mac](clicky-demo.gif)

This is the open-source version of Clicky for those that want to hack on it, build their own features, or just see how it works under the hood.

## Get started with Claude Code

The fastest way to get this running is with [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Once you get Claude running, paste this:

```
Hi Claude.

Clone https://github.com/farzaa/clicky.git into my current directory.

Then read the CLAUDE.md. I want to get Clicky running locally on my Mac.

Help me set up everything — the Cloudflare Worker with my own API keys, the proxy URLs, and getting it building in Xcode. Walk me through it.
```

That's it. It'll clone the repo, read the docs, and walk you through the whole setup. Once you're running you can just keep talking to it — build features, fix bugs, whatever. Go crazy.

## Manual setup

If you want to do it yourself, here's the deal.

### Prerequisites

- macOS 14.2+ (for ScreenCaptureKit)
- Xcode 15+
- Node.js 18+ (for the Cloudflare Worker)
- A [Cloudflare](https://cloudflare.com) account (free tier works)
- API keys for: [Anthropic](https://console.anthropic.com), [AssemblyAI](https://www.assemblyai.com), [ElevenLabs](https://elevenlabs.io)

### 1. Set up the Cloudflare Worker

The Worker is a tiny proxy that holds your API keys. The app talks to the Worker, the Worker talks to the APIs. This way your keys never ship in the app binary.

```bash
cd worker
npm install
```

Now add your secrets. Wrangler will prompt you to paste each one:

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
```

For the ElevenLabs voice ID, open `wrangler.toml` and set it there (it's not sensitive):

```toml
[vars]
ELEVENLABS_VOICE_ID = "your-voice-id-here"
```

Deploy it:

```bash
npx wrangler deploy
```

It'll give you a URL like `https://your-worker-name.your-subdomain.workers.dev`. Copy that.

### 2. Run the Worker locally (for development)

If you want to test changes to the Worker without deploying:

```bash
cd worker
npx wrangler dev
```

This starts a local server (usually `http://localhost:8787`) that behaves exactly like the deployed Worker. You'll need to create a `.dev.vars` file in the `worker/` directory with your keys:

```
ANTHROPIC_API_KEY=sk-ant-...
ASSEMBLYAI_API_KEY=...
ELEVENLABS_API_KEY=...
ELEVENLABS_VOICE_ID=...
```

Then update the proxy URLs in the Swift code to point to `http://localhost:8787` instead of the deployed Worker URL while developing. Grep for `clicky-proxy` to find them all.

### 3. Update the proxy URLs in the app

The app has the Worker URL hardcoded in a few places. Search for `your-worker-name.your-subdomain.workers.dev` and replace it with your Worker URL:

```bash
grep -r "clicky-proxy" leanring-buddy/
```

You'll find it in:
- `CompanionManager.swift` — Claude chat + ElevenLabs TTS
- `AssemblyAIStreamingTranscriptionProvider.swift` — AssemblyAI token endpoint

### 4. Open in Xcode and run

```bash
open leanring-buddy.xcodeproj
```

In Xcode:
1. Select the `leanring-buddy` scheme (yes, the typo is intentional, long story)
2. Set your signing team under Signing & Capabilities
3. Hit **Cmd + R** to build and run

The app will appear in your menu bar (not the dock). Click the icon to open the panel, grant the permissions it asks for, and you're good. The product is `Lyceum.app` but it keeps the original bundle id `com.yourcompany.leanring-buddy` — deliberately, because changing it would silently reset every TCC permission you already granted.

### Permissions the app needs

- **Microphone** — push-to-talk, plus continuous capture while a practice run is live
- **Accessibility** — for the global keyboard shortcut (Control + Option: tap = run, hold = ask)
- **Screen Recording** — screenshots on the hotkey, plus a 1.6s slide-change watcher while a run is live
- **Screen Content** — for ScreenCaptureKit access

The slide watcher only stores a snapshot when the screen actually settles on something new, so a 10-minute run costs a handful of images, not 400.

## Architecture

If you want the full technical breakdown, read `CLAUDE.md`. But here's the short version:

**Menu bar app** (no dock icon) with three `NSPanel` windows — the control panel dropdown, the full-screen transparent cursor overlay, and the Lyceum coach panel that parks bottom-right while you present. Push-to-talk streams audio over a websocket to AssemblyAI, sends the transcript + screenshot to Claude via streaming SSE, and plays the response through ElevenLabs TTS. Claude can embed `[POINT:x,y:label:screenN]` tags in its responses to make the cursor fly to specific UI elements across multiple monitors. All three APIs are proxied through a Cloudflare Worker.

The coaching path reuses the same pieces with different plumbing. `LyceumSessionRecorder` owns a second `AVAudioEngine` for the long run and rotates the AssemblyAI session every five minutes, because a temporary streaming token dies at 480 seconds — the transcript from each segment is stitched into one text. `LyceumSlideWatcher` squashes each frame to a 12x8 luminance grid and commits a slide when that grid stays different for two polls, so the menu bar clock and hover states do not count as slides. At stop, the transcript plus up to 12 of the slides that held the most screen time go into one Claude call with a JSON output contract; the verdict is parsed into `LyceumCoachReport`, saved under `Application Support/The Lyceum/Sessions`, and the two-sentence `spokenFeedback` is read aloud.

## Project structure

```
leanring-buddy/          # Swift source (yes, the typo stays)
  CompanionManager.swift    # Central state machine, tap vs hold detection
  CompanionPanelView.swift  # Menu bar panel UI
  ClaudeAPI.swift           # Claude streaming client
  ElevenLabsTTSClient.swift # Text-to-speech playback
  OverlayWindow.swift       # Blue cursor overlay
  AssemblyAI*.swift         # Real-time transcription
  BuddyDictation*.swift     # Push-to-talk pipeline
  LyceumCoachModels.swift     # Drills, report model, JSON parser, exporters
  LyceumCoachPrompts.swift  # System prompts for the three drills
  LyceumSessionRecorder.swift # Long-form mic capture with token rotation
  LyceumSlideWatcher.swift  # Slide-change detection while presenting
  LyceumCoachManager.swift  # Runs the session, grades it, saves it
  LyceumCoachPanelView.swift # Coach UI: live run + verdict
  LyceumCoachWindowManager.swift # Floating coach panel
worker/                  # Cloudflare Worker proxy
  src/index.ts              # Three routes: /chat, /tts, /transcribe-token
CLAUDE.md                # Full architecture doc (agents read this)
```

## Contributing

PRs welcome. If you're using Claude Code, it already knows the codebase — just tell it what you want to build and point it at `CLAUDE.md`.

Got feedback? DM me on X [@farzatv](https://x.com/farzatv).
