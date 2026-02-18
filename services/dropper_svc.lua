-- =============================================
-- WRAITH OS - DROPPER SERVICE
-- =============================================
-- Armour equipping via redstone pulses to droppers.
-- Ported from JARVIS modules/droppers.lua

local svc = {}

function svc.main(state, config, utils)
    -- Pulse a redstone output briefly
    local function pulse_redstone(side, color, duration)
        duration = duration or 0.3
        if color then
            local current = rs.getBundledOutput(side)
            rs.setBundledOutput(side, colors.combine(current, color))
            sleep(duration)
            rs.setBundledOutput(side, colors.subtract(rs.getBundledOutput(side), color))
        else
            rs.setOutput(side, true)
            sleep(duration)
            rs.setOutput(side, false)
        end
    end

    -- Find item in storage
    local function find_item_in_storage(item_name)
        for _, store in ipairs(state.storage.peripherals) do
            local ok, list = pcall(store.periph.list)
            if ok and list then
                for slot, item in pairs(list) do
                    if item.name == item_name or item.name:find(item_name, 1, true) then
                        return store, slot, item
                    end
                end
            end
        end
        return nil
    end

    local function push_item_to_dropper(item_name, dropper_name, target_slot)
        local store, slot, item = find_item_in_storage(item_name)
        if not store then
            return false, "Item not found: " .. item_name
        end
        local ok, pushed = pcall(store.periph.pushItems, dropper_name, slot, 1, target_slot)
        if ok and pushed and pushed > 0 then
            return true
        end
        return false, "Failed to push to dropper"
    end

    -- Expose equip function via state
    state.storage.equip_armour = function(set_name)
        set_name = set_name or "default"
        local sets = config.armour_sets or {}
        local armour_set = sets[set_name]

        if not armour_set then
            utils.set_status(state, "Unknown armour set: " .. set_name, colors.red, 3)
            return false
        end

        utils.set_status(state, "Equipping: " .. set_name, colors.cyan, 5)
        utils.add_notification(state, "ARMOUR: Equipping " .. set_name, colors.orange)

        local success_count = 0
        local total = #armour_set.pieces

        for i, piece in ipairs(armour_set.pieces) do
            if piece.dropper_peripheral then
                local ok, err = push_item_to_dropper(piece.item, piece.dropper_peripheral, 1)
                if not ok then
                    utils.add_notification(state,
                        string.format("ARMOUR: Failed %s - %s", piece.label or piece.item, err or "error"),
                        colors.red)
                end
                sleep(0.2)
            end

            pulse_redstone(piece.dropper.side, piece.dropper.color, piece.pulse_duration or 0.3)
            success_count = success_count + 1

            utils.add_notification(state,
                string.format("ARMOUR: Fired %s (%d/%d)", piece.label or piece.item, i, total),
                colors.cyan)

            if i < total then
                sleep(piece.delay or 0.5)
            end
        end

        if success_count == total then
            utils.set_status(state, "Armour equipped!", colors.lime, 3)
        else
            utils.set_status(state, string.format("Armour: %d/%d equipped", success_count, total), colors.orange, 3)
        end

        return success_count == total
    end

    -- Get available sets
    state.storage.get_armour_sets = function()
        local sets = config.armour_sets or {}
        local result = {}
        for name, set in pairs(sets) do
            table.insert(result, {
                name = name,
                label = set.label or utils.capitalize(name),
                piece_count = #set.pieces,
            })
        end
        table.sort(result, function(a, b) return a.name < b.name end)
        return result
    end

    -- Report loaded sets
    local set_count = 0
    for _ in pairs(config.armour_sets or {}) do set_count = set_count + 1 end
    if set_count > 0 then
        utils.add_notification(state, "DROPPERS: " .. set_count .. " armour sets loaded", colors.lime)
    end

    -- Keep alive
    while state.running do
        sleep(1)
    end
end

return svc
