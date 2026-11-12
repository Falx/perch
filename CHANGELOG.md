# Changelog

All notable changes to Perch are documented here. Versions follow
`MAJOR.MINOR.PATCH`; the TOC `## Version` is the source of truth.

## 0.1.0 — unreleased

First working build.

### Added

- Built-in element behaviour:
  - **Gold:** right-click settings with a format preset (default, `12g 34s 56c`,
    coin icons, gold only) or a custom template using `#g #s #c` (amounts) and
    `#gi #si #ci` (coin icons).
  - **Durability:** hovering lists every slot with its percentage (no settings).
  - **Bags:** left-click opens the bags; right-click settings has "Show as one
    bag" (off lists each bag's free/total).
  - **Experience:** right-click settings with presets (current %, current % +
    rested %, current/max, current+rested/max, missing) or a custom template using
    `#c #m #r #x #p #rp #xp`. The bar also refreshes on rested-XP changes.
  - Templates use one shared code engine: longest code wins, `##` is a literal `#`.

- Right-clicking a built-in element opens its settings: the Elements page with
  that element selected. The page now has an "element settings" section for the
  built-ins that have any: Clock (24-hour, local time) and Coordinates (decimals).

- **Elements page:** a scrolling list of every element in bar order (hidden ones
  greyed) with a detail panel: show, icon, label and value checkboxes, a custom
  label input, and Move up / Move down buttons. Commands get label and icon
  options; the Value option applies to data sources only.
- Appearance sliders have a number box that only accepts numbers (decimals only
  where the step is fractional). It follows the slider while you type, steps with
  Up/Down and the mouse wheel, and clamps and snaps to the slider's range on
  Enter. A **Default** button after the box resets the value to the shipped
  default and greys out while the value already is the default. The font
  selector moved to Appearance.
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

- Number boxes looked empty: the Settings canvas is built before it has a size, so
  the client scrolled each box's text out of view (dragging in the box revealed
  it). The cursor is now reset to the start whenever text is set, and when the box
  is shown or resized.
- Broker cells only received left-clicks. They now register for all buttons, so
  plugin right-click handlers work too.
- Option sliders were invisible (a bare `Slider` frame has no track or thumb)
  and their number boxes looked empty (an `EditBox` without a font never draws
  its text). Sliders now draw a track and thumb, and every input sets its font.
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
