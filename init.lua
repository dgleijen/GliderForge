
mglide = {}

mglide.registered_gliders = {}
local built_in = dofile(core.get_modpath(core.get_current_modname()) .. "/builtin.lua")
local hanggliding_players = {}

local has_player_monoids = core.get_modpath("player_monoids") ~= nil
local has_pova = core.get_modpath("pova") ~= nil
local has_mphysx = core.get_modpath("mphysx") ~= nil

local function check_physics_engine()
    if has_pova then
        return "pova"
    elseif has_player_monoids then
        return "monoids"
    elseif has_mphysx then
        return "mphysx"
    end
    return "builtin"
end

local physics_engine = check_physics_engine()

local set_physics_overrides
local remove_physics_overrides

if physics_engine == "pova" then
    set_physics_overrides = function(player, overrides)
        local pname = player:get_player_name()
        pova.add_override(pname, "mglide:glider", {
            jump    = overrides.jump or 0,
            speed   = overrides.speed,
            gravity = overrides.gravity,
        })
        pova.do_override(player)
    end
    remove_physics_overrides = function(player)
        local pname = player:get_player_name()
        pova.del_override(pname, "mglide:glider")
        pova.do_override(player)
    end
elseif physics_engine == "monoids" then
    set_physics_overrides = function(player, overrides)
        for key, value in pairs(overrides) do
            player_monoids[key]:add_change(player, value, "mglide:glider")
        end
    end
    remove_physics_overrides = function(player)
        for _, key in pairs({"jump", "speed", "gravity"}) do
            player_monoids[key]:del_change(player, "mglide:glider")
        end
    end
elseif physics_engine == "mphysx" then
    set_physics_overrides = function(player, overrides)
        local pname = player:get_player_name()
        mphysx.add(pname, "mglide:glider", overrides)
        mphysx.apply(player)
    end
    remove_physics_overrides = function(player)
        local pname = player:get_player_name()
        mphysx.del(pname, "mglide:glider")
        mphysx.apply(player)
    end
else
    set_physics_overrides = function(player, overrides)
        local pname = player:get_player_name()
        built_in.add(pname, "mglide:glider", overrides)
        built_in.apply(player)
    end
    remove_physics_overrides = function(player)
        local pname = player:get_player_name()
        built_in.del(pname, "mglide:glider")
        built_in.apply(player)
    end
end

local hud_overlay_ids = {}

function mglide.register_glider(modname, name, def)
    if mglide.registered_gliders[name] then
        core.log("warning", "[mglide] Glider '" .. name .. "' already registered, skipping.")
        return
    end
    core.register_tool(modname .. ":" .. name, {
        description = def.description or "Glider",
        inventory_image = def.inventory_image or "[fill:64x64:0,0:#ffffff]",
        on_use = function(stack, player)
            return mglide.use(stack, player, name)
        end,
    })
    local entity_def = def.entity_def or {}
    entity_def.initial_properties = entity_def.initial_properties or {}
    entity_def.initial_properties.immortal = true
    entity_def.initial_properties.static_save = false
    entity_def.initial_properties.collisionbox = {0,0,0,0,0,0}
    entity_def.on_step = mglide_step
    core.register_entity(modname .. ":" .. name, entity_def)
    mglide.registered_gliders[name] = def
    if def.recipe then
        core.register_craft({
            output = modname .. ":" .. name,
            recipe = def.recipe
        })
    end
    core.log("action", "[mglide] Registered glider: " .. name)
end



local function set_hud_overlay(player, name, overlay_def, show)
if not overlay_def or not overlay_def.texture then return end
    if not hud_overlay_ids[name] and show == true then
        hud_overlay_ids[name] = player:hud_add({
            type = "image",
            text = overlay_def.texture,
            position = overlay_def.position or {x = 0, y = 0},
            scale = overlay_def.scale or {x = -100, y = -100},
            alignment = overlay_def.alignment or {x = 1, y = 1},
            offset = overlay_def.offset or {x = 0, y = 0},
            z_index = overlay_def.z_index or -150,
        })
    elseif hud_overlay_ids[name] and show == false then
        player:hud_remove(hud_overlay_ids[name])
        hud_overlay_ids[name] = nil
    end
end

local function safe_node_below(pos)
    local node = core.get_node_or_nil({x = pos.x, y = pos.y - 0.5, z = pos.z})
    if not node then return false end
    local def = core.registered_nodes[node.name]
    if def and (def.walkable or (def.liquidtype ~= "none" and def.damage_per_second <= 0)) then
        return true
    end
    return false
end

local function mglide_step(self, dtime)
    local gliding = false
    local player = self.object:get_attach("parent")
    if player then
        local pos = player:get_pos()
        local name = player:get_player_name()
        local glider_name = hanggliding_players[name]
        if glider_name then
            local def = mglide.registered_gliders[glider_name] or {}
            local phys = def.physics or {}
            if not safe_node_below(pos) then
                gliding = true
                local vel = player:get_velocity().y
                local override = {jump = 0}
                if vel < 0 and vel > -3 then
                    override.speed   = (math.abs(vel / 2.0) + 1.0) * (phys.glide_boost or 1.0)
                    override.gravity = ((vel + 3) / 20) * (phys.gravity_factor or 1.0)
                elseif vel <= -3 then
                    override.speed   = 2.5 * (phys.glide_boost or 1.0)
                    override.gravity = -0.1 * (phys.gravity_factor or 1.0)
                    if vel < -5 then
                        player:add_velocity({x=0, y=math.min(5, math.abs(vel / 10.0)), z=0})
                    end
                else
                    override.speed   = 1.0 * (phys.base_speed or 1.0)
                    override.gravity = 0.25 * (phys.gravity_factor or 1.0)
                end
                set_physics_overrides(player, override)
            end

            if not gliding then
                remove_physics_overrides(player)
                hanggliding_players[name] = nil
                set_hud_overlay(player, name, def.overlay_def, false) -- hide overlay
            end
        end
    end

    if not gliding then
        self.object:set_detach()
        self.object:remove()
    end
end

function mglide.is_gliding(player)
    if not player or not player:is_player() then
        return false
    end
    return mglide.get_current_glider(player) ~= nil
end

function mglide.get_current_glider(player)
    if not player or not player:is_player() then return nil end
    local name = player:get_player_name()
    return hanggliding_players[name]
end

function mglide.use(stack, player, glider_name)
    if type(player) ~= "userdata" then return end
    local pos = player:get_pos()
    local pname = player:get_player_name()
    local def = mglide.registered_gliders[glider_name]
    if not def then return end

    if not hanggliding_players[pname] then
        local entity = core.add_entity(pos, "mglide:" .. glider_name)
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
            set_physics_overrides(player, initial)

            hanggliding_players[pname] = glider_name
            set_hud_overlay(player, pname, def.overlay_def, true) 

            if def.uses and def.uses > 0 then
                stack:add_wear(65535 / def.uses)
            end
            return stack
        end
    else
        remove_physics_overrides(player)
        hanggliding_players[pname] = nil
        set_hud_overlay(player, pname, def.overlay_def, false) -- hide overlay
    end
end

core.register_on_dieplayer(function(player)
    local name = player:get_player_name()
    local glider_name = hanggliding_players[name]
    hanggliding_players[name] = nil
    remove_physics_overrides(player)
    if glider_name then
        local def = mglide.registered_gliders[glider_name]
        if def and def.overlay_def then
            set_hud_overlay(player, name, def.overlay_def, false)
        end
    end
end)

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    local glider_name = hanggliding_players[name]
    hanggliding_players[name] = nil
    hud_overlay_ids[name] = nil
    remove_physics_overrides(player)
    if glider_name then
        local def = mglide.registered_gliders[glider_name]
        if def and def.overlay_def then
            set_hud_overlay(player, name, def.overlay_def, false)
        end
    end
end)

core.register_on_player_hpchange(function(player, hp_change, reason)
    local name = player:get_player_name()
    if hanggliding_players[name] and reason.type == "fall" then
        return 0, true
    end
    return hp_change
end, true)
