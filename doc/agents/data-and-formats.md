# Data values, coders, settings, streams

Back to [AGENTS.md](../../AGENTS.md).

## `dv::value` (`src/data/dv.hpp`)

The engine's dynamic value type — used for JSON/TOML/YAML/bjson documents,
content definitions, Lua ↔ C++ data exchange, saved entity/component data.

Types (`dv::value_type`): `none`, `number` (double), `boolean`, `integer`
(int64), `object` (`unordered_map<string, value>`), `list`, `bytes`,
`string`.

```cpp
auto obj = dv::object();          // or dv::list()
obj["name"] = "stone";
obj["size"] = 3;
auto& arr = obj.list("faces");    // create nested list
arr.add(1);

if (obj.has("name")) { const std::string& s = obj["name"].asString(); }
int64_t n = obj["size"].asInteger(0);           // with default
obj.at("hitbox").get(def.hitbox);               // optional read into a field (no-op if missing)
for (const auto& [key, val] : obj.asObject()) { ... }
```

`root.at("key").get(field)` is the idiomatic "read if present" pattern in
loaders (`BlockLoader.cpp`). `dv_util.hpp` adds glm vector/matrix
conversions (`dv::get_vec`, `dv::to_value`). Classes that persist implement
`Serializable` (`serialize()` → `dv::value`, `deserialize(const dv::value&)`).

Lua bridge: `lua::pushvalue(L, const dv::value&)` and `lua::tovalue(L, idx)`
(`lua_util.hpp`).

## Coders (`src/coders/`)

| File | API | Notes |
|---|---|---|
| `json.*` | `json::parse(filename, src)`, `json::stringify(value, nice, indent)` | Also used for `.json` content |
| `binary_json.*` | `json::to_binary(value, compress)`, `json::from_binary(ptr, size)` | "bjson", spec `doc/specs/binary_json_spec.md` |
| `toml.*` | `toml::parse`, `toml::stringify`; overloads for `SettingsHandler` | settings, generator defs, project.toml |
| `yaml.*`, `xml.*` | `yaml::parse/stringify`; `xml::parse` → `xml::Document` | XML used by UI layouts |
| `png.*`, `imageio.*` | load/write `ImageData` | |
| `ogg.*`, `wav.*` | PCM decoding for audio | |
| `vec3.*`, `vcm.*`, `obj.*` | 3D model formats | `vec3_model_spec.md`, `doc/en/vcm.md` |
| `gzip.*`, `rle.*`, `compression.*`, `byte_utils.*` | compression and byte (de)serialization | `ByteBuilder` / `ByteReader` |
| `GLSLExtension.*` | shader preprocessor | see rendering doc |
| `syntax_parser.*` | syntax highlighting for the code editor | |
| `vector_fonts.*` | FreeType fonts | |
| `BasicParser.hpp/.inl`, `commons.*` | shared tokenizer base; throws `parsing_error` (has `errorLog()` with line/column) | extend for new text formats |

Adding a format: follow the `parse(filename, source) → dv::value` /
`stringify(const dv::value&)` shape, add a gtest in `test/coders/`, and (if
scripts need it) a Lua library (`libjson.cpp`, `libtoml.cpp`, `libyaml.cpp`
are thin wrappers), plus `io::read_object` extension dispatch if relevant.

## Settings (`src/settings.hpp`, `src/data/setting.hpp`, `src/io/settings_io.*`)

- `EngineSettings` groups structs (`audio`, `display`, `chunks`, `camera`,
  `graphics`, `debug`, `ui`, `network`, `pathfinding`, …) of typed
  settings: `FlagSetting`, `IntegerSetting {def, min, max}`,
  `NumberSetting {def, min, max, format}`, `StringSetting`.
- All are `ObservableSetting<T>`: `get()`, `set()`, `observe(cb, callNow)`
  returning a handle — store it with `keepAlive(...)`.
- `SettingsHandler` (`settings_io.cpp`) maps dotted names
  (`"chunks.load-distance"`) → settings via `builder.addSection(...)` /
  `builder.add("name", &setting)`. (The third `writeable` parameter is
  currently accepted but ignored — don't rely on it for access control.)
  The dotted name is what Lua and `settings.toml` see.
- Persisted to `user:settings.toml`; Lua reads with `app.get_setting(name)`
  / `vc.get_setting`, writes with `app.set_setting` (emits
  `core:setting.<name>.set` event).

## Byte-level structures

- `data/StructLayout` — typed field layouts (used for block `fields`
  metadata and Lua `ctypes`-like access); serialization + compatibility checks
  between layouts.
- `util/Buffer`, `util/data_io.hpp` (endianness helpers `be2h`, `h2le`…),
  `io/memory_istream`, `io/memory_ostream`, `deflate_*stream`.
- Lua `bytearray` / `Bytearray` (`res/modules/internal/bytearray.lua`,
  FFI-backed), `core:data_buffer`, `core:io_stream`.

## Logging (`src/debug/Logger.hpp`)

`static debug::Logger logger("tag");` then `logger.info() << ...;`
(`debug`, `info`, `warning`, `error`). Output: stdout + log file
(`user:latest.log`, `latest.sub<N>.log` for sub-processes).
