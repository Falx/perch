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

### Still to verify

- Command cell actually fires the macro (`/perch cmd add Test /perch list`).
- Options canvas layout/scroll on the real client; `/perch frame` standalone.
- Tooltips after the callback fix, drag/save, UI scale 80%/120%, second
  character.
