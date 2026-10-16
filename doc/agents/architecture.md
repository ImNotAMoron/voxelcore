# Architecture

How the engine starts, runs and shuts down, and how the big objects relate.
Back to [AGENTS.md](../../AGENTS.md).

## Startup sequence

`src/main.cpp`:

1. `parse_cmdline` → `CoreParameters` (`src/engine/CoreParameters.hpp`).
2. `debug::Logger::init(<userdir>/latest.log)`.
3. `Engine::getInstance().initialize(params)` then `engine.run()`.
4. `Engine::terminate()` → `Engine::close()` (saves settings, tears down in
   reverse order).

`Engine::initialize` (`src/engine/Engine.cpp`) in order:

| Step | What happens |
|---|---|
| Project folder | `--project`, else `user:project`, else `res:project`, else `res/` |
| `EnginePaths` | Mounts virtual FS devices (`res`, `user`, `project`, `core`, `config`, `export`, `script`) |
| `loadProject()` | Reads `project:project.toml` → `Project` (name, `base_packs`, permissions) |
| `Editor`, `CommandsInterpreter` | Devtools + console command parser |
| `Network` | Only if project has `network` permission or `--dbg-server` given |
| `DebuggingServer` | Only with `--dbg-server` |
| `loadSettings()` | `settings.toml` → `EngineSettings` via `SettingsHandler` |
| `EngineController` | World open/create/delete, pack reconfig |
| `initializeClient()` | **Not in headless**: `AssetsManagement`, `WindowControl` → `Window` + `Input`, controls, `gui::GUI` |
| `audio::initialize` | Real OpenAL backend only when not headless |
| `ContentControl` | Owns packs + `Content`; calls `Engine::onContentLoad` after each load |
| `scripting::initialize` | Creates the main Lua state, runs `stdlib.lua`, `classes.lua` |
| `AppScriptsControl` | Starts `--script`/`--test` coroutine; client loads `project:project_client.lua` |

Project permissions (`src/devtools/Project.hpp`): `debugging`, `network`,
`record-audio`, `write-to-user`, `sub-instances`.

## Main loops

`Engine::run()` picks one:

**`Mainloop` (client, `src/engine/Mainloop.cpp`)** — per frame:

```
time.update → engine.applicationTick()   (resume app-script coroutine)
           → engine.updateFrontend()     (assets, hotkeys, audio, gui.act, screen->update, gui.postAct)
           → engine.renderFrame()        (screen->draw, gui->draw)   [skipped when iconified]
           → engine.postUpdate()         (network, post-runnables, Lua post-runnables, debugger)
           → engine.nextFrame()          (swap buffers, poll events)
```

In `--test` mode the client loop quits when the app script finishes.

**`ServerMainloop` (headless, `src/engine/ServerMainloop.cpp`)** — requires
`--script`/`--test` (otherwise "nothing to do"). Each iteration: update time
(fixed step `1/tps` in test mode, wall clock otherwise), update the
`LevelController` if a world is open, `applicationTick`, `postUpdate`, then
sleep to hold `--tps`. Exits when the app script coroutine finishes.

## Screens and world lifecycle

`Screen` (`src/frontend/screens/Screen.hpp`) is the main-loop state:
`MenuScreen` or `LevelScreen`. Set via `Engine::setScreen`; the app client
script gets `on_<screen>_setup` / `on_<screen>_clear` callbacks.

World open flow: Lua `app.open_world` / menu → `EngineController::openWorld`
→ loads world content + `WorldFiles`, checks indices (may show a
`ContentReport` / convert dialog) → builds a `Level` → `Engine::onWorldOpen`
→ the **level consumer** registered by the active main loop:
- client: replaces screen with `LevelScreen(level, localPlayer)`; a null level
  goes back to `MenuScreen`.
- headless: `ServerMainloop::setLevel` creates/destroys a `LevelController`.

`LevelScreen` owns `LevelController`, `PlayerController`, `LevelFrontend`,
`WorldRenderer`, `Hud`, `Decorator`, post-processing. Its `update`:
world timers → animator → `PlayerController::update` →
`LevelController::update(min(delta, 0.2), paused)` → `postUpdate` → HUD →
decorator → renderer. On shutdown it calls `processBeforeQuit()` and
`saveWorld()`.

## Simulation (`src/logic/`)

`LevelController::update`:
1. async pathfinding agents step;
2. per player: configure chunk area, `ChunksController::update` (load /
   generate / unload chunks within `chunks.load-distance` + padding);
3. if not paused: `BlocksController::update` (random ticks, block ticks,
   world tick — all driven by `util::Clock` at 20 TPS split into parts),
   `Entities::update` (physics, components), `on_player_tick` events;
4. `Entities::clean()`.

Scripting hooks fire from these controllers via `scripting::on_*`
(see [scripting.md](scripting.md)).

## Ownership map

```
Engine (singleton, util::ObjectsKeeper)
├─ EnginePaths, Project, SettingsHandler, EngineSettings
├─ ContentControl ── Content (rebuilt on every content load)
├─ EngineController, cmd::CommandsInterpreter, network::Network?
├─ AppScriptsControl (app script coroutine, project client script)
├─ [client] Window, Input, gui::GUI, AssetsManagement, WindowControl
└─ Screen
    └─ LevelScreen
        ├─ LevelController ── Level (World, GlobalChunks, Entities, Players, Inventories, ...)
        │   ├─ ChunksController (WorldGenerator, Lighting)
        │   └─ BlocksController
        ├─ PlayerController
        └─ LevelFrontend, WorldRenderer, Hud, Decorator
```

`util::ObjectsKeeper::keepAlive(...)` holds observer handles (e.g. setting
observers) for the lifetime of the owner — use it when subscribing to
`Setting::observe` from a long-lived object.

## Threading model

- **Main thread**: GL, all Lua states, world/level state, GUI.
- **Workers**: `util::ThreadPool` in `AssetsLoader` (asset decoding),
  `ChunksRenderer` (mesh building), `WorldConverter` (world upgrade);
  `network/Sockets.cpp` threads; `stdin_cmd_reader` thread.
- To get back to the main thread: `Engine::postRunnable(fn)` (queued,
  executed in `postUpdate` via `PostRunnables`, recursive-mutex protected).
  Lua has its own `scripting::process_post_runnables()`.
- World generation runs synchronously on the main thread inside
  `ChunksController`.

## Versions and constants

`src/constants.hpp`: engine version (`ENGINE_VERSION_STRING`), chunk size
(`CHUNK_W=16`, `CHUNK_H=256`, `CHUNK_D=16`), `REGION_FORMAT_VERSION`, special
block ids (`BLOCK_AIR=0`, `BLOCK_OBSTACLE=1`, `BLOCK_STRUCT_AIR=2`,
`BLOCK_VOID`), subprocess limits. `ENGINE_DEBUG_BUILD` is `!NDEBUG`.
