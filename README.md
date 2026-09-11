# circlr

**An orbital music workspace for songwriters and arrangers on macOS.**

English · [한국어](README.ko.md)

[Getting started](#getting-started) · [Documentation](docs/README.md) · [Roadmap](docs/releases/roadmap.md) · [Releases](https://github.com/zeztto/circlr/releases)

In circlr, a circle is a timeline. Build a song from sections, place MIDI, audio, instruments and effects inside them, and connect their inputs and outputs. Move between the whole arrangement and detailed editing on one zoomable canvas.

![A section's circular timelines and MIDI, instrument, effect and audio connections in circlr](docs/images/circlr-orbit-build157.jpg)

*Actual development app, 0.30.0 build157, using an authored QA project. The screenshot shows editing; it does not demonstrate audio playback. [Capture details](docs/images/README.md).*

> **Development preview.** 0.30.0 is in progress, not a completed release. Physical audio output, Korean IME input and parts of the integration checklist remain unverified. See [current QA](docs/releases/0.30.0-qa.md) before evaluating it for production work.

## What you can work with

- **Song form:** nested album, song and section circles; reusable sections, repetitions and arrangement variations.
- **A connected canvas:** free placement, grids, groups, custom colors and connections around eight directions with explicit IN/OUT.
- **MIDI and audio:** orbital note editing, a drum/synth step editor, pitch bend and sustain editing, waveform trim, split and fades.
- **Sound and motion:** instrument/effect routing, automation, bounce and source restoration; playback-follow and signal visualization controls.
- **Local agents:** an MCP interface for inspecting and editing projects, generating MIDI, rendering and saving, with activity visible in the console.

![MIDI notes drawn as arcs and edited within the same canvas](docs/images/circlr-midi-build157.jpg)

These are implemented development features, not a guarantee of compatibility with every audio device or plug-in. Artist profiles and a combined text, image and video workspace are the [longer-term direction](docs/21-artist-universe.md).

## Getting started

Download the current **[0.30.0-preview.1](https://github.com/zeztto/circlr/releases/tag/v0.30.0-preview.1)** for Apple Silicon. This is build158 for evaluation with incomplete QA, not the completed 0.30.0 milestone. Repository access is required while the project remains private. Build from `main` to use the integrated development source.

**Requirements:** macOS 14+, Xcode 26+ selected as the active developer directory, and Python 3. Native validation currently covers Apple Silicon. The interface is currently in Korean; this README is available in both languages.

```sh
git clone --branch main https://github.com/zeztto/circlr.git
cd circlr
./scripts/build-app.sh
open 'dist/써클러.app'
```

The build packages the app, its five audio helpers and the agent kit together. Local packages use ad-hoc signing and are not notarized. Keep a separate copy of important projects when trying development builds.

## First session

1. Right-click empty canvas space to create a circle. Add sections to plan the song, then add MIDI, audio, instruments and effects inside them.
2. Zoom with the wheel over empty canvas space; double-click a circle to enter its detail. Connect ports to define signal flow.
3. Edit notes or steps, import audio/MIDI, and use the toolbar to switch to automation or sound settings.
4. Save the `.circlr` project with **⌘S**. Use **Bounce** to turn a track path into audio and **Restore original** to return to its source.

| Shortcut | Action |
|---|---|
| ⇧⌘P | Search commands and shortcuts |
| ⌘J | Jump to a section, track, instrument or effect |
| Tab / ⇧Tab | Move through editor controls |
| Ctrl + ` | Show or hide the console |
| ⌘W / ⌘Q | Minimize the window / quit the app |

## Developers and agents

Start with [the documentation map](docs/README.md). Contributors should read [CONTRIBUTING.md](CONTRIBUTING.md); coding agents should also read [AGENTS.md](AGENTS.md). For music work, see [MCP setup](mcp/README.md) and the [studio agent kit](docs/24-music-agent-kit.md).

The Swift package separates the project model (`CirclrCore`), audio processing (`CirclrAudio`, `CirclrRealtime`) and macOS interface (`CirclrApp`). GUI and MCP edits use the same document model. See [architecture](docs/15-hierarchy-canvas-architecture.md) and [verification](docs/releases/README.md).

## Status, releases and license

Each completed version will have a Git tag and a GitHub Release with Korean/English notes, a verified app package and checksums. Development build numbers and documentation edits do not create releases. [Changelog](CHANGELOG.md) · [Release procedure](docs/releases/README.md).

circlr is being prepared for a future open-source release. **An open-source license has not been selected or added yet.** Public availability and reuse permissions should not be assumed. Third-party samples and private music projects are not included in this repository.
