# Release Windows

This repo is a macOS AppKit project and does not contain a real Windows build. The Windows option remains a placeholder until a genuine binary exists.

## Current state

- `landing/download-config.json` keeps the Windows channel URL empty.
- `scripts/check-release-windows.sh` exits 0 with a waiting state when no real build is published.
- The landing page therefore shows the Windows channel as not ready rather than advertising a fake executable.

## Allowed options

1. Keep macOS-only and update the landing page to say the platform is not available yet.
2. Ship a real Windows client built with a native stack and upload a genuine `.exe`.
3. Re-use a hosted web client only after a real release pipeline exists for that build; never create a fake `.exe` archive.

Any real Windows work requires a separate engineering decision and a valid installer plus checksum, not a renamed macOS artifact.
