# Virtual filesystem, content packs, projects, assets

Back to [AGENTS.md](../../AGENTS.md). User docs: `doc/en/content-packs.md`,
`resources.md`, `assets-preload.md`, `engine-use-recommendations.md`.

## Virtual filesystem (`src/io/`)

All engine and script file access goes through `io::path` — a string of the
form `entry_point:relative/path` (backslashes normalized to `/`). Entry points
map to **devices** (`io/devices/`): `StdfsDevice` (real directory),
`MemoryDevice`, `ZipFileDevice`. Sub-devices alias a folder of another device.

| Entry point | Backing | Writable | Set up in |
|---|---|---|---|
| `res:` | `--res` folder | no | `EnginePaths` ctor |
| `core:` | alias of `res:` | no | `EnginePaths` ctor |
| `user:` | `--dir` folder | only with project permission `write-to-user` | `EnginePaths` ctor |
| `project:` | project folder | no | `EnginePaths` ctor |
| `config:` | `user:config` | yes | `EnginePaths` ctor |
| `export:` | `user:export` | yes | `EnginePaths` ctor |
| `world:` | current world folder (`user:worlds/<name>`) | yes | `setCurrentWorldFolder` |
| `script:` | folder of `--script`/`--test` file | no | `EnginePaths` ctor |
| `<packid>:` | each loaded content pack folder | no | `setEntryPoints` on content load |
| `W.<random>` | mounted/temporary writable devices (e.g. opened zip, `file.mount`) | yes | `EnginePaths::mount` |

Writable check: `EnginePaths::isWriteable` — Lua `file.*` refuses writes
elsewhere. Pack ids in `ContentPack::RESERVED_NAMES` (`res`, `core`, `user`,
`world`, `project`, …) are forbidden.

C++ API (`src/io/io.hpp`): `io::read_string`, `read_bytes`, `read_json`,
`read_toml`, `read_object` (by extension), `write_string`, `write_json`,
`write_binary_json`, `is_regular_file`, `is_directory`, `exists`,
`create_directories`, `remove_all`, `directory_iterator`, `resolve` (to
`std::filesystem::path`). Prefer these over `std::filesystem` for anything
under an entry point.

Well-known files: `user:settings.toml`, `user:controls.toml`,
`user:latest.log`, `user:worlds/`, `user:content/`.

## Projects (`src/devtools/Project.*`)

A project is the "app" running on the engine: `project.toml` with `name`,
`title`, `base_packs`, `permissions`, plus optional `project_client.lua`
(screen setup/clear callbacks). Default project: `res/project/`.
Command line args after a bare `--` (as `--key value` pairs) become project
args, visible to Lua via `__VC_PROJECT_ARGS` (consumed by stdlib).

## Content packs

Packs are searched in (`ContentControl.cpp::default_content_sources`):
`world:content`, `user:content`, `project:content`, `res:content`.
The engine's own `res/` folder is the implicit `core` pack
(`ContentPack::createCore`), always loaded first.

Pack layout (see `res/content/base/`):

```
<pack>/
  package.json          id, title, version, creator, description, dependencies
  content.json          lists of blocks / items / entities / generators to load
  blocks/<name>.json    block definitions          → BlockLoader
  items/<name>.json     item definitions           → ItemLoader
  entities/<name>.json  entity definitions         → EntityLoader
  generators/<name>.toml + <name>.files/          → GeneratorLoader
  block_materials/*.json
  skeletons/ models/ textures/ sounds/ fonts/ shaders/ layouts/ texts/
  scripts/              <block>.lua, <item>.lua, world.lua, hud.lua, content.lua, components/
  modules/              Lua modules for `require "<pack>:<module>"`
  config/               bindings.toml, defaults.toml, user-props.toml
  resources.json        named runtime resources (cameras, post-effect slots)
  resource-aliases.json
  preload.json          assets to load eagerly
```

Content ids are `packid:name` (`base:stone`). A block automatically gets an
item `packid:name.item`. Namespaced custom properties (e.g. `"base:durability"`
in a block JSON) must be declared in some pack's `config/user-props.toml`.

Dependencies (`package.json` `dependencies`): prefix `!` required, `?`
optional, `~` weak; version operators `=,>,<,>=,<=`
(`ContentPack.hpp`, resolved by `PacksManager::assemble`).

## Content loading pipeline

`ContentControl::loadContent()`:

1. `PacksManager::scan()` + `assemble(names)` — resolve dependency order.
2. `EnginePaths::setEntryPoints` — mount `<packid>:` entry points;
   build `ResPaths` (search roots for resources across packs).
3. `ContentBuilder` + `corecontent::setup` (built-in blocks: air, obstacle,
   struct air; core items).
4. For each pack (core first): `ContentLoader(&pack, builder, resPaths).load()`
   → content script, generators, `resources.json`, aliases, block materials,
   units listed in `content.json` (dispatched to `loading/*Loader.cpp`), tags.
5. `builder.build()` → immutable `Content` with `ContentIndices`
   (numeric runtime ids for blocks/items/entities; order depends on packs,
   which is why worlds store `indices.json` and may need conversion).
6. `scripting::on_content_load` (post_content.lua, stdcmd.lua).
7. `ContentLoader::loadScripts` — block/item scripts, world scripts,
   components, then `on_content_loaded`.
8. `Engine::onContentLoad` — editor tools, locales, pack `config/bindings.toml`,
   then `loadAssets()` (client only).

Unit definitions: `Block` (`voxels/Block.hpp`), `ItemDef`
(`items/ItemDef.hpp`), `EntityDef` (`objects/EntityDef.hpp`), `GeneratorDef`
(`world/generator/GeneratorDef.hpp`). Each has a `rt` (runtime) sub-struct
filled after build (ids, funcs sets, cached data) — do not serialize it.

Lua side: `app.reconfig_packs(add, remove)`, `app.config_packs`,
`app.load_content`, `app.reset_content` must be called from the app-script
coroutine; the reload happens between ticks.

## Assets (`src/assets/`, `src/engine/AssetsManagement.*`)

Client only. `AssetsLoader` queues entries by `AssetType` (`TEXTURE`,
`SHADER`, `FONT`, `ATLAS`, `LAYOUT`, `SOUND`, `MODEL`, `SKELETON`,
`POST_EFFECT`, `ANIMATION`) and decodes them on a thread pool; GL uploads
happen in the post-function on the main thread. Results land in `Assets`
(`assets->get<Texture>("name")`). Lookup names are pack-qualified where
relevant (`blocks:stone` texture in the blocks atlas, `base:...`).
`AssetsManagement::update()` drives background loading each frame.
