local GLIDERFORGE = {}
local REGISTERED_GLIDERS = {}
local HUD_OV_ID = {}
local PLAYERS_GLIDING = {}

local BUILTIN
local function Check_Physics_Engine()
    local has_player_monoids = core.get_modpath("player_monoids") ~= nil
    local has_pova = core.get_modpath("pova") ~= nil
    local has_armorforge = core.get_modpath("armorforge") ~= nil and core.global_exists("armorforge.physics")
    if has_pova then
        return "pova"
    elseif has_player_monoids then
        return "monoids"
    elseif has_armorforge then
        BUILTIN = armorforge.physics
        return "builtin"
    end
    BUILTIN = dofile(core.get_modpath(core.get_current_modname()) .. "/builtin.lua")
    return "builtin"
end

local PHYSICS_ENGINE = Check_Physics_Engine()
-- Empty functions
local set_physics_overrides
local remove_physics_overrides
local PHYSICS_STRING = "gliderforge:glider"
-- Filling functions with the proper physics logic.
if PHYSICS_ENGINE == "pova" then
    
    Set_Physics_Overrides = function(player, overrides)
        local player_name = player:get_player_name()
        pova.add_override(player_name, PHYSICS_STRING, {
            jump    = overrides.jump or 0,
            speed   = overrides.speed,
            gravity = overrides.gravity,
        })
        pova.do_override(player)
    end
    Remove_Physics_Overrides = function(player)
        local player_name = player:get_player_name()
        pova.del_override(player_name, PHYSICS_STRING)
        pova.do_override(player)
    end
elseif PHYSICS_ENGINE == "monoids" then
    Set_Physics_Overrides = function(player, overrides)
        for key, value in pairs(overrides) do
            player_monoids[key]:add_change(player, value, PHYSICS_STRING)
        end
    end
    Remove_Physics_Overrides = function(player)
        for _, key in pairs({"jump", "speed", "gravity"}) do
            player_monoids[key]:del_change(player, PHYSICS_STRING)
        end
    end
else
    Set_Physics_Overrides = function(player, overrides)
        local player_name = player:get_player_name()
        BUILTIN.add(player_name, PHYSICS_STRING, overrides)
        BUILTIN.apply(player)
    end
    Remove_Physics_Overrides = function(player)
        local player_name = player:get_player_name()
        BUILTIN.del(player_name, PHYSICS_STRING)
        BUILTIN.apply(player)
    end
end

local function set_hud_overlay(player, player_name, overlay_def, show)
if not overlay_def or not overlay_def.texture then return end
    if not HUD_OV_ID[player_name] and show == true then
        HUD_OV_ID[player_name] = player:hud_add({
            type = "image",
            text = overlay_def.texture,
            position = overlay_def.position or {x = 0, y = 0},
            scale = overlay_def.scale or {x = -100, y = -100},
            alignment = overlay_def.alignment or {x = 1, y = 1},
            offset = overlay_def.offset or {x = 0, y = 0},
            z_index = overlay_def.z_index or -150,
        })
    elseif HUD_OV_ID[player_name] and show == false then
        player:hud_remove(HUD_OV_ID[player_name])
        HUD_OV_ID[player_name] = nil
    end
end

local function Use_Glider(stack, player, glider_name)
    if type(player) ~= "userdata" then return end
    local pos = player:get_pos()
    local player_name = player:get_player_name()
    local def = REGISTERED_GLIDERS[glider_name]
    if not def then return end

    if not PLAYERS_GLIDING[player_name] then
        local entity = core.add_entity(pos, "gliderforge:" .. glider_name)
        if entity then
            local attach_pos = def.attach_pos or {x=0, y=10, z=0}
            local attach_rot = def.attach_rot or {x=0, y=0, z=0}
            entity:set_attach(player, "", attach_pos, attach_rot)

            if def.textures then
                entity:set_properties({textures = def.textures})
            end

            local phys = def.physics or {}
            local initial = {
                jump    = 0,
                gravity = (phys.gravity_factor or 1.0) * 0.25,
                speed   = phys.base_speed or 1.0,
            }
            Set_Physics_Overrides(player, initial)

            PLAYERS_GLIDING[player_name] = { name = glider_name, entity = entity }
            set_hud_overlay(player, player_name, def.overlay_def, true)

            if def.uses and def.uses > 0 then
                stack:add_wear(65535 / def.uses)
            end
            return stack
        end
    else
        local state = PLAYERS_GLIDING[player_name]
        Remove_Physics_Overrides(player)
        if state and state.entity and state.entity:get_luaentity() then
            state.entity:set_detach()
            state.entity:remove()
        end
        PLAYERS_GLIDING[player_name] = nil
        set_hud_overlay(player, player_name, def.overlay_def, false)
    end
end

local function Safe_Landing(pos)
    local node = core.get_node_or_nil({x = pos.x, y = pos.y - 0.5, z = pos.z})
    if not node then return false end
    local def = core.registered_nodes[node.name]
    if def and (def.walkable or (def.liquidtype ~= "none" and def.damage_per_second <= 0)) then
        return true
    end
    return false
end

local function Glider_Step(self, dtime)
    local isGliding = false
    local player = self.object:get_attach()
    if player and player:is_player() then
        local pos = player:get_pos()
        local player_name = player:get_player_name()
        local state = PLAYERS_GLIDING[player_name]
        local glider_name = state and state.name
        if glider_name then
            local def  = REGISTERED_GLIDERS[glider_name] or {}
            local phys = def.physics or {}

            if not Safe_Landing(pos) then
                isGliding = true
                local vel_y = player:get_velocity().y
                local override = { jump = 0 }

                if vel_y < 0 and vel_y > -3 then
                    override.speed   = (math.abs(vel_y / 2.0) + 1.0) * (phys.glide_boost or 1.0)
                    override.gravity = ((vel_y + 3) / 20) * (phys.gravity_factor or 1.0)
                elseif vel_y <= -3 then
                    override.speed   = 2.5 * (phys.glide_boost or 1.0)
                    override.gravity = -0.1 * (phys.gravity_factor or 1.0)
                    if vel_y < -5 then
                        player:add_velocity({x=0, y=math.min(5, math.abs(vel_y / 10.0)), z=0})
                    end
                else
                    override.speed   = 1.0 * (phys.base_speed or 1.0)
                    override.gravity = 0.25 * (phys.gravity_factor or 1.0)
                end

                Set_Physics_Overrides(player, override)
            end

            if not isGliding then
                -- Cleanup when landing
                Remove_Physics_Overrides(player)

                if state.entity and state.entity:get_luaentity() then
                    state.entity:set_detach()
                    state.entity:remove()
                end

                PLAYERS_GLIDING[player_name] = nil
                set_hud_overlay(player, player_name, def.overlay_def, false)
            end
        end
    end

    if not isGliding then
        self.object:set_detach()
        self.object:remove()
    end
end

core.register_on_leaveplayer(function(player)
    local player_name = player:get_player_name()
    local state = PLAYERS_GLIDING[player_name]
    PLAYERS_GLIDING[player_name] = nil

    Remove_Physics_Overrides(player)

    if state then
        local def = REGISTERED_GLIDERS[state.name]
        if def and def.overlay_def then
            set_hud_overlay(player, player_name, def.overlay_def, false)
        end
        if state.entity and state.entity:get_luaentity() then
            state.entity:set_detach()
            state.entity:remove()
        end
    end
end)

core.register_on_dieplayer(function(player)
    local player_name = player:get_player_name()
    local state = PLAYERS_GLIDING[player_name]
    PLAYERS_GLIDING[player_name] = nil

    Remove_Physics_Overrides(player)

    if state then
        local glider_name = state.name or state
        local def = REGISTERED_GLIDERS[glider_name]
        if def and def.overlay_def then
            set_hud_overlay(player, player_name, def.overlay_def, false)
        end
        if state.entity and state.entity:get_luaentity() then
            state.entity:set_detach()
            state.entity:remove()
        end
    end
end)

core.register_on_player_hpchange(function(player, hp_change, reason)
    local player_name = player:get_player_name()
    if PLAYERS_GLIDING[player_name] and reason.type == "fall" then
        return 0
    end
    return hp_change
end)

-- API

function GLIDERFORGE.register_glider(modname, glider_name, def)
    if REGISTERED_GLIDERS[glider_name] then
        return false
    end
    core.register_tool(modname .. ":" .. glider_name, {
        description = def.description or "Glider",
        inventory_image = def.inventory_image or "[fill:64x64:0,0:#ffffff",
        on_use = function(stack, player)
            return Use_Glider(stack, player, glider_name)
        end,
    })

    local entity_def = def.entity_def or {}
    entity_def.initial_properties = entity_def.initial_properties or {}
    entity_def.initial_properties.immortal = true
    entity_def.initial_properties.static_save = false
    entity_def.initial_properties.collisionbox = {0,0,0,0,0,0}
    entity_def.on_step = Glider_Step

    core.register_entity(modname .. ":" .. glider_name, entity_def)
    
    REGISTERED_GLIDERS[glider_name] = def
    if def.recipe then
        core.register_craft({
            output = modname .. ":" .. glider_name,
            recipe = def.recipe
        })
    end
    return true
end

function GLIDERFORGE.is_gliding(player)
    if not player or not player:is_player() then
        return false
    end
    local player_name = player:get_player_name()
    return PLAYERS_GLIDING[player_name] ~= nil
end

gliderforge = GLIDERFORGE





