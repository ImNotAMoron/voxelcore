# Scripting (C++ ↔ LuaJIT)

Back to [AGENTS.md](../../AGENTS.md). User-facing API docs live in
`doc/en/scripting.md` and `doc/en/scripting/**` (mirror in `doc/ru/`).

## Layers

| Layer | Location | Role |
|---|---|---|
| Dispatch API | `src/logic/scripting/scripting.hpp/.cpp`, `scripting_hud.cpp`, `scripting_entities.cpp`, `scripting_world_generation.cpp`, `scripting_functional.cpp` | `scripting::on_*` functions called by engine C++ to fire Lua events; script loading; environments |
| Lua core | `src/logic/scripting/lua/lua_engine.*`, `lua_util.hpp`, `lua_wrapper.hpp`, `lua_commons.hpp` | State creation, `lua::` thin wrappers over the Lua C API (`pushvec3`, `tovec3`, `require_string`, …), events, environments |
| Libraries | `src/logic/scripting/lua/libs/lib*.cpp` | One `luaL_Reg <name>lib[]` table per library |
| Usertypes | `src/logic/scripting/lua/usertypes/` | `Heightmap`, `VoxelFragment`, `Canvas`, `Random`, `PCMStream` (C++ objects as Lua userdata) |
| Lua bootstrap | `res/scripts/*.lua` | stdlib written in Lua |
| Lua modules | `res/modules/**` (`core:` prefix) | Public modules (`core:vector3`, `core:data_buffer`, …) and `internal/` (locked to core) |

## Lua states

`lua::StateType` (`lua_engine.hpp`): `BASE`, `SCRIPT`, `GENERATOR`.

- **Main state** — one per engine; `SCRIPT` when headless, `BASE` on client.
  All content/world/HUD/UI scripts run here, separated by *environments*.
- **Generator states** — one per world generator
  (`scripting_world_generation.cpp`), `GENERATOR` type: only the pure
  libraries (`base64`, `bjson`, `block`, `byteutil`, `crypto`, `file`,
  `generation`, `item`, `json`, `mat4`, `pack`, `quat`, `random`,
  `compression`, `toml`, `utf8`, `vec2/3/4`, `xml`, `yaml`), `ffi` removed,
  `debug` stripped.

Library registration is in `lua_engine.cpp::create_libs`. Libraries opened
only for `BASE`/`SCRIPT`: `assets`, `audio`, `console`, `core`, `gui`,
`input`, `inventory`, `network`, `pathfinding`, `player`, `time`, `world`,
`entities`, `cameras`, and component internals `__skeleton`, `__rigidbody`,
`__transform`. `test` is opened only with `--test`. Some libraries are
composed in Lua (e.g. `gfx.*`, `hud`, `rules`, `session`, `ctypes`) — search
`res/scripts` and `res/modules/internal` before assuming a C++ origin.

`app` (from `libapp.cpp`, registered as `__vc_app`) is a global only in
`SCRIPT` states; otherwise it is injected into the environment of app scripts
by `__vc_start_app_script` in `res/scripts/stdlib.lua`.

## Bootstrap order

1. `lua::create_state` → `luaL_openlibs`, `create_libs`, registry tables,
   usertypes, `__VC_HEADLESS`, `__VC_PROJECT_ARGS`, then
   **`res/scripts/stdmin.lua`** (`vc`, `events`, `require`, script cache).
2. `scripting::initialize` → **`stdlib.lua`** (extended stdlib, coroutines,
   app-script runner, `gui_util`), **`classes.lua`**.
3. On every content load (`scripting::on_content_load`) →
   **`post_content.lua`** (runs with `__vc_app`/`__vc_internals` temporarily
   exposed), then **`stdcmd.lua`** (console commands).
4. Frontend init (`scripting::on_frontend_init`) → **`hud_classes.lua`**.

`res/` itself is loaded as the built-in **`core` pack** (prepended to the
pack list by `ContentControl`), so `res/scripts/world.lua`,
`res/scripts/hud.lua` and `res/scripts/components/*.lua` are simply the core
pack's world/HUD/component scripts, discovered by the same rules as any pack.

## Environments

Each script runs in an environment (a table with `__index = _G`) identified
by an `int` id; C++ holds them as `scriptenv` (`std::shared_ptr<int>` whose
deleter removes the env).

- root env `0` = globals;
- **pack env** (`scripting::create_pack_environment`) — one per content pack,
  sets `PACK_ID`, `PACK_ENV`. Block, item, world, content and HUD scripts of
  a pack are all executed **in this shared env**; collisions between their
  `on_*` callbacks are avoided because `register_event` moves each callback
  into the event bus and clears the global right after the script runs.
  Other top-level globals of those scripts *are* shared pack-wide.
- **child env** (`create_environment(parent)`) — sets `CUR_ENV`; used e.g.
  for the project client script and by `gui` helpers.
- **document env** (`create_doc_environment`) — one per UI layout
  (`UiDocument`), parent = the owning pack env (or root).

`require "pack:name"` loads `pack:modules/name.lua` in that pack's env and
caches it in `package.loaded`. A bare `require "name"` resolves against the
caller's pack. `core:internal/*` modules are locked after startup
(`__vc_lock_internal_modules`).

## Events

Lua-side bus: `events.on(name, fn)`, `events.emit(name, ...)`,
`events.reset`, `events.remove_by_prefix` (`res/modules/internal/events.lua`).

C++ wires script callbacks with `scripting::register_event(env, "on_x",
"<id>")`: if the script defined global `on_x`, it is moved into the bus under
`<id>` and the global is cleared. The returned bool is stored in a
`*FuncsSet` bitfield so C++ can skip dispatch cheaply.

| Script | Discovered at | Event ids |
|---|---|---|
| Block | `<pack>/scripts/<script-name>.lua` | `<block>.placed`, `.broken`, `.interact`, `.update`, `.randupdate`, `.blocktick`, … (`BlockFuncsSet`, `voxels/Block.hpp`) |
| Item | `<pack>/scripts/<script-name>.lua` | `<item>.use`, `.useon`, `.blockbreakby` (`ItemFuncsSet`) |
| World | `<pack>/scripts/world.lua` | `<pack>:.worldopen`, `.worldtick`, `.blockplaced`, `.playertick`, `.chunkpresent`, `.entityspawn`, … (`WorldFuncsSet`) |
| Content | `<pack>/scripts/content.lua` | `<pack>:.onscriptsloading`, `.oncontentloaded` |
| HUD | `<pack>/scripts/hud.lua` | `<pack>:.hudopen`, `.hudrender`, `.hudclose`, `.inventoryinteract` |
| Component | `<pack>/scripts/components/*.lua` | instantiated per entity; see below |
| Layout | `<layout>.xml.lua` next to the XML | `on_open`, `on_close`, `on_progress` in the doc env |

Dispatch example (`scripting.cpp::on_block_common`): emit the block-specific
event if its bit is set, then every pack's world-level `:.block<suffix>`
event if that pack's `worldfuncsset` bit is set.

### Adding a new event (checklist)

1. Add a bit to the relevant `*FuncsSet` struct.
2. `register_event(env, "on_new_thing", prefix + ".newthing")` in the
   matching `scripting::load_*_script`.
3. Declare + implement `scripting::on_new_thing(...)` (push args with
   `lua::push*`, return the arg count from the lambda) using
   `lua::emit_event`.
4. Call it from the C++ logic at the right moment (main thread only).
5. Document it in `doc/en/scripting/events.md` and `doc/ru/scripting/events.md`.

## Entity components

`<pack>/scripts/components/<name>.lua` is compiled once and stored in the
registry chunk table (`lua::CHUNKS_TABLE`) as `<pack>:<name>`. Each entity
instance runs the chunk in a fresh env with `entity`, `ARGS` (from the entity
JSON `components[].args`), `SAVED_DATA` (persisted table); the script defines
callbacks such as `on_save`, `on_update(tps)`, `on_physics_update`,
`on_render`, `on_despawn`, `on_grounded`, `on_fall`, `on_sensor_enter/exit`,
`on_aim_on/off`, `on_attacked`, `on_used`, `on_player_set`
(event callbacks are dispatched from `scripting_entities.cpp`; the per-frame
`on_update`/`on_physics_update`/`on_render` loop lives in Lua,
`res/modules/internal/stdcomp.lua`). Built-in components live in
`res/scripts/components/`. See `doc/en/scripting/ecs.md`.

## Writing a library function

```cpp
// src/logic/scripting/lua/libs/libtime.cpp
#include "api_lua.hpp"
#include "engine/Engine.hpp"

using namespace scripting;   // gives engine, level, content, indices, ...

static int l_delta(lua::State* L) {
    return lua::pushnumber(L, engine->getTime().getDelta());  // returns 1
}

const luaL_Reg timelib[] = {
    {"delta", lua::wrap<l_delta>},
    {nullptr, nullptr}};
```

Rules:
- Name C functions `l_<name>` (or `l_<lib>_<name>`), make them `static`.
- Always register via `lua::wrap<l_fn>` — it turns C++ exceptions into Lua
  errors. Throw `std::runtime_error` for bad input.
- Read args with `lua::tointeger/tonumber/require_string/tovec3/...`;
  validate counts with `lua::check_argc` (in `api_lua.hpp`).
- Return the number of values pushed (`lua::push*` helpers return 1).
- World-dependent functions must handle `scripting::level == nullptr`
  (no world open). Client-only functions must handle headless.
- Convert data trees with `lua::pushvalue(L, dv::value)` / `lua::tovalue`.
- New library: declare `extern const luaL_Reg xlib[];` in `api_lua.hpp`,
  call `openlib(L, "x", xlib)` in `create_libs` under the right state type.
- Then: docs in both languages, `CHANGELOG.md` entry under *New Functions*,
  a test in `dev/tests/`.

## Errors and debugging

- `lua::call` throws `luaerror`; `lua::call_nothrow` logs and returns 0.
  Event handlers use the nothrow path, so a broken script logs an error with
  traceback instead of crashing.
- `print` is overridden (`l_print`) to write to `scripting::output_stream`
  (stdout by default) — this is what vctest captures.
- `--dbg-server <transport>:<port>` enables the debugging server
  (`devtools/DebuggingServer`, protocol in `doc/specs/debugging_protocol.md`).
- In game: the console layout (`res/layouts/console.xml(.lua)`) runs Lua
  and commands registered in `stdcmd.lua` via `console.add_command`.
