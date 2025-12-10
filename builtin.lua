local mphysx_overrides = {}

local mphysx  = {}

function mphysx.add(name, key, def)
    if name and key and def then
        mphysx_overrides[name] = mphysx_overrides[name] or {}
        mphysx_overrides[name][key] = def
    end
end

function mphysx.del(name, key)
    if name and key and mphysx_overrides[name] then
        mphysx_overrides[name][key] = nil
    end
end

function mphysx.apply(player)
    if not player then return end
    local name = player:get_player_name()
    if not mphysx_overrides[name] then return end

    local list = mphysx_overrides[name]

    local override = {
        speed = 1, speed_walk = 1, speed_climb = 1, speed_crouch = 1, speed_fast = 1,
        jump = 1, gravity = 1,
        liquid_fluidity = 1, liquid_fluidity_smooth = 1, liquid_sink = 1,
        acceleration_default = 1, acceleration_air = 1, acceleration_fast = 1,
        sneak = true, sneak_glitch = false, new_move = true,
    }

    if list["default"] then
        for k,v in pairs(list["default"]) do override[k] = v end
    end

    for id,var in pairs(list) do
        if var and id ~= "default" and id ~= "min" and id ~= "max" and id ~= "force" then
            for k,v in pairs(var) do
                if type(v) == "number" then
                    override[k] = override[k] + v
                elseif type(v) == "boolean" then
                    override[k] = override[k] or v
                else
                    override[k] = v
                end
            end
        end
    end


    if list["min"] then
        for k,v in pairs(list["min"]) do
            if type(v) == "number" then override[k] = math.max(v, override[k]) end
        end
    end

    if list["max"] then
        for k,v in pairs(list["max"]) do
            if type(v) == "number" then override[k] = math.min(v, override[k]) end
        end
    end

    if list["force"] then
        for k,v in pairs(list["force"]) do override[k] = v end
    end

    player:set_physics_override(override)
end

core.register_on_joinplayer(function(player)
    mphysx_overrides[player:get_player_name()] = {}
    mphysx.apply(player)
end)

core.register_on_leaveplayer(function(player)
    if player then mphysx_overrides[player:get_player_name()] = nil end
end)

return mphysx