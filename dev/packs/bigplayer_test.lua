-- Integration test for the bigplayer pack (needs the pack in user:content).
local util = require "core:tests_util"

-- Builds a stone floor at y=49 and a 1-block step at x=3..6, then pushes
-- the player at it. Returns standing y, final x, final y.
local function walk_into_step(pid, e)
    local stone = block.index("base:stone")
    for x = -3, 8 do
        for z = -3, 3 do
            block.set(x, 49, z, stone)
            for y = 50, 60 do block.set(x, y, z, 0) end
        end
    end
    for x = 3, 6 do
        for z = -3, 3 do block.set(x, 50, z, stone) end
    end
    player.set_pos(pid, 0, 54, 0)
    app.sleep(1.0)
    local _, y0, _ = player.get_pos(pid)
    for i = 1, 30 do
        local v = e.rigidbody:get_vel()
        e.rigidbody:set_vel({4, v[2], 0})
        app.tick()
    end
    for i = 1, 10 do app.tick() end
    local x1, y1, _ = player.get_pos(pid)
    return y0, x1, y1
end

local function open_world(packs, name)
    app.config_packs(packs)
    app.new_world(name, "2019", "core:default")
    app.set_setting("chunks.load-distance", 3)
    app.set_setting("chunks.load-speed", 1)
    local pid = player.create(name)
    player.set_spawnpoint(pid, 0, 100, 0)
    player.set_pos(pid, 0, 100, 0)
    app.sleep_until(function () return block.get(0, 0, 0) ~= -1 end)
    for i = 1, 5 do app.tick() end
    return pid, entities.get(player.get_entity(pid))
end

local function test_big_player()
    local pid, e = open_world({"base", "bigplayer"}, "giant")
    assert(e ~= nil, "player entity missing")
    print("entity def:", e:def_name())
    assert(e:def_name() == "bigplayer:player", "wrong player entity")
    assert(e:has_component("bigplayer:scaler"), "scaler component missing")
    util.check_vec3({1.2, 3.6, 1.2}, e.rigidbody:get_size(), "hitbox")

    local y0, x1, y1 = walk_into_step(pid, e)
    print("big player: standing y, final x, final y:", y0, x1, y1)
    assert(x1 > 4.0, "big player was stopped by a 1-block step")
    util.check_float(y0 + 1.0, y1, "big player height on the step", 0.05)
    app.close_world(false)
    app.delete_world("giant")
end

-- Control: the stock player (step-height 0.5) must be blocked by the step
local function test_base_player()
    local pid, e = open_world({"base"}, "normal")
    print("entity def:", e:def_name())
    assert(e:def_name() == "base:player")
    local y0, x1, y1 = walk_into_step(pid, e)
    print("base player: standing y, final x, final y:", y0, x1, y1)
    assert(x1 < 3.0, "base player should be blocked by the step")
    util.check_float(y0, y1, "base player height", 0.05)
    app.close_world(false)
    app.delete_world("normal")
end

-- Packs can't be reconfigured after content is loaded, so each case runs
-- in its own process. Set CONTROL = true for the stock-player run.
local CONTROL = false

if CONTROL then
    test_base_player()
else
    test_big_player()
end
print("TEST OK")
