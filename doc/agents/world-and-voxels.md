# World, voxels, lighting, saves, generation, entities

Back to [AGENTS.md](../../AGENTS.md). Format specs: `doc/specs/`.
User docs: `doc/en/block-properties.md`, `world-generator.md`,
`entity-properties.md`, `rigging.md`.

## Voxels and chunks (`src/voxels/`)

- `voxel` (`voxel.hpp`) = 4 bytes: `blockid_t id` (uint16) + `blockstate`
  (`rotation:3`, `segment:3`, `reserved:2`, `userbits:8`). Convert with
  `blockstate2int` / `int2blockstate`.
- `Chunk` = `CHUNK_W×CHUNK_H×CHUNK_D` = 16×256×16 voxels, indexed by
  `vox_index(x, y, z) = (y * CHUNK_D + z) * CHUNK_W + x` (`constants.hpp`).
  Holds a `Lightmap`, `flags` (`modified` → remesh, `unsaved` → save,
  `ready`, `lighted`, …), block inventories and `blocksMetadata` (block
  fields). After editing voxels call `setModifiedAndUnsaved()`.
- `GlobalChunks` — level-wide map of loaded chunks (`Level::chunks`),
  ref-counted; handles saving and unloading.
- `Chunks` — a player-local square matrix view over loaded chunks around a
  position (`Player::chunks`); used for rendering, raycasts, lighting.
- `blocks_agent` (`blocks_agent.hpp`) — header-only templates working on
  either storage: `get`, `require`, `get_chunk`, `set`, extended (multi-voxel)
  blocks with segments, rotation helpers, raycast. Prefer these over ad-hoc
  index math.
- `Block` (`Block.hpp`) — block definition: model, textures, rotation
  profile, hitboxes, emission, material, flags (`obstacle`,
  `light-passing`, `replaceable`, …), `fields` struct layout, `rt`
  (runtime id, `BlockFuncsSet`, solid flag, …).
- Special ids: `BLOCK_AIR=0`, `BLOCK_OBSTACLE=1`, `BLOCK_STRUCT_AIR=2`,
  `BLOCK_VOID` = missing chunk.

Changing blocks from gameplay code should go through `BlocksController`
(`logic/BlocksController.hpp`): `placeBlock`, `breakBlock`, `updateSides`,
inventories binding — it fires scripting events, updates lighting and
neighbour updates. The Lua `block.set` / `block.place` / `block.destruct`
library functions are the script-side equivalents (`libblock.cpp`).

## Lighting (`src/lighting/`)

4 channels — R, G, B (block light) and S (sky) — 4 bits each, stored in
`Lightmap` per chunk. `Lighting` orchestrates one `LightSolver` per channel:
`prebuildSkyLight`, `buildSkyLight`, `onChunkLoaded`, `onBlockSet`. Only
created for the client player (`LevelController` ctor) — headless levels have
no lighting.

## Level and World (`src/world/`)

- `World` — persistent world meta: name, seed, generator, time/daytime,
  `WorldFiles`, timers. `world.json` in the world folder.
- `Level` — the runtime: `GlobalChunks`, `Inventories`, `PhysicsSolver`,
  `LevelEvents` (C++ event bus: `CHUNK_PRESENT`, `CHUNK_UNLOAD`, …),
  `Entities`, `Players`, `Pathfinding`, cameras, `Environment` (weather).

## Save format (`src/world/files/`)

World folder (`user:worlds/<name>/` → `world:`):

```
world.json        world meta (seed, generator, time, ...)
indices.json      content indices at save time (block/item/entity names → ids)
player.json       players
resources.json    runtime resources
regions/          voxels layer     (REGION_LAYER_VOXELS)
lights/           light cache layer
inventories/      block inventories
entities/         entities
blocksdata/       block fields (metadata)
data/<packid>/    pack data (pack.data_file)
content/          world-local content packs
```

Each layer stores 32×32-chunk region files (`.VOXREG` magic), format version
`REGION_FORMAT_VERSION` (=3) — spec `doc/specs/region_file_spec.md`, chunk
voxel encoding `region_voxels_chunk_spec.md`. `WorldRegions` keeps at most
`MAX_OPEN_REGION_FILES` open. Old formats convert through
`compatibility.cpp` and `WorldConverter` (multithreaded; also remaps ids
when `indices.json` differs from the current `Content` — see
`ContentReport`). **If you change any on-disk format: bump the version, add
a converter, update the spec, and keep reading old saves.**

## Chunk lifecycle

`ChunksController::update` (per player, budgeted by `chunks.load-speed` ms):
pick nearest missing chunk in `Player::chunks` → try load from regions
(`WorldRegions`) → otherwise `WorldGenerator::generate(voxels, x, z)` →
`Lighting::onChunkLoaded` → `LevelEvents::CHUNK_PRESENT` →
`scripting::on_chunk_present`. Unloading triggers save + `on_chunk_remove`.

## World generator (`src/world/generator/`)

Defined by `generators/<name>.toml` + `<name>.files/` (`script.lua`,
`biomes.toml`, `structures.toml`, `fragments/`, …) in a pack; loaded by
`content/loading/GeneratorLoader.cpp` into `GeneratorDef`.

`WorldGenerator` builds `ChunkPrototype`s in stages
(`ChunkPrototypeLevel`: `WIDE_STRUCTS` → `BIOMES` → `HEIGHTMAP` →
`STRUCTURES`) using `SurroundMap` to make sure neighbours reach the needed
stage, then fills voxels (layers, sea level, plants, structures, lines).
Script callbacks (heightmap generation, `place_structures`,
`place_structures_wide`, …) run in a dedicated **generator Lua state**
(`scripting_world_generation.cpp`) with `Heightmap` / `VoxelFragment`
usertypes and the `generation` library. Generation is synchronous on the main
thread. Built-in `core:default` generator lives under `res/generators/`.

## Entities (`src/objects/`, `src/physics/`)

- `Entities` wraps an **EnTT** registry; `entityid_t` UIDs map to
  `entt::entity`. `spawn(def, pos, args, saved)` / `despawn(id)`.
- Components: `Transform`, `Rigidbody` (with `Hitbox`, sensors), skeleton
  (`rigging::Skeleton` in `src/animation/rigging.hpp`, `skeletons/*.json` +
  `.vec3`/`.vcm` models, animation `.vca`), and **script components**
  (`UserComponent` list, see
  [scripting.md](scripting.md#entity-components)).
- `EntityDef` (`entities/<name>.json`): `components`, `hitbox`, `sensors`,
  `blocking`, `skeleton-name`, `save` flags, etc.
- `PhysicsSolver` (`physics/`) — AABB vs voxel collisions, substeps,
  broadphase over nearby solids.
- `Player` (`objects/Player.hpp`) — id, name, position/rotation, cameras,
  inventory, its own `Chunks` view, and an attached entity (`base:player`).
  `Players` holds all players of a level (multiple players can exist even
  in single-player; tests create several).

## Items and inventories (`src/items/`)

`ItemDef` (icon, stack size, placing block, script callbacks), `ItemStack`
(id, count, optional `dv` data), `Inventory` (slots), `Inventories`
(id-indexed registry in `Level`; block inventories are bound to chunk
positions via `Chunk::addBlockInventory`).
