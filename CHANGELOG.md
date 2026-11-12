# Changelog

All notable changes to Perch are documented here. Versions follow
`MAJOR.MINOR.PATCH`; the TOC `## Version` is the source of truth.

## 0.1.0 — unreleased

First working build.

### Added

- Settings are split into subpages: **General** (six toggles including
  click-through, plus a font selector), **Appearance** and **Elements**, under a
  **Perch** landing page. Tabs are used when the client lacks the subcategory API.
- `/perch config <general|appearance|elements>` opens a page directly.
- LibSharedMedia-3.0 embedded; fonts from it (and the built-in set) are selectable.
  An unresolvable font falls back to the default instead of breaking the bar.
- `/perch doctor` reports subcategory support, page count and LibSharedMedia.

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

### Fixed

- 16001 raises `FontString:SetText(): Font not set` as a hard error. Cells now
  apply their font before the first text write; previously the first broker cell
  aborted the scan and the bar never rendered.
- One failing data object can no longer abort the scan or the poll; failures are
  reported per object by `/perch doctor`.
- The poll ticker is created before the initial scan, so a scan failure cannot
  leave the bar without updates.
- FPS falls back to `GetFramerate` (`GetFPS` is absent on 16001).
- Plugin callbacks now receive the display cell (LibDBIcon convention), fixing
  the HidingBar tooltip error, and are isolated with `pcall`.
- Command cells call `RegisterForClicks("AnyUp")`; without it the secure macro
  button never fired and `/perch cmd` buttons did nothing.
- Command cells now carry `type`/`type1` and `macrotext`/`macrotext1` plus
  `useOnKeyDown = false`, the combination the Forever client actually executes.
- **Combat `ADDON_ACTION_BLOCKED: Button:SetWidth()` fixed.** Anchoring a
  secure command cell to the bar made the broker cells protected, so resizing
  them in combat was refused. Command cells now live on `UIParent` and are
  anchored to an invisible mirror frame, hidden on `PLAYER_REGEN_DISABLED` and restored
  on `PLAYER_REGEN_ENABLED`.
- Options widgets read the saved values immediately; the Settings canvas is
  created already shown, so `OnShow` never fired on the first open.
- Unticking an element now hides its cell for good; the poll used to re-show it
  at its stale anchor, drawing it over the next element.
- `/perch doctor` reports command cells: shown state, parent, click count and
  the macrotext/type each one carries.
- Layout is skipped during combat (`ClearAllPoints` on secure cells is
  protected) and retried on `PLAYER_REGEN_ENABLED`.
- The Settings canvas gets a chrome-less content frame instead of the draggable
  standalone frame; `/perch frame` builds the standalone frame lazily.

### Changed

- Launcher-type LDB objects are hidden by default and opt-in.
- Options pane lists every detected LDB object with a visibility checkbox.
- `/perch list` shows all elements and marks hidden ones with `[off]`.

### Known limitations

- Element ordering is stored but has no drag-and-drop UI yet.
- No per-element label/colour overrides yet.
- No settings import/export yet.
- Verified on 1.60.1 build 70888; tooltips, UI scale and a second character are
  still pending. Command-cell clicks are instrumented (`/perch doctor` shows a
  per-cell click count) but not yet confirmed in the client.
