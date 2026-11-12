# Changelog

All notable changes to Perch are documented here. Versions follow
`MAJOR.MINOR.PATCH`; the TOC `## Version` is the source of truth.

## 0.1.0 — unreleased

First working build.

### Added

- LibDataBroker-1.1 display: discovers data objects at login and on late
  registration, updates via attribute callbacks with a 1-second poll fallback.
- Broker cells with icon, text, per-plugin click forwarding and tooltips.
- Built-in data sources: clock, gold, FPS, memory, durability, bags, coordinates, XP.
- Command cells: secure macro buttons managed with `/perch cmd add|del`.
- Bar: top-center anchoring, drag when unlocked, saved position, scale, spacing,
  height, icon size, background, fade, hide-in-combat, click-through.
- Native Settings category with a standalone options frame fallback
  (`/perch frame` opens it directly).
- `/perch` commands: config, frame, lock, unlock, scale, list, enable, disable,
  cmd, doctor, dump, reset.
- `/perch doctor` diagnostics report.
- Headless `luajit` test harness and `tools/package.sh`.

### Known limitations

- Element ordering is stored but has no drag-and-drop UI yet.
- No per-element label/colour overrides yet.
- No settings import/export yet.
- Verified against the API stub only; first in-game pass pending.
