# Testing

Back to [AGENTS.md](../../AGENTS.md).

Two independent suites. Both pass on a clean `main` (verified on Windows /
MSVC Debug: **63/63 gtest**, **17/17 vctest**).

## 1. C++ unit tests — GoogleTest (`test/`)

- Built only with `-DVOXELENGINE_BUILD_TESTS=ON` (all CMake presets set it).
- `test/CMakeLists.txt` globs `test/**/*.cpp` into `VoxelCoreTest`, linked
  against `VoxelCoreSrc` + `GTest::gtest_main`; tests are registered with
  CTest via `gtest_discover_tests`. `res/` is copied to `build/test/res`.
- Mirrors `src/` layout: `test/coders/json.cpp` tests `src/coders/json.*`.
- Good targets: pure code (coders, `dv`, `util`, `io::path`, `Chunk`
  encode/decode, generator `SurroundMap`, `StructLayout`). No GL/window/audio
  is available — don't construct `Engine` in unit tests.

```cpp
#include <gtest/gtest.h>
#include "coders/rle.hpp"

TEST(RLE, EncodeDecode) {
    // arrange / act
    EXPECT_EQ(expected, actual);
}
```

Run:

```sh
ctest --test-dir build -C Debug --output-on-failure   # VS multi-config (drop -C on single-config)
build/test/Debug/VoxelCoreTest.exe --gtest_filter='JSON.*'   # Linux: build/test/VoxelCoreTest
```

After adding a new test file re-run CMake configure (glob).
`network/curltest.cpp` fires a real HTTP request but asserts nothing, so it
passes offline too.

## 2. Engine integration tests — Lua + `vctest` (`dev/tests/`, `vctest/`)

`vctest` scans a directory for `*.lua` and, for each file, runs:

```
VoxelCore --headless --test <file> --res <res> --dir <user>/.vctest > output.txt 2>&1
```

A test **passes when the process exits with code 0**. Any uncaught Lua error
(failed `assert`, `error(...)`) terminates the engine with a non-zero code
(observed exit code 3 on Windows), and vctest prints the captured output
(and re-runs under `--memchecker`/`--debugger` if given). The user dir
`.vctest` is wiped after the run; `worlds/` is removed between tests.

In `--headless --test` mode:
- the main state is `SCRIPT` type; the test file is an **app script**
  running as a coroutine with `app` available;
- `app.tick()` advances one engine tick (headless loop uses a fixed step of
  `1/tps`), `app.sleep(sec)` ticks until time passes;
- the `test` library is opened (`libtest.cpp` + `res/modules/internal/test.lua`):
  `test.click`, `test.fill`, `test.press`, `test.find_by_text`,
  `test.find_by_attr` (UI automation, useful in client test runs);
- `script:` entry point = the test file's folder;
- `res/modules/tests_util.lua` (`require "core:tests_util"`) offers
  `create_demo_world(generator)`, `check_vec3`, `check_float`, `check_int`.

Typical test:

```lua
local util = require "core:tests_util"
util.create_demo_world()            -- config_packs({"base"}) + new_world("demo", ...)

local pid = player.create("Tester")
player.set_pos(pid, 0, 100, 0)
for i = 1, 10 do app.tick() end
assert(world.count_chunks() > 0, "chunks were not loaded")

app.close_world(true)
app.delete_world("demo")
```

Run:

```sh
# all
build/vctest/Debug/vctest.exe -e build/Debug/VoxelCore.exe -d dev/tests -r res -u <empty-dir>
# Linux (also see ./run.sh -t which adds valgrind)
build/vctest/vctest -e build/VoxelCore -d dev/tests -r res -u <empty-dir>
# one test, output to console
build/Debug/VoxelCore.exe --headless --test dev/tests/world.lua --res res --dir <tmp-dir>
```

vctest options: `--exe/-e`, `--tests/-d`, `--res/-r` (default `res`),
`--user/-u` (default `.`), `--output-always`, `--memchecker <valgrind>`,
`--debugger "<cmd>"`.

`network_http`, `network_tcp`, `network_udp` need network access (HTTP test
reaches the internet); the default project grants the `network` permission.

### When to add which test

| Change | Add |
|---|---|
| Pure algorithm / parser / data structure in C++ | gtest in `test/<area>/` |
| Lua library function, content loading, world/chunk/entity behaviour, filesystem rules | Lua test in `dev/tests/` |
| Bug fix | a regression test in whichever suite can reproduce it |

## CI (`.github/workflows/`)

| Workflow | Platform | Runs |
|---|---|---|
| `build.yml` → `cmake.yml` | Ubuntu, Release | build + `ctest` |
| `windows.yml` | Windows MSVC (vcpkg, preset `default-vs-msvc-windows`, RelWithDebInfo) | build + `ctest` + vctest |
| `windows-clang.yml` | Windows clang (static vcpkg triplet) | build + vctest |
| `macos.yml` | macOS | build + `ctest` + vctest under lldb |
| `appimage.yml` | Linux AppImage | build + `ctest` + vctest under valgrind |
| `release.yml` | — | packages releases |

Warnings don't fail CI builds. Keep both suites green and avoid tests that
depend on timing, or on random seeds without printing the seed (see
`dev/tests/chunks.lua`).
