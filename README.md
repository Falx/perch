# Perch

A small, centered LibDataBroker info bar for **World of Warcraft: Forever**.

Perch sits at the top of your screen and turns every LibDataBroker (LDB) plugin
you have into a clickable cell. It also ships its own data sources, so the bar is
useful on day one — the Forever LDB ecosystem is still young.

```
  2:32   123g 45s   61 fps   41 MB   80%   9/16   43.2, 71.8
  clock  gold       fps      memory  dur   bags   coords
```

## Features

- **LDB display** — every data object from any addon shows up automatically,
  including ones loaded later.
- **Built-in sources** — clock, gold, FPS, memory, durability, bags, coordinates, XP.
- **Clickable** — LDB `OnClick` is forwarded, so broker plugins keep their own
  left/right/middle behaviour and tooltips.
- **Command cells** — secure macro buttons (`SecureActionButtonTemplate`), so
  `/cast`, `/use`, `/reload` and addon slash commands work and respect combat.
- **Customizable** — font, size, color, icons, spacing, height, scale, background,
  fade, hide-in-combat, click-through.
- **Native options** — registered in Blizzard's Settings window, plus a standalone
  fallback frame.
- **Diagnostics** — `/perch doctor` prints a paste-ready report about the client
  API, LDB objects and fonts.

## Install

1. Copy the `Perch` folder into
   `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the client (or `/reload`).
3. Enable **Perch** in the AddOns list.

The packaged zip already has the correct `Perch/` root:

```
Interface/AddOns/Perch/Perch.toc
```

## Commands

| Command | Effect |
|---|---|
| `/perch` | Open options (native Settings category, or the standalone frame) |
| `/perch frame` | Toggle the standalone options frame |
| `/perch lock` / `unlock` | Lock or unlock dragging |
| `/perch scale 1.2` | Set bar scale |
| `/perch list` | List elements and their order |
| `/perch enable <key>` / `disable <key>` | Toggle an element |
| `/perch cmd add <name> <macro>` | Add a command cell |
| `/perch cmd del <name>` | Remove a command cell |
| `/perch doctor` | Print diagnostics |
| `/perch dump` | Print saved variables |
| `/perch reset` | Reset all settings |

## Development

Requires `luajit` and `zip`.

```bash
luajit tests/run.lua     # headless API stub, no game required
tools/package.sh         # validates and builds dist/Perch-<version>.zip
```

The test harness stubs the WoW API (`tests/wow_stub.lua`) and loads the addon in
TOC order, so layout math, LDB discovery, saved variables and command routing are
covered without the client. Anything visual or client-specific still needs an
in-game pass — see `/perch doctor`.

On Windows, `scoop install luajit zip` plus Git Bash is enough to run both
commands. A junction keeps the client pointed at the working copy, so edits go
live after `/reload`:

```powershell
cmd /c mklink /J "<WoW>/_forever_/Interface/AddOns/Perch" "<repo>\Perch"
```

The stub raises on `FontString:SetText()` without a font, because 16001 treats
that as a hard error. Do not weaken it.

Design notes and the phase checklist live in [docs/PLAN.md](docs/PLAN.md).

## Scope

Forever only (interface `16001`). No retail or Classic Era compatibility layers.

## License

MIT for Perch's own code. Vendored libraries keep their own licenses:
see [docs/LICENSES.md](docs/LICENSES.md).
