# Changelog

All notable changes to Clonk are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-05-27

First production release.

### Added
- Five DSP-synthesised voices — Clicky Blue, Tactile Brown, Linear Red, Deep
  Thock, Vintage Typewriter — modelled on real switch archetypes.
- Per-key voice overrides and a live sound playground in the popover.
- **Profiles**: name and switch between complete sound sets in one click.
- **Sleep rules**: auto-mute on battery / low battery, within set hours, when
  a specific app is in front, while idle, on an external keyboard, during a
  calendar event, or with multiple displays attached.
- **Play modes**: Piano (tuned notes, configurable scale/root/sustain) and
  Guitar (plucked strings with optional modifier sustain).
- **Spatial audio**: pan clicks left-to-right across the keyboard.
- **On-screen overlays**: floating Keyboard, Minimal, WPM and CPM widgets.
- **Sample-pack import**: drop a folder of audio files (wav, aiff, caf, mp3,
  m4a, flac) and Clonk plays a random sample on every keystroke.
- Mac App Store distribution pipeline (`make build-mas`).
- Drag-to-install DMG pipeline (`make dmg`).
- Stable-signing path (`Clonk Dev` self-signed cert) so macOS keeps the
  Accessibility grant across local rebuilds.

### Security & privacy
- Listen-only `CGEventTap` — Clonk never modifies or swallows input.
- Zero network code. Nothing leaves the device.
- Sandboxed MAS build; non-sandboxed direct-distribution build for the
  Accessibility-grant developer workflow.
- Privacy manifest declares only `UserDefaults` (CA92.1).
