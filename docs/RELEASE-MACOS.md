# Release macOS

This project keeps release metadata in `clicky-main/Config/Release.xcconfig`, `landing/download-config.json`, and the appcast feed at `clicky-main/appcast.xml`.

## Current settings

- Version: 0.4.0
- Build number: 4
- Minimum macOS: 14.2
- Product: The Lyceum
- Feed URL: https://raw.githubusercontent.com/Julie22-yaerin/PRESENTATION/main/clicky-main/appcast.xml

## Release mode

This repo targets the universal binary route (A): one build that works on Apple Silicon and Intel, published under the two download names required by the landing page:

- TheLyceum-arm64.dmg
- TheLyceum-intel.dmg

The app identifiers and script variables stay consistent with the repo: `The Lyceum` as the product name and `Julie22-yaerin/PRESENTATION` as the release repo.
