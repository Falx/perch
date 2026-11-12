# In-game findings

Facts verified in the actual WoW: Forever client. Append findings here and keep
`/perch doctor` in sync.

Format:

```
## YYYY-MM-DD — client 1.60.1 (16001)
- finding
- finding
```

---

## 2026-11-12 — client 1.60.1 build 70888 (16001)

First run on the real client. `/perch doctor` reported:

- `GetBuildInfo()` → version `1.60.1`, build `70888`, TOC `16001`.
- `Settings` API fully present (`RegisterCanvasLayoutCategory`,
  `RegisterAddOnCategory`, `CreateCheckbox`, `CreateSlider`,
  `CreateSliderOptions`). The category registered and got **id 21**, so the
  native options path works; the standalone frame is only a fallback.
- `C_Container`, `C_Map.GetPlayerMapPosition`, `C_DateAndTime`,
  `GetInventoryItemDurability`, `GetGameTime`, `GetMoney` all present.
- `GetFPS` is **missing**; the vanilla-era `GetFramerate` is used instead
  (see `Builtins.lua`).
- Fonts `Fonts\FRIZQT__.TTF` and `Fonts\ARIALN.TTF` resolve.
- LDB sees 21 objects: 8 built-ins plus `BugSack`, `Disenchantry`, `EnhanceQoL`,
  `EnhanceQoL_DamageMeter`, `ForeverFishing`, `HidingBar1`, `Leatrix_Plus`,
  `OneForAll`, `OpenMap`, `Pigeon`, `Spoken`, `TalentsForeverBook`,
  `TomTom-Paste`. Most third-party objects are icon-only launchers.
- `SecureCmdOptionParse` and `InCombatLockdown` present (macro cells not yet
  exercised with a real command).

### Bug found on first run: `FontString:SetText(): Font not set`

The client treats text-before-font as a **hard error**, not a silent no-op:

```
FontString:SetText(): Font not set
[Perch/Element.lua]:94: in function 'RefreshBrokerCell'
[Perch/Broker.lua]:86: in function 'UpdateBrokerCell'
[Perch/Broker.lua]:80: in function 'RegisterBroker'
[Perch/Broker.lua]:60: in function 'ScanBrokers'
[Perch/Broker.lua]:43: in function 'InitBroker'
```

`RefreshBrokerCell` called `SetText` before `SizeCell` applied the font. The
first cell aborted `ScanBrokers`, which aborted `InitBroker` **before the poll
ticker existed**, so only a handful of cells ever registered, no built-ins
appeared, and the bar stayed 1px wide (invisible).

Fixes:

- `ApplyCellFont` runs before any `SetText` (broker cells, command cells, and
  resizing), guarded by a font signature so it is not re-applied every refresh.
- `ScanBrokers` / `UpdateBrokerCell` isolate failures per data object and record
  them for `/perch doctor` (`broker errors:`), so one broken plugin cannot take
  the bar down.
- The poll ticker is created **before** the first scan.
- `/perch doctor` now prints bar state, cell counts, broker failures and layout
  errors.
- `tests/wow_stub.lua` raises on text-before-font (bare font strings only;
  templated ones such as `GameFontNormal` carry a font), so the harness catches
  this class of bug.

Also fixed while in there: command cells had the same text-before-font bug, and
the FPS source now prefers `GetFPS` and falls back to `GetFramerate`.

### Second pass (same build)

- **Bar renders** after the font fix: `bar: shown 1344x22 at TOP/TOP (0, -8)`,
  20 broker cells, 0 broker errors.
- **LDB callback convention:** LibDBIcon calls `obj.OnClick(button, mouse)` /
  `obj.OnEnter(button)` with the *display button*, not the data object. HidingBar
  relies on it (`btn:GetParent()`), so Perch was throwing on hover. Perch now
  passes the cell as the first argument and wraps plugin callbacks in `pcall`
  (failures show up as `broker errors:` in the doctor report).
- **Secure macro buttons need `RegisterForClicks`.** Without
  `cell:RegisterForClicks("AnyUp")` the `SecureActionButtonTemplate` never fires
  `OnClick`, so `/perch cmd` cells silently did nothing.
- **`ClearAllPoints()` on command cells is protected.** Laying out in combat
  produced `ADDON_ACTION_BLOCKED ... Button:ClearAllPoints()` from `Layout`.
  Layout is now skipped while `InCombatLockdown()` and re-run on
  `PLAYER_REGEN_ENABLED`; `hideInCombat` hides the bar directly on
  `PLAYER_REGEN_DISABLED`.
- **`Settings.RegisterCanvasLayoutCategory` embeds the frame as-is.** Passing
  the draggable standalone frame produced a floating pane inside the Settings
  window. The canvas now gets its own chrome-less content frame, and
  `/perch frame` builds the standalone frame lazily (it used to toggle the
  embedded one, which looked like "nothing happens").
- **Launcher objects:** 13 of the 20 objects are icon-only launchers
  (`EnhanceQoL`, `OneForAll`, `OpenMap`, `HidingBar1`, ...). They are now hidden
  by default and opt-in from the options element list.
- `/perch list` now prints every known element with an `[off]` marker.

### Third pass (same build)

- **Root cause of the combat `Button:SetWidth()` block:** a secure button
  anchored into the bar made the *broker cells* protected too. On 16001 an
  addon frame that holds or is anchored to a secure frame becomes protected, so
  `SetWidth` / `ClearAllPoints` on it is refused in combat even though the
  secure button itself was fine. OneForAll documents the same thing in
  `UI/InfoBar.lua` ("the live client does not let a secure button hang on a
  normal one").
  - Command cells now live on **`UIParent`** and are positioned by screen
    coordinates (`GetLeft`/`GetBottom` × effective scale) in `Layout`, never
    anchored to the bar or to a broker cell.
  - They are hidden on `PLAYER_REGEN_DISABLED` (the last moment `Hide` is
    allowed) and shown/repositioned on `PLAYER_REGEN_ENABLED`.
  - `SizeCell` still refuses `SetWidth`/`SetHeight` in combat and sets
    `sizePending`; `ApplyAll` after combat clears it. This is now a belt-and-
    braces guard rather than the main fix.
- **Command buttons need `type` *and* `type1`** on this client, plus
  `macrotext`/`macrotext1`, `useOnKeyDown = false` and `RegisterForClicks("AnyUp")`.
  That is what OneForAll, EnhanceQoL `MountActions` and Blackthornes Farmer use;
  the single `type`/`macrotext` pair alone was not enough.
- **Settings canvas is created already shown**, so `OnShow` never fires on the
  first open. Every option widget read as unchecked/zero until it was touched.
  Widgets now initialise at creation, and `OpenToCategory` schedules one
  `RefreshOptions` after the frame is visible.
- **Disabled broker cells were re-shown by the poll.** `PollBrokers` called
  `RefreshBrokerCell`, which always ended in `cell:Show()`, and `Layout` skipped
  disabled cells without hiding them — so an unticked element stayed visible at
  its stale anchor and drew over its neighbour. `RefreshBrokerCell` now checks
  `IsEnabled` first and hides, and `Layout` hides every cell not in the enabled
  order.
- `/perch doctor` now reports each command cell: shown/hidden, parent, click
  count (`PostClick`), and the macrotext/type it actually carries.

### Still to verify

- Command cell actually fires the macro (`/perch cmd add Test /perch list`).
- Options canvas layout/scroll on the real client; `/perch frame` standalone.
- Tooltips after the callback fix, drag/save, UI scale 80%/120%, second
  character.
- No `ADDON_ACTION_BLOCKED` while pulling a mob with command cells on the bar.
