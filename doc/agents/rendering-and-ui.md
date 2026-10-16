# Rendering, shaders, GUI and frontend

Back to [AGENTS.md](../../AGENTS.md). User docs: `doc/en/xml-ui-layouts.md`,
`scripting/ui.md`, `block-models.md`, `vcm.md`, `particles.md`,
`text-styles.md`, `3d-text.md`.

Everything here is **client only** — not created in headless mode.

## Layers

| Layer | Path | Contents |
|---|---|---|
| Window/input | `src/window/` | `Window`, `Input` (keys, mouse, bindings), `Camera`; GLFW backend in `window/detail/` |
| GL core | `src/graphics/core/` | `Shader`, `Texture`, `Atlas`, `Mesh<Vertex>`, `Batch2D/3D`, `LineBatch`, `Framebuffer`, `GBuffer`, `PostProcessing`, `PostEffect`, `Shadows`, `Font`, `DrawContext` (scoped GL state) |
| World rendering | `src/graphics/render/` | `WorldRenderer` (frame orchestration), `ChunksRenderer` + `BlocksRenderer` (chunk meshing on a thread pool), `ModelBatch`, `Skybox`, `ParticlesRenderer`/`Emitter`, `PrecipitationRenderer`, `TextsRenderer`, `HandsRenderer`, `BlockWrapsRenderer`, `Decorator` (ambient effects), `ModelsGenerator` |
| Frontend | `src/frontend/` | `LevelFrontend` (`ContentGfxCache`: per-block texture regions and models), `Hud`, menus, `UiDocument`, `locale` |
| GUI | `src/graphics/ui/` | `GUI` (root, focus, frames), `elements/*` (UINode tree), `gui_xml.cpp` (XML → nodes), `markdown.cpp` |

## Frame (`WorldRenderer::renderFrame`)

Opaque pass → either the **classic** forward path or the **advanced**
deferred path (setting `graphics.advanced-render`: G-buffer, shadow map pass
with `shadows` shader, deferred lighting, SSAO) → skybox, 3D texts, debug
lines, translucent chunk meshes sorted back-to-front, weather → post-effects
(`PostProcessing`, slots from `resources.json` `post-effect-slot`) → hands →
block overlay. HUD/GUI are drawn after by `LevelScreen` / `Engine::renderFrame`.

Chunk meshes are built off-thread by `ChunksRenderer`'s `ThreadPool`
(`BlocksRenderer` reads a snapshot `VoxelsVolume`) and uploaded on the main
thread. A chunk is remeshed when `chunk->flags.modified` is set.

## Shaders (`res/shaders/`)

- Programs are pairs `<name>.glslv` + `<name>.glslf`, loaded as `Shader`
  assets by name (`assets.require<Shader>("main")`).
- Preprocessed by `GLSLExtension` (`src/coders/GLSLExtension.*`):
  `#include <name>` pulls `res/shaders/lib/<name>.glsl`; engine defines and
  `#param` declarations (post-effect parameters settable from Lua
  `gfx.posteffects`) are injected. Setting `debug.do-trace-shaders` dumps
  preprocessed sources.
- Post-effects: `res/shaders/effects/*.glsl` (`default`, `ssao`,
  `deferred_lighting`, …).
- Packs may ship their own `shaders/`.

## GUI

- Tree of `gui::UINode` (`elements/UINode.hpp`): `Container`, `Panel`,
  `Button`, `Label`, `TextBox`, `CheckBox`, `TrackBar`, `Image`, `Canvas`,
  `InventoryView`, `SelectBox`, `SplitBox`, `ModelViewer`, `InlineFrame`,
  `Plotter`, `Menu` (page stack), `Frame`.
- XML tags → readers in `gui_xml.cpp` (`add("button", read_button)`, …).
  Text/tooltip/hint starting with `@` are localization keys
  (`langs::get`, files `res/texts/<locale>.txt`, pack `texts/`).
- Layout files: `res/layouts/*.xml` and pack `layouts/`. A layout `x.xml`
  gets an optional script `x.xml.lua` executed in its own document env
  (`UiDocument`); element ids are accessible as `document.<id>` with
  properties from `libgui.cpp` (`getattr`/`setattr` property tables) and
  `res/modules/internal/gui_util.lua`.
- Menu pages: `res/layouts/pages/*.xml` loaded through the page loader
  (`scripting::create_page_loader`); reusable fragments in
  `res/layouts/templates/` (instantiated with `gui.template(name, params)`,
  defined in Lua in `res/scripts/stdlib.lua`; dialogs like `gui.ask` live in
  `res/modules/internal/gui_util.lua`).
- Attribute expressions like `size-func="..."` / `onclick="..."` are Lua
  snippets compiled in the document env.

### Adding a GUI element / attribute

1. Element class in `src/graphics/ui/elements/` (derive from `UINode` or
   `Container`).
2. Reader in `gui_xml.cpp` (parse attributes; reuse `read_uinode` /
   `read_container_impl` for common ones) + register with `add("tag", ...)`.
3. Lua properties/methods in `libgui.cpp` getattr/setattr tables.
4. Document in `doc/en|ru/xml-ui-layouts.md` and `scripting/ui.md`.

## HUD (`src/frontend/hud.*`)

`Hud` manages inventory screens, block UIs (`ui-layout` block property), the
hotbar, debug panel (`debug_panel.cpp`, F3), pause menu, and pack HUD
scripts (`scripts/hud.lua`). Lua `hud` library = `libhud.cpp` + Lua parts in
`res/scripts/hud_classes.lua`.

## Audio (`src/audio/`)

`audio::` namespace façade; OpenAL backend in `audio/AL/`, `NoAudio` in
headless. Channels (`regular`, `ambient`, `ui`, `music`…), 3D listener set
in `LevelScreen::updateAudio`. Sounds are `.ogg`/`.wav` assets
(`coders/ogg.cpp`, `wav.cpp`); streaming via `PCMStream`.
