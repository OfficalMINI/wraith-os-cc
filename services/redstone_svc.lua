-- =============================================
-- WRAITH OS - REDSTONE SERVICE
-- =============================================
-- Named redstone output manager.
-- Ported from JARVIS modules/redstone.lua

local svc = {}

function svc.main(state, config, utils)
    -- Initialize outputs
    for name, _ in pairs(config.redstone_outputs) do
        state.redstone.states[name] = false
    end

    local count = utils.table_size(config.redstone_outputs)
    if count > 0 then
        utils.add_notification(state, "REDSTONE: " .. count .. " outputs registered", colors.lime)
    end

    -- Expose functions via state
    state.redstone.set_output = function(name, on)
        local mapping = config.redstone_outputs[name]
        if not mapping then return false end

        state.redstone.states[name] = on

        if mapping.color then
            local current = rs.getBundledOutput(mapping.side)
            if on then
                rs.setBundledOutput(mapping.side, colors.combine(current, mapping.color))
            else
                rs.setBundledOutput(mapping.side, colors.subtract(current, mapping.color))
            end
        else
            rs.setOutput(mapping.side, on)
        end

        local label = mapping.label or name
        utils.add_notification(state,
            string.format("RS: %s %s", label, on and "ON" or "OFF"),
            on and colors.lime or colors.lightGray)
        return true
    end

    state.redstone.toggle_output = function(name)
        local current = state.redstone.states[name] or false
        return state.redstone.set_output(name, not current)
    end

    state.redstone.get_output = function(name)
        return state.redstone.states[name] or false
    end

    state.redstone.get_all_outputs = function()
        local outputs = {}
        for name, mapping in pairs(config.redstone_outputs) do
            table.insert(outputs, {
                name = name,
                label = mapping.label or utils.capitalize(name),
                side = mapping.side,
                color = mapping.color,
                on = state.redstone.states[name] or false,
            })
        end
        table.sort(outputs, function(a, b) return a.name < b.name end)
        return outputs
    end

    -- Keep alive (event-driven via function calls)
    while state.running do
        sleep(1)
    end
end

return svc
