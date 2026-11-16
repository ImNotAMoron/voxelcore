-- Scales the entity model by scaling the skeleton root bone.
-- The hitbox is set separately in the entity definition.
local rig = entity.skeleton

local scale = ARGS.scale or 2.0

rig:set_matrix(0, mat4.scale({scale, scale, scale}))
