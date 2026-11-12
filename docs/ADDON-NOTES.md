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

### Still to verify

- Bar renders after the font fix (re-run pending).
- `SecureActionButtonTemplate` + `type = "macro"` (`/perch cmd add Test /reload`).
- Tooltips, clicks, drag/save, combat deferral, UI scale 80%/120%, second
  character.
