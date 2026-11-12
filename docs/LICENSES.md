# Vendored libraries

Perch embeds three libraries so users do not need to install anything else.
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

## Updating

Replace the file from upstream, then run:

```bash
luajit tests/run.lua
tools/package.sh
```
