# Micropolis for macOS (native port)

**Download (free, notarized):** https://coastandcorp.com/micropolis/

> This repository is published to provide the source code under the GPL.
> Issues are disabled and pull requests are not reviewed.
> For questions, contact app-support@coastandcorp.com.

Distributed for macOS only (Developer ID + notarization). The iPadOS build target is kept in the project but is not distributed.

A modified version of [MicropolisCore](https://github.com/SimHacker/MicropolisCore)
(GPL-3.0). The original C++ simulation engine runs natively; the
WebAssembly/Svelte front end is replaced by SwiftUI.

## Layout
- `Engine/` — C++ engine copied from `packages/micropolis-engine/src`
  (without `emscripten.cpp`, `callback.cpp`). Native-port changes, marked
  "Modified (native port)":
  - `fileio.cpp` loadScenario: `std::string x = NULL` crashed outside Emscripten
  - `micropolis.cpp` constructor: `callback` was uninitialised (crash on macOS)
  - `data_types.h`: `Ptr` is `char *` to match Apple's MacTypes.h
  - `micropolis.cpp` constructor: `mapBase`/`mopBase` were uninitialised too
  - `fileio.cpp`: 32-bit fields (funds, city time, funding %) were read/written
    through 8-byte `long` on 64-bit hosts, corrupting neighbouring fields; the
    funding % were also overwritten with unconverted values
  - `sprite.cpp`: sprites were `malloc`ed but hold a `std::string` (UB) → `new`
  - `evaluate.cpp` voteProblems: off-by-one read/write past `problemVotes`
  - `allocate.cpp` / `micropolis.h`: guard columns/cells around the map so a
    crafted city file with zone centres at the edge cannot corrupt memory
- `Sources/Bridge/MPEngine.{h,mm}` — Objective-C++ wrapper: native Callback,
  tile/sprite/overlay renderer (CGBitmapContext), state accessors.
- `Sources/App/` — SwiftUI app (shared by macOS and iPadOS).
- `Resources/` — tiles, sprites, tool icons, sounds, cities, scenario thumbnails.

## Build
```
xcodegen generate
xcodebuild -scheme Micropolis -destination 'platform=macOS' build
```
Debug launch arguments: `-demoCity haight`, `-demoScenario 5`, `-demoOverlay`.

## Controls
- iPad: one finger builds, two fingers scroll, pinch zooms (Pencil / trackpad OK)
- Mac: click/drag builds, trackpad scroll or right-drag pans, pinch zooms

## License
GPL-3.0 with the Electronic Arts additional terms (see `LICENSE`, `gpl-3.0.txt`).
"Micropolis" is a registered trademark of Micropolis Corporation (Micropolis GmbH)
and is licensed here as a courtesy of the owner under the Micropolis Public Name
License (`MicropolisPublicNameLicense.md`) — non-commercial use only.
