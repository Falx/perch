# Perch — design plan

**Status:** Phase 0/1 implemented; the bar renders in the client and broker
clicks, drag and embedded options work. Third-pass fixes (secure cells on
`UIParent`, options init, hidden disabled cells) are committed pending a
command-click retest — see `docs/ADDON-NOTES.md`
**Last updated:** 2026-11-12
**Target client:** World of Warcraft: Forever, interface `16001`
**Repo identity:** `Falx <thomasdupont100@gmail.com>` (repo-local git config)

Resume by reading this file plus `AGENTS.md`, then run `luajit tests/run.lua`
and `tools/package.sh`.

---

## 1. Goal

A horizontal, centered data bar at the top of the screen that:

1. Displays **LibDataBroker-1.1 (LDB)** objects as live, clickable cells.
2. Ships its **own data sources**, registered as LDB objects so the display treats
   them like any plugin.
3. Supports **command cells** (icon + label + macro text) to trigger other addons
   or game actions.
4. Is **visually customizable** with live application.
5. Persists settings in versioned saved variables.

Out of scope for v1: adapter modules for individual addons, multi-bar layouts,
wrapping to multiple rows, boss mods, damage meters.

---

## 2. Decisions

| Decision | Choice |
|---|---|
| Name | Perch |
| Folder / TOC | `Perch` |
| Saved variable | `PerchDB` |
| Globals | `Perch_*`, namespace `_G.Perch` |
| Slash command | `/perch` |
| Options | Native `Settings` API + standalone fallback frame |
| No Ace3 | Vendored LibStub, CallbackHandler-1.0, LibDataBroker-1.1 only |
| Client | Forever only, interface `16001` |
| Transport | Git remote; addon folder symlinked or copied into `Interface/AddOns` |
| Testing | `luajit` harness locally, live client on the user's other PC |

---

## 3. Repository layout

```
Perch/                      shipped addon
  Perch.toc
  Core.lua                  namespace, DB defaults, events, /perch dispatch
  Bar.lua                   frame, layout, position, styling
  Element.lua               broker cells (icon/text/click/tooltip)
  Command.lua               secure macro cells
  Broker.lua                LDB discovery + updates
  Builtins.lua              8 built-in data sources
  Doctor.lua                /perch doctor report
  Config.lua                Options framework (widgets, picker, pages, Settings registration)
  ConfigGeneral/Appearance/Elements.lua   one options page each
  Media.lua                 LibSharedMedia wrapper with built-in fallback
  Format.lua                #code template engine, gold and XP formats
  Libs/                     LibStub, CallbackHandler-1.0, LibDataBroker-1.1
tests/                      headless harness (not shipped)
tools/package.sh            validation + dist zip
docs/PLAN.md                this file
docs/ADDON-NOTES.md         in-game findings
AGENTS.md                   conventions for future sessions
```

---

## 4. Architecture

### 4.1 LDB integration

Verified against the vendored LibDataBroker-1.1 (minor 4):

- Data objects are **proxies**; `object.callbacks` does not exist.
- Callbacks live on the **library object** and fire as
  `(eventName, ...)` with no target prefix:
  - `LibDataBroker_DataObjectCreated` → `(name, object)`
  - `LibDataBroker_AttributeChanged` → `(name, key, value, object)`
- Assigning a proxy field fires callbacks **only when the value changes**, so
  Perch must not fire them manually.
- Discovery: `DataObjectIterator()` at login, `DataObjectCreated` for anything
  registered later.
- A 1-second poll remains as a safety net for plugins that bypass the proxy.

### 4.2 Cell types

**Broker cell** — `Button` with icon, font string, highlight.
- Plugin callbacks receive the **cell**, matching LibDBIcon:
  `OnClick(cell, button)`, `OnEnter(cell)`, `OnLeave(cell)`,
  `OnMouseDown/OnMouseUp(cell, button)`. HidingBar and EnhanceQoL call frame
  methods on that argument, so passing the data object breaks them.
- All plugin callbacks are `pcall`ed; failures are reported once per object by
  `/perch doctor`.
- `OnEnter` → `GameTooltip:SetOwner`, then `OnTooltipShow` if defined, else
  `label`/`text` fallback. `OnLeave` hides the tooltip and forwards.
- The font is applied **before** the first `SetText` (16001 errors otherwise).
- Empty text with no icon hides the cell.
- `type == "launcher"` objects are hidden unless explicitly enabled.

**Command cell** — `SecureActionButtonTemplate` parented to **`UIParent`**, with
`type = "macro"`, `type1 = "macro"`, `macrotext`/`macrotext1`, `useOnKeyDown =
false` and `RegisterForClicks("AnyUp")` (without it the template never fires
`OnClick`). Works for `/cast`, `/use`, `/target` and addon slash commands while
respecting combat protection.

On 16001 a secure button anchored to a normal frame makes that frame protected
too, so the bar and every broker cell would refuse `SetWidth` in combat
(`ADDON_ACTION_BLOCKED`). Command cells therefore stay on `UIParent` and
`Layout` anchors them to an invisible **mirror frame** (`P.secureAnchor`) that
copies the bar's point, size and scale, so only that frame becomes protected.
Normal cells are positioned by explicit offsets from the bar, so command cells
can sit anywhere in the order. They are hidden on `PLAYER_REGEN_DISABLED` (the last safe moment) and
shown/repositioned on `PLAYER_REGEN_ENABLED`. Rebuilds are deferred during
combat.

### 4.3 Layout

- Bar anchored `TOP` with saved offsets; width = sum of cell widths, so anchoring
  self-centers it.
- Cell width = icon (if shown) + icon padding + `GetStringWidth(text)`.
- Re-layout is debounced with `C_Timer.After(0, ...)`, never in `OnUpdate`.
- Disabled cells are hidden first, so they cannot linger at a stale anchor or
  draw over their neighbour; the bar shrinks to its content.
- Secure command cells are laid out last, by screen position, after the normal
  chain. `Layout` still returns early in combat and is retried on
  `PLAYER_REGEN_ENABLED`.

### 4.4 Data model

```lua
PerchDB = {
  version = 1,
  bar = {
    point = "TOP", relativePoint = "TOP", x = 0, y = -8, locked = true,
    height = 22, padding = 6, spacing = 8, scale = 1,
    hideWhenEmpty = true, mouseoverFade = false, hideInCombat = false,
    clickThrough = false,
    background = { enabled = true, texture = ..., color = { 0, 0, 0, 0.5 } },
    font = { name = "Fonts\\FRIZQT__.TTF", size = 12,
             color = { 1, 1, 1, 1 }, outline = "" },
    iconSize = 14, showIcons = true,
  },
  elements = { ["Perch_Clock"] = { enabled = true }, ["cmd:Reload"] = { enabled = true } },
  order = { "Perch_Clock", ..., "cmd:Reload" },
  commands = { { name = "Reload", macrotext = "/reload", icon = ... } },
  settings = { clock24 = false, clockLocal = false, coordDecimals = 1 },
}
```

Defaults are deep-merged, so older saved variables gain new keys automatically.

### 4.5 Built-ins

| Key | Content | Source |
|---|---|---|
| `Perch_Clock` | `2:32` | `GetGameTime()` (or `date` for local), 1 Hz |
| `Perch_Gold` | `123g 45s` | `GetMoney()`, `PLAYER_MONEY` |
| `Perch_FPS` | `61 fps` | `GetFPS()`, 1 Hz |
| `Perch_Memory` | `41 MB` | `collectgarbage("count")`, 1 Hz |
| `Perch_Durability` | `80%` | `GetInventoryItemDurability`, event |
| `Perch_Bags` | `9/16` | `C_Container` with legacy fallback |
| `Perch_Coords` | `43.2, 71.8` | `C_Map`, 0.2 s throttle, hidden in instances |
| `Perch_XP` | `50%` | `UnitXP`/`UnitXPMax`, hidden at cap |

### 4.6 Options

Native category via `Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory`,
wrapped in `pcall`. The client assigns the numeric category ID when registering;
Perch stores the returned ID (or `category:GetID()`) and never overwrites
`category.ID`, because `Settings.OpenToCategory` needs the real ID. The frame is
built with plain widgets (checkboxes, sliders, buttons) so it also works
standalone if the Settings API differs on 16001; `/perch frame` opens it directly.

Controls: lock, show icons, hide when empty, mouseover fade, hide in combat,
click-through, background, scale, font size, height, spacing, icon size,
background alpha, reset position, reset settings, doctor.

The Settings canvas gets its own chrome-less content frame; the draggable
standalone frame (`/perch frame`) is built lazily and shares the same content
builder. The canvas is created already shown, so `OnShow` never fires on the
first open: widgets initialise their values at creation, and `OpenToCategory`
schedules one `RefreshOptions` after the frame is visible. A scrollable
**Elements** list shows every LDB object Perch knows about (including hidden
launchers) with a checkbox per element, so new plugins can be added to the bar
without slash commands.

---

## 5. Phases

### Phase 0 — skeleton — DONE
- [x] Repo, identity, `.gitignore`, `README`, `CHANGELOG`, `AGENTS.md`, `LICENSE`
- [x] Vendored LibStub, CallbackHandler-1.0, LibDataBroker-1.1
- [x] `Perch.toc` with `## Interface: 16001`
- [x] `tools/package.sh`
- [x] `luajit` harness with 378 assertions
- [x] `/perch doctor`

### Phase 1 — usable bar — DONE (pending in-game verification)
- [x] DB defaults and merge
- [x] Bar frame, layout, drag, styling
- [x] Broker cells, click, tooltip
- [x] LDB discovery, callbacks, poll fallback
- [x] All 8 built-in sources
- [x] Command cells with `/perch cmd`
- [x] Basic options frame
- [x] **First in-game pass: `/perch doctor`** — 1.60.1/70888, Settings id 21,
      `GetFPS` missing, LDB 21 objects
- [x] Fix `FontString:SetText(): Font not set` (hard error on 16001)
- [x] Re-test the bar in the client after the font fix — bar renders, clicks,
      drag and `/perch frame` work
- [x] Secure command cells on `UIParent` (fixes combat `SetWidth` block)
- [x] Options widgets initialise on creation; disabled cells stay hidden
- [x] Verified in the client: command click fires, options show saved values,
      no `ADDON_ACTION_BLOCKED` in combat

### Phase 2 — configuration depth
Settings redesign, in four steps (each ends with gates, a commit and an in-game check):
- [x] 1. Subpages framework, General (six toggles + font selector), LSM embedded
- [x] 2. Elements page: list + detail panel (show/icon/label/value/custom label), order buttons
- [x] 3. Command add/edit/remove (label + macro; icon selector deferred)
- [ ] 4. Appearance: alignment (top left/center/right), colours, texture, solid
      border, drawn end caps (disabled with a textured background)
- [x] Element visibility list: every LDB object, launchers opt-in
- [ ] Element ordering UI (up/down or drag)
- [ ] Per-element label, icon and colour overrides
- [ ] Command editing UI with icon picker
- [ ] Font picker (LibSharedMedia if present, system fonts otherwise)

### Phase 3 — polish
- [ ] Settings profiles and import/export string
- [ ] Optional LibSharedMedia textures
- [ ] Tooltip layout and anchor options
- [ ] README screenshots

### Phase 4 — release
- [ ] CurseForge and/or Wago project, verify `perch` slug
- [ ] Package metadata and versioning scheme
- [ ] Confirm Forever flavor tagging

---

## 6. Assumptions to verify in the client

Record results in `docs/ADDON-NOTES.md`.

1. `Settings` signatures on 16001 (canvas registration, checkbox/slider helpers).
2. `SecureActionButtonTemplate` + `type = "macro"` behaviour.
3. Font paths resolve (`Fonts\\FRIZQT__.TTF`, `Fonts\\ARIALN.TTF`).
4. Texture paths valid in the Forever client.
5. `C_Container` availability vs legacy container functions.
6. `GetInventoryItemDurability` unchanged.
7. Which LDB plugins exist for Forever today.
8. Whether `## Interface: 16001` needs bumping after patches.
9. Whether `C_DateAndTime` exists (doctor probes it; clock uses `GetGameTime`).

---

## 7. In-game validation checklist

1. No Lua errors on login (`/console scriptErrors 1`).
2. Bar appears top-center and shows the built-ins.
3. `/perch doctor` output pasted back for review.
4. Third-party broker plugin appears and updates.
5. Left/right click on a broker cell reaches the plugin.
6. Tooltip renders and hides.
7. `/perch cmd add Test /reload` produces a working button.
8. `/perch unlock` → drag → `/perch lock` → `/reload` keeps position.
9. Options frame opens from `/perch` and from Esc → Options → AddOns.
10. Combat: no errors, command rebuild deferred.
11. UI scale 80% and 120%.
12. Two characters share the same global settings correctly.
