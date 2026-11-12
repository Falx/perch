# Perch — agent notes

Read this before changing anything. `docs/PLAN.md` has the full design and the
phase checklist.

## Hard rules

- **Target: World of Warcraft: Forever only**, interface `16001`. Do not add
  retail/Classic compatibility branches; `## Interface-Multiple` is out of scope.
- Addon folder **must** be `Perch/` and match the TOC name.
- Never prefix with `Broker_` (reserved for LDB plugins) or `Lib` (reserved for
  libraries).
- **No Ace3.** Options use Blizzard's native `Settings` API, feature-detected, with
  a standalone frame fallback. Do not vendor Ace3.
- Saved variables: `PerchDB`. Globals: `Perch_*`. Addon namespace: `_G.Perch`.

## Before every commit

```bash
luajit tests/run.lua     # must be 0 failures
tools/package.sh         # syntax, TOC consistency, stray files, zip
```

`tools/package.sh` fails if a `.lua` under `Perch/` is missing from `Perch.toc`,
so new files must be added to the TOC in load order.

## Load order (Perch.toc)

```
Core -> Bar -> Element -> Command -> Broker -> Builtins -> Doctor -> Config
```

`Core.lua` owns `_G.Perch`, the DB defaults and the `/perch` dispatcher. Every
other file starts with:

```lua
local ADDON, P = ...
P = _G.Perch
```

## Things that bit us already

- **LDB callbacks live on the library, not the object.** Data objects are proxies
  with a metatable; `object.callbacks` does not exist. Register on the library:
  `ldb:RegisterCallback("LibDataBroker_DataObjectCreated", fn)` and
  `ldb:RegisterCallback("LibDataBroker_AttributeChanged", fn)`. Handlers receive
  `(eventName, ...)` — no target prefix.
- **LDB fires attribute callbacks when a proxy field is assigned** (only if the
  value actually changed). Do not fire them manually or the display updates twice.
- **`LibStub` is a callable table, not a function.** Check for nil, then call it
  through `pcall`.
- **Never call `SetText` unconditionally.** Re-setting text on every poll is the
  classic way to make a broker display waste CPU.
- **`arg1` is not available in WoW scripts.** Use the script's own parameters.
- **Attribute changes are blocked in combat** for secure frames; `Command.lua`
  defers rebuilds through `InCombatLockdown()`.

## Test harness

`tests/wow_stub.lua` implements the frame/fontstring/texture API, `C_Timer`,
`Settings`, and the game functions Perch touches. Missing frame fields are `nil`
(no magic no-op fallback) — if a test fails with "attempt to call a nil value",
the client would fail too, so add the method to the stub deliberately.

`tests/run.lua` loads the addon in TOC order, fires `ADDON_LOADED` and
`PLAYER_LOGIN`, and asserts behaviour. Keep it dependency-free.

## Client findings

Record anything verified in the real client in `docs/ADDON-NOTES.md` and update
`/perch doctor` if an API differs from expectations.
