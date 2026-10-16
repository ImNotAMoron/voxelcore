# AGENTS.md — VoxelCore

Guide for AI coding agents working in this repository. Read this first; follow
links into `doc/agents/` for subsystem deep dives.

## What this is

VoxelCore (v0.32, `src/constants.hpp`) is a voxel game engine written in
**C++17**, scripted with **LuaJIT**, rendered with **OpenGL** (GLFW + GLEW),
audio via **OpenAL**. Almost all gameplay lives in Lua content packs; the C++
side provides the engine, world simulation, rendering and ~45 Lua libraries.
It can also run **headless** (no window/GL/audio) for servers and tests.

Upstream: `https://github.com/MihailRis/VoxelCore` (PRs merge into `main`).

## Repository map

| Path | Contents |
|---|---|
| `src/` | Engine sources → static lib `VoxelCoreSrc` (all `*.cpp` globbed) + `main.cpp` → exe `VoxelCore` |
| `src/engine/` | `Engine` singleton, `Mainloop` (client), `ServerMainloop` (headless), paths, assets mgmt |
| `src/logic/` | `LevelController`, `BlocksController`, `ChunksController`, `PlayerController`, `EngineController`, console `CommandsInterpreter` |
| `src/logic/scripting/` | C++↔Lua bridge: `scripting.cpp` (event dispatch), `lua/` (state, wrappers), `lua/libs/lib*.cpp` (Lua libraries), `lua/usertypes/` |
| `src/content/` | Content packs, `ContentLoader` (+ `loading/` per unit type), `ContentBuilder` → immutable `Content` |
| `src/voxels/` `src/lighting/` | Chunks, voxel/block defs, `blocks_agent` templates, pathfinding; light solver |
| `src/world/` | `Level`, `World`, weather; `files/` (save format, regions); `generator/` |
| `src/objects/` `src/physics/` `src/items/` | Entities/players/components, rigidbody & hitboxes, inventories |
| `src/graphics/` | `core/` (GL wrappers, batches, shaders), `render/` (world renderers), `ui/` (GUI tree + XML reader) |
| `src/frontend/` | Screens (`MenuScreen`, `LevelScreen`), HUD, menus, locale, `UiDocument` |
| `src/coders/` `src/data/` `src/io/` | Parsers/encoders (json, toml, yaml, xml, bjson, png, ogg, vcm…), `dv::value`, settings types, virtual FS |
| `src/network/` `src/audio/` `src/window/` `src/devtools/` | Curl/sockets, OpenAL, GLFW window+input+camera, editor/debugger/project/app scripts |
| `res/` | Runtime resources (copied next to the exe on every build): `scripts/` (Lua bootstrap), `modules/` (`core:` Lua modules), `layouts/` (XML UI + `.xml.lua`), `shaders/`, `textures/`, `texts/` (locales), `content/base/` (built-in pack), `project/` (default project) |
| `test/` | GoogleTest unit tests → `VoxelCoreTest` |
| `dev/tests/*.lua` | Engine integration tests run by `vctest` |
| `vctest/` | Test runner that launches `VoxelCore --headless --test <file>` per Lua file |
| `doc/en`, `doc/ru` | User/modder documentation (keep both languages in sync) |
| `doc/specs/` | Binary file-format specs (regions, bjson, vec3, debugging protocol) |
| `doc/agents/` | Agent-oriented deep dives (this guide's companions) |

## Build

Dependencies: glfw3, glew, glm, libpng, zlib, luajit, libvorbis, openal-soft,
EnTT, curl, freetype, openssl (≥3.0), gtest (tests). See `vcpkg.json` and
`README.md` for per-distro packages.

**Windows (MSVC + vcpkg)** — the local checkout is configured this way
(`build/`, generator *Visual Studio 18 2026*, triplet `x64-windows`,
toolchain `C:/vcpkg/scripts/buildsystems/vcpkg.cmake`, tests ON):

```sh
cmake --preset default-vs-msvc-windows        # needs VCPKG_ROOT; only for fresh configure
cmake --build build --config Debug --parallel  # builds VoxelCore, VoxelCoreTest, vctest
```

**Linux / macOS**:

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release -DVOXELENGINE_BUILD_TESTS=ON
cmake --build build --parallel
# or: ./run.sh -b (build), -r (rebuild), -t (run vctest under valgrind)
```

Notes:
- `src/CMakeLists.txt` uses `file(GLOB_RECURSE ...)`. **After adding/removing
  a `.cpp`/`.hpp`, re-run the CMake configure step** (Visual Studio builds
  re-glob via `ZERO_CHECK` only when a CMakeLists changes).
- Post-build copies `res/` next to the binary (`build/Debug/res`, and
  `build/test/res` for gtest). Edit `res/` in the source tree, never the copy.
- Warnings: `/W4` (MSVC) and `-Wall -Wextra` (+extras) — keep new code
  warning-free.

## Test

Two suites — run both before declaring a change done.

```sh
# 1) C++ unit tests (GoogleTest via CTest) — 63 tests
ctest --test-dir build -C Debug                     # multi-config (VS); drop -C on Linux
build/test/Debug/VoxelCoreTest.exe --gtest_filter='Chunk.*'   # single suite

# 2) Engine integration tests (Lua, headless) — 17 tests in dev/tests/
build/vctest/Debug/vctest.exe -e build/Debug/VoxelCore.exe -d dev/tests -r res -u <empty-tmp-dir>
# single Lua test directly:
build/Debug/VoxelCore.exe --headless --test dev/tests/parsing.lua --res res --dir <tmp-dir>
```

Linux paths: `build/VoxelCoreTest`, `build/vctest/vctest`, `build/VoxelCore`.
`network_*` Lua tests need internet. Details: [doc/agents/testing.md](doc/agents/testing.md).

## Run

```sh
build/Debug/VoxelCore.exe --res res --dir <userdir>   # client
VoxelCore --headless --script <file.lua> [--tps 20]    # server / automation
VoxelCore --help                                       # all flags
```

Flags (`src/util/command_line.cpp`): `--res`, `--dir`, `--project`,
`--script`, `--test`, `--headless`, `--stdin-cmd`, `--tps`, `--dbg-server`,
`--log`, `--version`. Logs go to `<userdir>/latest.log`.

## Code conventions

**C++** (`.clang-format`: Google base, 4-space indent, 80 cols, namespace
contents indented, `AlignAfterOpenBracket: BlockIndent` — closing paren on its
own line for wrapped calls). Run `clang-format -i` on touched C++ files only;
don't reformat unrelated code.

- Classes `PascalCase`, methods/members `camelCase`, free functions in
  namespaces `snake_case` (`scripting::on_block_placed`, `io::read_string`).
- Files: one class per `PascalCase.cpp/.hpp`; namespace-of-functions files are
  `snake_case.cpp`. Headers use `#pragma once`.
- Includes are relative to `src/` (`#include "voxels/Chunk.hpp"`).
- Ownership: `std::unique_ptr` members; raw pointers/references for
  non-owning access. Subsystems are reached via `Engine::getInstance()` or the
  `scripting::engine/level/content/...` globals (set during lifecycle).
- Logging: `static debug::Logger logger("module-name");` then
  `logger.info() << ...` / `.warning()` / `.error()`.
- Errors: throw `std::runtime_error` (or domain subclasses like
  `contentpack_error`, `parsing_error`, `initialize_error`). Inside Lua C
  functions, throwing is fine — `lua::wrap<>` converts it to a Lua error.
- Data trees: use `dv::value` (`src/data/dv.hpp`) for JSON/TOML/bjson-like data.
- Paths: use `io::path` with entry points (`res:`, `user:`, `world:`…) and
  `io::` functions — not `std::filesystem` directly — for anything a script or
  content pack can touch. See [content-and-io.md](doc/agents/content-and-io.md).

**Lua** (`res/`, `dev/tests/`): 4-space indent, `snake_case`, modules return a
table; `require "packid:path/module"` (no `.lua`). Engine-internal globals are
prefixed `__vc_` / `__VC_`.

**Commits**: short lowercase imperative subjects, optional `fix:` / `feat:` /
`docs:` prefix (e.g. `fix registry access in generator scripts`).

## Common tasks — where to touch

| Task | Files to change |
|---|---|
| Add a Lua library function | `src/logic/scripting/lua/libs/lib<name>.cpp` (`static int l_x(lua::State*)` + entry in the `luaL_Reg` array, wrapped with `lua::wrap<>`) → `doc/en/scripting/builtins/lib<name>.md` **and** `doc/ru/...` → `CHANGELOG.md` → test in `dev/tests/` |
| Add a new Lua library | new `lib<name>.cpp`, `extern` in `libs/api_lua.hpp`, `openlib` in `lua_engine.cpp::create_libs` (pick the right state type), docs + `doc/*/scripting.md` index |
| Add a block property | field in `src/voxels/Block.hpp`, copy in `Block::cloneTo` (`Block.cpp`), parse in `src/content/loading/BlockLoader.cpp`, expose in `libblock.cpp` if needed, document in `doc/*/block-properties.md` |
| Item / entity property | `items/ItemDef.*` + `loading/ItemLoader.cpp`; `objects/EntityDef.*` + `loading/EntityLoader.cpp`; `doc/*/item-properties.md`, `entity-properties.md` |
| Add a script event | flag in the `*FuncsSet` struct, `register_event(...)` in `scripting.cpp::load_*_script`, a `scripting::on_*` dispatcher called from C++ logic, `doc/*/scripting/events.md` |
| Add a UI element / XML attribute | `src/graphics/ui/elements/`, reader in `gui_xml.cpp`, Lua props in `libgui.cpp`, `doc/*/xml-ui-layouts.md` + `scripting/ui.md` |
| Add an engine setting | struct in `src/settings.hpp`, register in `src/io/settings_io.cpp` (`builder.add("name", &setting)`), UI in `res/layouts/pages/settings_*.xml(.lua)`, locale keys in `res/texts/*.txt` |
| Add a console command | `res/scripts/stdcmd.lua` (`console.add_command`) |
| Change save format | `src/world/files/*`, bump/handle versions (`REGION_FORMAT_VERSION`, `compatibility.cpp`), update `doc/specs/` |
| Add a shader | `res/shaders/*.glslv/.glslf`, shared code in `res/shaders/lib/*.glsl` via `#include <name>` |

## Pitfalls

- **Docs come in pairs**: every user-facing change touches `doc/en/**` *and*
  `doc/ru/**` (same file names). Notable additions also go into `CHANGELOG.md`.
- **Headless mode**: no `Window`, `Input`, `GUI`, assets or audio backend.
  Guard client-only code with `engine.isHeadless()` / null checks; Lua side
  uses `vc.is_client()`.
- **Threads**: GL, Lua and world state are main-thread only. Background workers
  (`util::ThreadPool` in `AssetsLoader`, `ChunksRenderer`, `WorldConverter`;
  network/socket threads) must hand results back via
  `engine.postRunnable(...)`.
- **Lua stack discipline**: every C function returns the number of pushed
  values; `lua::pop` aborts in Debug on underflow. Balance the stack in
  `scripting::*` dispatchers.
- **Generator scripts** run in a *separate* Lua state (`StateType::GENERATOR`)
  without `world`, `player`, `gui`, `ffi`, etc. and with no access to the
  main state's globals. Don't call engine-state libs from them.
- **Content reload** destroys and rebuilds `Content`; never cache
  `Block*`/`ItemDef*`/indices across `ContentControl::loadContent`.
- `res/content/*` is gitignored except `base` — user-installed packs dropped
  there are not part of the repo.
- Static `scripting::*` globals (`level`, `controller`, `blocks`) are null
  outside an open world — check before use in libraries.

## Deep dives

- [doc/agents/architecture.md](doc/agents/architecture.md) — engine lifecycle, loops, screens, controllers, threading
- [doc/agents/scripting.md](doc/agents/scripting.md) — Lua states, environments, libraries, bootstrap, events
- [doc/agents/content-and-io.md](doc/agents/content-and-io.md) — virtual FS, packs, content loading, projects, assets
- [doc/agents/world-and-voxels.md](doc/agents/world-and-voxels.md) — chunks, blocks, lighting, saves, generator, entities, physics
- [doc/agents/rendering-and-ui.md](doc/agents/rendering-and-ui.md) — GL layer, renderers, shaders, GUI/XML, HUD
- [doc/agents/data-and-formats.md](doc/agents/data-and-formats.md) — `dv::value`, coders, settings, streams
- [doc/agents/testing.md](doc/agents/testing.md) — gtest, vctest, CI
