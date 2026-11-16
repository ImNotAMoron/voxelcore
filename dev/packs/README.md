# Example content packs

## bigplayer

Doubles the player's size so blocks look half as big. No engine changes:

- `config/defaults.toml` replaces the player entity (`player-entity`).
- `entities/player.json` doubles the hitbox (`1.2 x 3.6 x 1.2`), raises
  `step-height` to `1.0` (walks up full blocks) and tunes jump/speed.
  The first-person eye height follows the hitbox (1.6 -> 3.2 blocks).
- `scripts/components/scaler.lua` scales the model via the skeleton root bone.

Install: copy `bigplayer/` into `res/content/` (or `<userdir>/content/`) and
enable it for a world.

Test (copy the pack into `<tmp>/content/` first):

```sh
build/VoxelCore --headless --test dev/packs/bigplayer_test.lua --res res --dir <tmp>
```

Set `CONTROL = true` in the test to check that the stock player can't climb
the same step. The model scale can only be seen in a client run: the
skeleton API does nothing in headless mode.
