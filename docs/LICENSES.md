# Vendored libraries

Perch embeds four libraries so users do not need to install anything else.
They keep their own licenses; Perch's MIT license does not cover them.

## LibStub

- File: `Perch/Libs/LibStub/LibStub.lua`
- Version: minor 2
- Source: https://github.com/wowace-clone/LibStub
- License: **Public Domain** (stated in the file header)

## CallbackHandler-1.0

- File: `Perch/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`
- Version: minor 8
- Source: https://github.com/WoWUIDev/Ace3
- License: **MIT** (Ace3 project)

## LibDataBroker-1.1

- File: `Perch/Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua`
- Version: minor 4
- Source: https://github.com/tekkub/libdatabroker-1-1
- License: **MIT**

## LibSharedMedia-3.0

- File: `Perch/Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua`
- Version: minor 12000005 (12.0.0 v5), copied from the BugSack addon in the
  Forever client, where it is known to load
- Source: https://www.curseforge.com/wow/addons/libsharedmedia-3-0
- License: **LGPL v2.1** (stated in the file header). The file is unmodified and
  kept as a separate library file, so users can replace it.
- Needs `C_UIFileAsset.IsKnownFile` (present on 16001; `/perch doctor` probes it).

## Updating

Replace the file from upstream, then run:

```bash
luajit tests/run.lua
tools/package.sh
```
