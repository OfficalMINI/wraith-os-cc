-- =============================================
-- WRAITH OS - MASTERMINE SERVICE
-- =============================================
-- Hub discovery, auto mine_levels generation,
-- config sync, status polling.

local svc = {}

function svc.main(state, config, utils)
    local mm = state.mastermine
    local cfg = config.mastermine
    local proto = cfg.protocols

    -- ========================================
    -- Persistence
    -- ========================================
    local SAVE_PATH = "wraith/mastermine_config.lua"

    local function save_config()
        local data = {
            hub_id = mm.hub_id,
            auto_mode = mm.auto_mode,
            ore_table = mm.ore_table,
            mine_levels = mm.mine_levels,
        }
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 5 then return end
        local tmp = SAVE_PATH .. ".tmp"
        local file = fs.open(tmp, "w")
        if file then
            file.write(content)
            file.close()
            if fs.exists(SAVE_PATH) then fs.delete(SAVE_PATH) end
            fs.move(tmp, SAVE_PATH)
        end
    end

    local function load_config()
        if fs.exists(SAVE_PATH) then
            local file = fs.open(SAVE_PATH, "r")
            if file then
                local raw = file.readAll()
                file.close()
                local fn = loadstring("return " .. raw)
                if fn then
                    local ok, data = pcall(fn)
                    if ok and type(data) == "table" then
                        if data.hub_id then mm.hub_id = data.hub_id end
                        if data.auto_mode ~= nil then mm.auto_mode = data.auto_mode end
                        if data.ore_table and #data.ore_table > 0 then
                            mm.ore_table = data.ore_table
                        end
                        if data.mine_levels and #data.mine_levels > 0 then
                            mm.mine_levels = data.mine_levels
                        end
                    end
                end
            end
        end
    end

    -- ========================================
    -- Initialize ore table from defaults
    -- ========================================
    local function init_ore_table()
        if #mm.ore_table == 0 then
            for _, entry in ipairs(cfg.default_ore_table) do
                local ore = {}
                for k, v in pairs(entry) do ore[k] = v end
                table.insert(mm.ore_table, ore)
            end
        else
            -- Merge missing fields from defaults into saved entries (e.g. smelts_to)
            local defaults_by_item = {}
            for _, entry in ipairs(cfg.default_ore_table) do
                defaults_by_item[entry.item] = entry
            end
            local merged_any = false
            for _, ore in ipairs(mm.ore_table) do
                local def = defaults_by_item[ore.item]
                if def then
                    for k, v in pairs(def) do
                        if ore[k] == nil then
                            ore[k] = v
                            merged_any = true
                        end
                    end
                end
            end
            if merged_any then save_config() end
        end
    end

    -- ========================================
    -- Auto mine_levels generation
    -- ========================================
    local function get_stock(item_name)
        -- Use pre-computed output_stock map (rebuilt with item cache, always current)
        local stock_map = state.storage.output_stock
        if stock_map then
            return stock_map[item_name] or 0
        end
        return 0
    end

    -- Get stock for an ore: smelted form (ingot) if it smelts, otherwise raw item
    local function get_ore_stock(ore)
        if ore.smelts_to then
            return get_stock(ore.smelts_to)
        end
        return get_stock(ore.item)
    end

    local function generate_mine_levels()
        local levels = {}  -- {[y] = score}
        local total_score = 0

        for _, ore in ipairs(mm.ore_table) do
            if ore.enabled then
                local stock = get_ore_stock(ore)
                ore.current_stock = stock
                local need = math.max(0, 1 - stock / ore.threshold)
                ore.need_pct = need
                if need > 0 then
                    local y = ore.best_y
                    levels[y] = (levels[y] or 0) + need
                    total_score = total_score + need
                end
            end
        end

        if total_score == 0 then
            -- All stocked — spread evenly across all enabled ore levels
            local enabled_levels = {}
            for _, ore in ipairs(mm.ore_table) do
                if ore.enabled then
                    enabled_levels[ore.best_y] = true
                end
            end
            local count = 0
            for _ in pairs(enabled_levels) do count = count + 1 end
            if count == 0 then return nil end
            local result = {}
            for y in pairs(enabled_levels) do
                table.insert(result, {level = y, chance = 1 / count})
            end
            table.sort(result, function(a, b) return a.level < b.level end)
            return result
        end

        -- Convert to mine_levels format
        local result = {}
        for y, score in pairs(levels) do
            table.insert(result, {
                level = y,
                chance = score / total_score,
            })
        end

        -- Sort by level for consistency
        table.sort(result, function(a, b) return a.level < b.level end)
        return result
    end

    local function levels_changed(new_levels, old_levels)
        if not new_levels or not old_levels then return true end
        if #new_levels ~= #old_levels then return true end
        for i, nl in ipairs(new_levels) do
            local ol = old_levels[i]
            if nl.level ~= ol.level then return true end
            if math.abs(nl.chance - ol.chance) > 0.01 then return true end
        end
        return false
    end

    -- ========================================
    -- Communication
    -- ========================================
    local function send_ping()
        if mm.hub_id then
            rednet.send(mm.hub_id, "ping", proto.ping)
        else
            rednet.broadcast("ping", proto.ping)
        end
    end

    local function send_config_to_hub()
        if not mm.hub_id or not mm.hub_connected then return false end
        if #mm.mine_levels == 0 then return false end
        rednet.send(mm.hub_id, {mine_levels = mm.mine_levels}, proto.config_msg)
        mm.last_sync = os.clock()
        return true
    end

    local function send_command_to_hub(cmd)
        if not mm.hub_id or not mm.hub_connected then return false end
        rednet.send(mm.hub_id, cmd, proto.command)
        return true
    end

    local function handle_status(sender, msg)
        if type(msg) ~= "table" then return end
        mm.hub_id = sender
        mm.hub_connected = true
        mm.hub_last_seen = os.clock()
        mm.mining_on = msg.on or false
        mm.turtles = msg.turtles or {}
        if msg.mine_levels then
            -- Always store hub's actual levels as reference for auto mode
            mm.hub_mine_levels = msg.mine_levels
            if not mm.auto_mode then
                mm.mine_levels = msg.mine_levels
            end
        end
        if msg.hub_config then
            mm.hub_config = msg.hub_config
            -- Initialize map location to mine entrance if not set
            if not mm.map_location and msg.hub_config.mine_entrance then
                mm.map_location = {
                    x = msg.hub_config.mine_entrance.x,
                    z = msg.hub_config.mine_entrance.z,
                }
            end
        end
    end

    local function handle_mine_data(sender, msg)
        if type(msg) ~= "table" then return end
        if msg.available_levels then
            mm.available_levels = msg.available_levels
        elseif msg.level and msg.data then
            mm.mine_data[msg.level] = msg.data
        end
    end

    -- ========================================
    -- Exposed functions
    -- ========================================
    mm.send_command = function(cmd)
        return send_command_to_hub(cmd)
    end

    mm.set_hub = function(id)
        mm.hub_id = tonumber(id)
        mm.hub_connected = false
        save_config()
    end

    mm.toggle_auto = function()
        mm.auto_mode = not mm.auto_mode
        save_config()
    end

    mm.update_ore = function(idx, field, value)
        if mm.ore_table[idx] then
            mm.ore_table[idx][field] = value
            save_config()
        end
    end

    mm.set_ore_enabled = function(idx, enabled)
        if mm.ore_table[idx] then
            mm.ore_table[idx].enabled = enabled
            save_config()
        end
    end

    mm.set_ore_threshold = function(idx, threshold)
        if mm.ore_table[idx] then
            mm.ore_table[idx].threshold = math.max(1, tonumber(threshold) or 64)
            save_config()
        end
    end

    mm.set_ore_best_y = function(idx, y)
        if mm.ore_table[idx] then
            mm.ore_table[idx].best_y = tonumber(y) or 0
            save_config()
        end
    end

    mm.force_sync = function()
        if mm.auto_mode then
            local new_levels = generate_mine_levels()
            if new_levels then
                mm.mine_levels = new_levels
            else
                mm.mine_levels = {}
            end
        end
        send_config_to_hub()
        save_config()
    end

    mm.request_mine_data = function(level)
        if not mm.hub_id or not mm.hub_connected then return false end
        if level then
            rednet.send(mm.hub_id, {level = level}, proto.data_req)
        else
            rednet.send(mm.hub_id, "levels", proto.data_req)
        end
        return true
    end

    -- ========================================
    -- Main event loop (single-loop, no parallel)
    -- ========================================
    -- NOTE: Cannot use parallel.waitForAll inside kernel services!
    -- The kernel's event filter mechanism only delivers events matching
    -- the service's yielded filter. parallel.waitForAll picks the first
    -- non-nil filter from its inner coroutines, so if one wants "timer"
    -- and another wants all events (nil), only timer events get through.
    -- This starves rednet_message delivery. Use timer-based scheduling instead.

    local function run_service_loop()
        local was_connected = false
        mm.ping_count = 0
        mm.last_ev = "init"

        -- Clock-based scheduling (avoids timer ID matching issues)
        local next_ping = os.clock() + 0.5
        local next_sync = os.clock() + cfg.sync_interval
        -- Keep a heartbeat timer ticking so we wake up regularly
        local heartbeat = os.startTimer(1)

        while state.running do
            local ev, p1, p2, p3 = os.pullEvent()
            mm.last_ev = ev
            local now = os.clock()

            -- Handle rednet messages (hub responses)
            if ev == "rednet_message" then
                local sender, msg, protocol = p1, p2, p3
                if protocol == proto.status then
                    handle_status(sender, msg)
                    if mm.hub_connected and not was_connected then
                        was_connected = true
                        -- Immediately sync mine levels on first connection
                        if mm.auto_mode and #mm.mine_levels > 0 then
                            send_config_to_hub()
                        end
                        utils.set_status(state,
                            "MasterMine: Connected to hub #" .. tostring(mm.hub_id), colors.lime, 5)
                    end
                elseif protocol == proto.data_resp then
                    handle_mine_data(sender, msg)
                end
            end

            -- Clock-based ping (runs on ANY event, checks if it's time)
            if now >= next_ping then
                send_ping()
                mm.ping_count = (mm.ping_count or 0) + 1
                next_ping = now + cfg.status_interval

                -- Check hub timeout
                if mm.hub_connected and (now - mm.hub_last_seen > cfg.hub_timeout) then
                    mm.hub_connected = false
                    if was_connected then
                        utils.set_status(state,
                            "MasterMine: Hub connection lost", colors.red, 5)
                        was_connected = false
                    end
                end
            end

            -- Clock-based sync
            if now >= next_sync then
                if mm.auto_mode and state.storage.ready then
                    local new_levels = generate_mine_levels()
                    if new_levels then
                        if levels_changed(new_levels, mm.mine_levels) then
                            mm.mine_levels = new_levels
                            if mm.hub_connected then
                                send_config_to_hub()
                            end
                            save_config()
                        end
                    elseif #mm.mine_levels > 0 then
                        -- All ores met or disabled — clear stale levels
                        mm.mine_levels = {}
                        if mm.hub_connected then
                            send_config_to_hub()
                        end
                        save_config()
                    end
                end
                for _, ore in ipairs(mm.ore_table) do
                    ore.current_stock = get_ore_stock(ore)
                    if ore.threshold > 0 then
                        ore.need_pct = math.max(0, 1 - ore.current_stock / ore.threshold)
                    end
                end
                next_sync = now + cfg.sync_interval
            end

            -- Restart heartbeat timer to keep waking up
            if ev == "timer" and p1 == heartbeat then
                heartbeat = os.startTimer(1)
            end
        end
    end

    -- ========================================
    -- Init & run
    -- ========================================
    load_config()       -- load saved ore_table FIRST (may lack new fields like smelts_to)
    init_ore_table()    -- merge any missing default fields into saved entries

    -- Update stock counts and generate initial mine levels
    if state.storage.ready then
        for _, ore in ipairs(mm.ore_table) do
            ore.current_stock = get_ore_stock(ore)
            if ore.threshold > 0 then
                ore.need_pct = math.max(0, 1 - ore.current_stock / ore.threshold)
            end
        end
        if mm.auto_mode then
            local init_levels = generate_mine_levels()
            if init_levels then
                mm.mine_levels = init_levels
            else
                mm.mine_levels = {}
            end
            save_config()
        end
    end

    local modem = state.network.modem_side
    if modem then
        local hub_str = mm.hub_id and ("#" .. mm.hub_id) or "none (broadcast)"
        utils.set_status(state, "MasterMine: modem=" .. modem .. " hub=" .. hub_str, colors.cyan, 5)
    else
        utils.set_status(state, "MasterMine: No modem!", colors.red, 10)
    end

    if modem then
        run_service_loop()
    else
        while state.running do sleep(5) end
    end
end

return svc
