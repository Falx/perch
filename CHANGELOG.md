# Changelog

All notable changes to Perch are documented here. Versions follow
`MAJOR.MINOR.PATCH`; the TOC `## Version` is the source of truth.

## 0.1.0 — unreleased

First working build.

### Added

- **Center around an element** (Appearance > Position). With the option on, a
  selector of the currently shown elements becomes active. The chosen element sits
  on the bar's middle; the elements before it fill the left side and the ones
  after it the right side. Both sides get the width of the larger one (at the
  normal spacing), and each side spreads its elements evenly over that space with
  equal gaps. A one-sided choice leaves the other side empty but the same width.
  An unknown or hidden choice falls back to the normal layout.
- Every label is now explicitly centred vertically in a cell as tall as the bar,
  so icons and labels (broker, command, minimap) share the bar's centre line.
- **Position boxes.** Appearance has X and Y offset boxes (pixels from the anchor
  corner), filled in with where the bar is now and updated when you drag it.
  Typing moves the bar live, Up/Down nudge by a pixel, and a sideways offset off
  the preset margin turns the alignment into "custom".
- **Texture previews.** The texture list shows each texture next to its name, and
  the closed selector shows the one in use.
- **End caps redefined.** Flat, **Triangle** (a right triangle at exactly 45
  degrees, as wide as the bar is high, widest at the top edge and meeting the
  bar's bottom corner), **Curved 1** (the old rounded cap), **Curved 2** (a
  quarter circle of radius = bar height centred on the bar's top corner) and
  **Curved 3** (an S-curve, almost horizontal where it leaves the top and where
  it lands on the bottom corner). The width setting applies to Curved 1 and 3.
  Old saved styles carry over ("curved" is Curved 1, the old slant is the
  Triangle).
- **Appearance page, complete.** It scrolls and is split into sections:
  - Position: alignment (top left / top centre / top right, or "custom" once the
    bar has been dragged) and the font.
  - Background: texture (LibSharedMedia), show/hide, colour (swatch with the
    game's colour picker plus a hex box) and alpha.
  - Border: on/off, colour, alpha, thickness. Drawn from plain colour textures
    and never overlapping the background.
  - End caps: left and right as Flat, Triangle, Curved or Slant, with a width.
    Caps are drawn row by row in the bar's own colour and alpha, with the border
    following their edge. They switch off (and their selectors grey out) when the
    background is a texture, and come back with a solid one.
  - Size and text sliders as before.
- Bars saved before alignment existed keep their place: a dragged bar reads as
  "custom".
- **Minimap button icon styles.** Each minimap element can choose how its picture
  is copied: Automatic, First texture, Top texture, Largest texture, Button
  texture, or All layers (every texture the button is made of, stacked), plus a
  crop (original, whole texture, trimmed edges). The source tint and
  desaturation are copied too. Chosen per element on the Elements page.
- **Minimap buttons as elements.** Buttons on the minimap that Perch does not
  already list as an LDB launcher (custom addon buttons, LibDBIcon buttons with
  no matching LDB object) show up in the Elements list as "minimap button".
  They are off until ticked, then show their own icon, or a label (the cleaned
  button name) or a custom label; the icon and label can be toggled
  independently (there is no value). Mouse down/up, clicks of every button,
  double-click, the mouse wheel and hover all reach the original button, with its
  tooltip anchored to the bar. Blizzard's minimap buttons, oversized frames and
  buttons that do nothing are skipped. Perch rescans every 10 seconds, at
  login, and from a **Rescan minimap** button on the Elements page.

- **Command editing on the Elements page:** an Add command button under the list,
  and for a selected command a name box, a macro box and a Remove button (two
  clicks to confirm). Renaming carries the command's element options and bar
  position along; macro edits update the secure button in place and, in combat,
  apply right after it. Invalid names (empty, too long, duplicate) and empty
  macros are refused and the box reverts.
- Built-in element behaviour:
  - **Gold:** right-click settings with a format preset (default, `12g 34s 56c`,
    coin icons, gold only) or a custom template using `#g #s #c` (amounts) and
    `#gi #si #ci` (coin icons).
  - **Durability:** hovering lists every slot with its percentage (no settings).
  - **Bags:** left-click opens the bags (no settings).
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

- The Y offset now counts downwards like a web page: a negative Y moves the whole
  bar up. The bar is no longer clamped to the screen, so it can be moved partly or
  fully off it; it used to stop at the edge while the command buttons (anchored to
  an unclamped copy of its position) kept going, so only one label seemed to move.
- Caps now carry the border along their top and bottom edges as well as the
  slanted/curved one (never on the side against the bar), and are exactly as tall
  as the bar.
- Curved 3 is an exaggerated sine half-wave: horizontal where it leaves the top and
  where it lands on the bottom corner, steep through the middle (an even mix of a
  sine and a sine of that sine). A wide one looks like a wave.
- **Antialiased caps.** Cap edges are no longer stair-stepped: every row keeps its
  exact fractional width, and the last pixel is drawn with the fraction it covers
  as its alpha (in the border colour when there is a border). Pieces never
  overlap, so translucent colours stay correct.
- The end cap width now applies to every cap, including the Triangle and Curved 2
  (a quarter ellipse when it differs from the bar height). It defaults to the bar
  height, which makes the Triangle an exact 45 degree slope and Curved 2 a
  circle, and goes up to 60. The old default of 10 moves to the new default once.
- A picked background texture never showed: it was multiplied by the background
  colour, which is black by default, so every texture came out black. A textured
  background now shows in its own colours (the alpha still applies); a new
  "Tint a textured background with the colour" option restores the tint.
- The default background (`ChatFrameBackground`) was missing from the texture
  list because LibSharedMedia's own "Solid" replaced it; it is now "Default
  (solid)".
- Polestar's menu stayed on the minimap: its fade-in tween re-applies the anchor
  it recorded (`psAnchor`, pointing at the real button) on every step, undoing a
  one-time move. Frames moved to the bar cell are now watched while shown and
  moved again whenever they point back at the button.
- Right-clicking a minimap button raised "Can't measure restricted regions" and
  never ran the click: the frame scan measured every frame, and some refuse to be
  measured. Forbidden and protected frames are now skipped, every frame check is
  guarded, and the re-anchoring runs after the click so it can never block it.
- Menus that a minimap button anchors straight to itself (Polestar's right-click
  menu) opened at the minimap. After a forwarded click, frames that are newly
  shown and anchored to the button are re-anchored to the bar cell; frames that
  were already there and the button's own children are left alone. Not done in
  combat.
- Hover panels that are not `GameTooltip` (FishFry's Snapshot) appeared under the
  minimap: they place themselves from the button's screen rectangle. While the
  mouse is over the bar cell, the original button now reports the cell's
  geometry, and gives its own back on leave or hide.
- The poll compared the raw plugin text with the composed cell text, so any
  element with a label or custom label was refreshed every second.
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
