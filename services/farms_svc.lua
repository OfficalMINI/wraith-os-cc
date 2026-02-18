-- =============================================
-- WRAITH OS - FARMS SERVICE
-- =============================================
-- Manages automated farm supply/harvest cycles.
-- Each farm has an input chest (supply seeds/fuel) and
-- output chest (harvest products back to storage).

local svc = {}

function svc.main(state, config, utils)
    local farms = state.farms
    local st = state.storage
    local cfg = config.farms or {}

    local CONFIG_FILE = "wraith/farms_config.lua"
    local cycle_interval = cfg.cycle_interval or 2

    -- Tree client communication via raw modem channels
    local tree_ch = cfg.tree_channels or {ping = 7401, status = 7402, command = 7403, result = 7404}
    local tree_timeout = cfg.tree_heartbeat_timeout or 30
    local tree_modem = nil

    local function setup_tree_modem()
        if tree_modem then return true end
        for _, side in ipairs({"back", "top", "left", "right", "bottom", "front"}) do
            if peripheral.getType(side) == "modem" then
                local m = peripheral.wrap(side)
                if m and m.open and not m.isWireless() then
                    tree_modem = m
                    m.open(tree_ch.ping)
                    m.open(tree_ch.result)
                    return true
                end
            end
        end
        return false
    end

    local function check_tree_client_update(client_version)
        local path = "wraith/clients/tree_client.lua"
        if not fs.exists(path) then return nil end
        local f = fs.open(path, "r")
        if not f then return nil end
        local content = f.readAll()
        f.close()
        if not content then return nil end
        local sum = 0
        for i = 1, #content do
            sum = (sum * 31 + string.byte(content, i)) % 2147483647
        end
        if tostring(sum) ~= client_version then
            return content
        end
        return nil
    end

    local function log(msg)
        utils.add_notification(state, "FARMS: " .. msg, colors.lime)
    end

    -- ========================================
    -- Config persistence
    -- ========================================
    local function load_config()
        if not fs.exists(CONFIG_FILE) then return nil end
        local f = fs.open(CONFIG_FILE, "r")
        if not f then return nil end
        local data = f.readAll()
        f.close()
        if not data or data == "" then return nil end
        local saved = textutils.unserialise(data)
        if saved then return saved end
        local fn = load("return " .. data)
        if fn then
            local ok, result = pcall(fn)
            if ok then return result end
        end
        return nil
    end

    local function save_config()
        local data = {plots = {}, tree_clients_cache = {}}
        for _, plot in ipairs(farms.plots) do
            table.insert(data.plots, {
                name = plot.name,
                type = plot.type,
                input = plot.input,
                output = plot.output,
                enabled = plot.enabled,
                supplies = plot.supplies,
                stats = plot.stats,
                tree_client_ids = plot.tree_client_ids,
                tree_config = plot.tree_config,
            })
        end
        -- Cache known tree clients so they appear in picker after reboot
        for id, c in pairs(farms.tree_clients) do
            data.tree_clients_cache[id] = {
                id = c.id,
                label = c.label,
                fuel = c.fuel,
                fuel_limit = c.fuel_limit,
                rounds = c.rounds,
                saplings = c.saplings,
            }
        end
        -- Serialise first, then write atomically to prevent data loss
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 10 then return end
        -- Write to temp file first, then replace
        local tmp = CONFIG_FILE .. ".tmp"
        local f = fs.open(tmp, "w")
        if f then
            f.write(content)
            f.close()
            if fs.exists(CONFIG_FILE) then fs.delete(CONFIG_FILE) end
            fs.move(tmp, CONFIG_FILE)
        end
    end

    -- ========================================
    -- Peripheral helpers
    -- ========================================
    local storage_patterns = cfg.chest_patterns or {"chest", "shulker", "crate", "drawer", "barrel"}

    local function is_inventory_type(ptype)
        if not ptype then return false end
        local pt = ptype:lower()
        for _, pat in ipairs(storage_patterns) do
            if pt:find(pat, 1, true) then return true end
        end
        return false
    end

    local function get_used_names()
        local used = {}
        -- Storage system assignments
        if st.names then
            for name, role in pairs(st.names) do
                used[name] = role
            end
        end
        -- Loadout buffer barrels
        if state.loadouts and state.loadouts.buffer_barrels then
            for _, barrel_name in pairs(state.loadouts.buffer_barrels) do
                used[barrel_name] = "loadout_buffer"
            end
        end
        -- Farm assignments
        for _, plot in ipairs(farms.plots) do
            if plot.input and plot.input ~= "" then
                used[plot.input] = "farm_input"
            end
            if plot.output and plot.output ~= "" then
                used[plot.output] = "farm_output"
            end
        end
        return used
    end

    farms.list_available_chests = function()
        local used = get_used_names()
        local available = {}
        local all_names = peripheral.getNames()
        for _, name in ipairs(all_names) do
            local ptype = peripheral.getType(name)
            if is_inventory_type(ptype) then
                local p = peripheral.wrap(name)
                if p and p.list then
                    table.insert(available, {
                        name = name,
                        type = ptype,
                        role = used[name] or nil,
                    })
                end
            end
        end
        table.sort(available, function(a, b) return a.name < b.name end)
        return available
    end

    -- ========================================
    -- Farm CRUD
    -- ========================================
    farms.add_farm = function(name)
        local plot = {
            name = name or ("Farm " .. (#farms.plots + 1)),
            type = "custom",
            input = "",
            output = "",
            enabled = false,
            supplies = {},
            stats = {items_supplied = 0, items_harvested = 0, supplied_by_item = {}, harvested_by_item = {}},
            tree_client_ids = {},
            tree_config = nil,
        }
        table.insert(farms.plots, plot)
        save_config()
        log("Created farm: " .. plot.name)
        return true
    end

    farms.remove_farm = function(idx)
        if idx < 1 or idx > #farms.plots then return false end
        local name = farms.plots[idx].name
        table.remove(farms.plots, idx)
        save_config()
        log("Removed farm: " .. name)
        return true
    end

    farms.update_farm = function(idx, field, value)
        local plot = farms.plots[idx]
        if not plot then return false end
        if field == "name" or field == "input" or field == "output" or field == "enabled"
            or field == "type" or field == "tree_config" then
            plot[field] = value
            save_config()
            -- When a chest is assigned to a farm, remove it from storage
            if (field == "input" or field == "output") and value and value ~= "" then
                if st.strip_farm_chests then st.strip_farm_chests() end
            end
            return true
        end
        return false
    end

    farms.link_tree_turtle = function(idx, turtle_id)
        local plot = farms.plots[idx]
        if not plot then return false end
        if not plot.tree_client_ids then plot.tree_client_ids = {} end
        -- Don't add duplicates
        for _, id in ipairs(plot.tree_client_ids) do
            if id == turtle_id then return true end
        end
        table.insert(plot.tree_client_ids, turtle_id)
        save_config()
        log("Linked turtle " .. turtle_id .. " to farm: " .. (plot.name or "?"))
        return true
    end

    farms.unlink_tree_turtle = function(idx, turtle_id)
        local plot = farms.plots[idx]
        if not plot or not plot.tree_client_ids then return false end
        for i, id in ipairs(plot.tree_client_ids) do
            if id == turtle_id then
                table.remove(plot.tree_client_ids, i)
                save_config()
                log("Unlinked turtle " .. turtle_id .. " from farm: " .. (plot.name or "?"))
                return true
            end
        end
        return false
    end

    farms.get_farms = function()
        return farms.plots
    end

    farms.toggle_farm = function(idx)
        local plot = farms.plots[idx]
        if not plot then return false end
        plot.enabled = not plot.enabled
        save_config()
        return plot.enabled
    end

    -- ========================================
    -- Supply rule CRUD
    -- ========================================
    farms.add_supply = function(farm_idx, item_name, display, target, threshold)
        local plot = farms.plots[farm_idx]
        if not plot then return false end
        table.insert(plot.supplies, {
            item = item_name,
            display = display or item_name,
            target = target or 64,
            threshold = threshold or 0,
        })
        save_config()
        return true
    end

    farms.remove_supply = function(farm_idx, supply_idx)
        local plot = farms.plots[farm_idx]
        if not plot then return false end
        if supply_idx < 1 or supply_idx > #plot.supplies then return false end
        table.remove(plot.supplies, supply_idx)
        save_config()
        return true
    end

    farms.update_supply = function(farm_idx, supply_idx, field, value)
        local plot = farms.plots[farm_idx]
        if not plot then return false end
        local supply = plot.supplies[supply_idx]
        if not supply then return false end
        if field == "target" or field == "threshold" or field == "display" or field == "item" then
            supply[field] = value
            save_config()
            return true
        end
        return false
    end

    -- ========================================
    -- Tree Client Tracking
    -- ========================================
    farms.send_tree_command = function(client_id, cmd)
        if not tree_modem then setup_tree_modem() end
        if not tree_modem then return false end
        cmd.target_id = client_id
        tree_modem.transmit(tree_ch.command, tree_ch.result, cmd)
        return true
    end

    local function handle_tree_message(side, channel, reply_ch, msg)
        if type(msg) ~= "table" then return end

        if channel == tree_ch.ping and msg.type == "tree_farmer" then
            -- Register/update tree client from heartbeat
            local id = msg.id
            if not id then return end
            local client = farms.tree_clients[id]
            local is_new = not client
            if is_new then
                client = {id = id}
                farms.tree_clients[id] = client
                log("Tree farmer connected: " .. (msg.label or tostring(id)))
            end
            client.label = msg.label or ("Tree " .. id)
            client.fuel = msg.fuel
            client.fuel_limit = msg.fuel_limit
            client.rounds = msg.rounds
            client.state = msg.state or "idle"
            client.saplings = msg.saplings
            client.progress = msg.progress
            client.last_seen = os.clock()
            client.version = msg.version

            -- Persist new client to cache so it appears in picker after reboot
            if is_new then save_config() end

            -- Send acknowledgement
            if tree_modem then
                tree_modem.transmit(tree_ch.status, tree_ch.ping, {
                    status = "wraith_tree_hub",
                    host_id = os.getComputerID(),
                })
            end

            -- Check for client update
            if msg.version then
                local new_content = check_tree_client_update(msg.version)
                if new_content and tree_modem then
                    log("Update for #" .. tostring(id) .. ": ver " .. tostring(msg.version) .. " outdated, sending " .. #new_content .. "b")
                    tree_modem.transmit(tree_ch.command, tree_ch.result, {
                        action = "update",
                        content = new_content,
                        target_id = id,
                    })
                elseif not new_content then
                    -- Version matches, no update needed (only log occasionally)
                elseif not tree_modem then
                    log("Update for #" .. tostring(id) .. ": no modem to send!")
                end
            else
                log("Turtle #" .. tostring(id) .. " sent no version — can't check update")
            end

        elseif channel == tree_ch.result and msg.action then
            -- Command result from tree client
            local id = msg.id
            if id and farms.tree_clients[id] then
                farms.tree_clients[id].last_seen = os.clock()
                if msg.action == "status_result" then
                    local c = farms.tree_clients[id]
                    c.fuel = msg.fuel
                    c.fuel_limit = msg.fuel_limit
                    c.rounds = msg.rounds
                    c.state = msg.state or c.state
                    c.saplings = msg.saplings
                end
            end
        end
    end

    local function check_tree_timeouts()
        local now = os.clock()
        for id, client in pairs(farms.tree_clients) do
            if client.last_seen and (now - client.last_seen) > tree_timeout then
                if client.state ~= "offline" then
                    client.state = "offline"
                end
            end
        end
    end

    -- ========================================
    -- Harvest: pull from farm output -> storage
    -- ========================================
    local harvest_start_idx = 1  -- rotating index

    local function harvest_farm(plot)
        if not plot.output or plot.output == "" then
            plot.harvest_status = nil  -- no output configured, nothing to report
            return 0
        end
        local out_p = peripheral.wrap(plot.output)
        if not out_p then
            plot.harvest_status = "output offline"
            return 0
        end

        local ok, items = pcall(out_p.list)
        if not ok or not items then
            plot.harvest_status = "read error"
            return 0
        end

        local harvested = 0
        local storage_periphs = st.peripherals or {}
        if #storage_periphs == 0 then
            plot.harvest_status = "no storage"
            return 0
        end

        local harvested_by_item = {}  -- {item_name -> count}
        for slot, item in pairs(items) do
            local remaining = item.count
            local tried = 0
            local si = harvest_start_idx

            while remaining > 0 and tried < #storage_periphs do
                local store = storage_periphs[si]
                local push_ok, pushed = pcall(out_p.pushItems, store.name, slot)
                if push_ok and pushed and pushed > 0 then
                    remaining = remaining - pushed
                    harvested = harvested + pushed
                    harvested_by_item[item.name] = (harvested_by_item[item.name] or 0) + pushed
                    if st.notify_deposited then
                        st.notify_deposited(item.name, item.nbt, pushed, store.name)
                    end
                end
                si = (si % #storage_periphs) + 1
                tried = tried + 1
            end

            harvest_start_idx = (harvest_start_idx % #storage_periphs) + 1
        end

        if harvested > 0 then
            plot.stats.items_harvested = plot.stats.items_harvested + harvested
            plot.harvest_status = string.format("pulled %d", harvested)
            -- Update analytics
            local a = state.analytics
            if a and a.totals then
                a.totals.farm_harvested = (a.totals.farm_harvested or 0) + harvested
            end
            -- Per-item harvest tracking (global + per-farm)
            if not plot.stats.harvested_by_item then plot.stats.harvested_by_item = {} end
            for iname, icount in pairs(harvested_by_item) do
                if a and a.farm_items_harvested then
                    a.farm_items_harvested[iname] = (a.farm_items_harvested[iname] or 0) + icount
                end
                plot.stats.harvested_by_item[iname] = (plot.stats.harvested_by_item[iname] or 0) + icount
            end
        else
            plot.harvest_status = "empty"
        end
        return harvested
    end

    -- ========================================
    -- Supply: push from storage -> farm input
    -- ========================================
    local function supply_farm(plot)
        if not plot.input or plot.input == "" then
            plot.delivery_status = "no input"
            for _, s in ipairs(plot.supplies) do s.status = "no chest" end
            return 0
        end
        if #plot.supplies == 0 then
            plot.delivery_status = "no rules"
            return 0
        end

        local in_p = peripheral.wrap(plot.input)
        if not in_p then
            plot.delivery_status = "input offline"
            for _, s in ipairs(plot.supplies) do s.status = "chest offline" end
            return 0
        end

        -- Count current stock in input chest per item type
        local ok, chest_items = pcall(in_p.list)
        if not ok then
            plot.delivery_status = "read error"
            for _, s in ipairs(plot.supplies) do s.status = "read error" end
            return 0
        end

        local current_stock = {}  -- {item_name -> count}
        if chest_items then
            for _, item in pairs(chest_items) do
                current_stock[item.name] = (current_stock[item.name] or 0) + item.count
            end
        end

        -- Copy pre-computed output_stock map (already aggregated by name across NBT variants)
        -- Must copy since we decrement locally after each pull
        local storage_stock = {}
        for k, v in pairs(st.output_stock or {}) do storage_stock[k] = v end

        local total_supplied = 0
        local any_sending = false
        local any_blocked = false
        local all_met = true

        for _, supply in ipairs(plot.supplies) do
            local current = current_stock[supply.item] or 0
            local deficit = supply.target - current
            if deficit <= 0 then
                supply.status = "target met"
                goto next_supply
            end

            all_met = false

            -- Check storage has enough above threshold
            local in_storage = storage_stock[supply.item] or 0
            if in_storage == 0 then
                supply.status = "not in storage"
                any_blocked = true
                goto next_supply
            end
            if in_storage < supply.threshold + deficit then
                local available = math.max(0, in_storage - supply.threshold)
                supply.status = string.format("low (%d avail)", available)
                any_blocked = true
                goto next_supply
            end

            -- Use cache-aware pull instead of scanning all storage peripherals
            if st.pull_from_storage then
                local pushed = st.pull_from_storage(plot.input, supply.item, nil, deficit, true)
                if pushed > 0 then
                    total_supplied = total_supplied + pushed
                    any_sending = true
                    supply.status = string.format("sent %d", pushed)
                    -- Update local stock tracking for subsequent supply rules
                    storage_stock[supply.item] = (storage_stock[supply.item] or 0) - pushed
                else
                    supply.status = "transfer failed"
                    any_blocked = true
                end
            else
                supply.status = "storage not ready"
                any_blocked = true
            end

            ::next_supply::
        end

        -- Set overall farm delivery status
        if any_sending and any_blocked then
            plot.delivery_status = "partial"
        elseif any_sending then
            plot.delivery_status = "sending"
        elseif all_met then
            plot.delivery_status = "targets met"
        elseif any_blocked then
            plot.delivery_status = "blocked"
        else
            plot.delivery_status = "idle"
        end

        if total_supplied > 0 then
            plot.stats.items_supplied = plot.stats.items_supplied + total_supplied
            local a = state.analytics
            if a and a.totals then
                a.totals.farm_supplied = (a.totals.farm_supplied or 0) + total_supplied
            end
            -- Per-item supply tracking (global + per-farm)
            if not plot.stats.supplied_by_item then plot.stats.supplied_by_item = {} end
            for _, supply in ipairs(plot.supplies) do
                if supply.status and supply.status:find("^sent") then
                    local sent = tonumber(supply.status:match("sent (%d+)"))
                    if sent and sent > 0 then
                        if a and a.farm_items_supplied then
                            a.farm_items_supplied[supply.item] = (a.farm_items_supplied[supply.item] or 0) + sent
                        end
                        plot.stats.supplied_by_item[supply.item] = (plot.stats.supplied_by_item[supply.item] or 0) + sent
                    end
                end
            end
        end
        return total_supplied
    end

    -- ========================================
    -- Main cycle
    -- ========================================
    local function run_farm_cycle()
        for _, plot in ipairs(farms.plots) do
            if plot.type == "tree" then
                -- Tree farms handled via modem, not chest I/O
                local ids = plot.tree_client_ids or {}
                if #ids == 0 then
                    plot.delivery_status = "unlinked"
                else
                    -- Summarise status across all linked turtles
                    local online, total = 0, #ids
                    for _, tid in ipairs(ids) do
                        local c = farms.tree_clients[tid]
                        if c and c.state ~= "offline" then online = online + 1 end
                    end
                    if online > 0 then
                        plot.delivery_status = online .. "/" .. total .. " farming"
                    else
                        -- Find most recent last_seen for offline display
                        local best_seen = 0
                        for _, tid in ipairs(ids) do
                            local c = farms.tree_clients[tid]
                            if c and c.last_seen and c.last_seen > best_seen then
                                best_seen = c.last_seen
                            end
                        end
                        if best_seen > 0 then
                            local ago = math.floor(os.clock() - best_seen)
                            plot.delivery_status = ago < 60 and ("offline " .. ago .. "s") or ("offline " .. math.floor(ago / 60) .. "m")
                        else
                            plot.delivery_status = "en route"
                        end
                    end
                end
                -- Tree farms can also have an output chest to pull logs into storage
                if plot.output and plot.output ~= "" then
                    harvest_farm(plot)
                end
            elseif plot.enabled then
                harvest_farm(plot)
                supply_farm(plot)
            else
                plot.delivery_status = "disabled"
                plot.harvest_status = nil
                for _, s in ipairs(plot.supplies or {}) do
                    s.status = "disabled"
                end
            end
        end
    end

    -- ========================================
    -- Load saved data
    -- ========================================
    local saved = load_config()
    if saved and saved.plots then
        for _, sp in ipairs(saved.plots) do
            -- Restore saved stats or initialize fresh
            if not sp.stats then
                sp.stats = {items_supplied = 0, items_harvested = 0, supplied_by_item = {}, harvested_by_item = {}}
            else
                sp.stats.items_supplied = sp.stats.items_supplied or 0
                sp.stats.items_harvested = sp.stats.items_harvested or 0
                sp.stats.supplied_by_item = sp.stats.supplied_by_item or {}
                sp.stats.harvested_by_item = sp.stats.harvested_by_item or {}
            end
            sp.type = sp.type or "custom"
            -- Migrate old single tree_client_id to tree_client_ids array
            if sp.tree_client_id and not sp.tree_client_ids then
                sp.tree_client_ids = {sp.tree_client_id}
                sp.tree_client_id = nil
            end
            sp.tree_client_ids = sp.tree_client_ids or {}
            table.insert(farms.plots, sp)
        end
    end

    -- Restore cached tree clients (so they appear in picker even before reconnecting)
    if saved and saved.tree_clients_cache then
        for id, c in pairs(saved.tree_clients_cache) do
            local nid = tonumber(id) or id
            farms.tree_clients[nid] = {
                id = c.id or nid,
                label = c.label or ("Tree " .. tostring(nid)),
                fuel = c.fuel,
                fuel_limit = c.fuel_limit,
                rounds = c.rounds,
                saplings = c.saplings,
                state = "offline",
                last_seen = 0,
            }
        end
    end

    -- Rebuild global analytics from persisted per-farm stats
    local a = state.analytics
    if a then
        local total_sup, total_har = 0, 0
        for _, plot in ipairs(farms.plots) do
            local st = plot.stats or {}
            total_sup = total_sup + (st.items_supplied or 0)
            total_har = total_har + (st.items_harvested or 0)
            for iname, icount in pairs(st.supplied_by_item or {}) do
                a.farm_items_supplied[iname] = (a.farm_items_supplied[iname] or 0) + icount
            end
            for iname, icount in pairs(st.harvested_by_item or {}) do
                a.farm_items_harvested[iname] = (a.farm_items_harvested[iname] or 0) + icount
            end
        end
        if a.totals then
            a.totals.farm_supplied = total_sup
            a.totals.farm_harvested = total_har
        end
    end

    farms.ready = true
    local farm_count = #farms.plots
    if farm_count > 0 then
        log(farm_count .. " farm(s) loaded")
    end

    -- Set up wired modem for tree client communication
    setup_tree_modem()

    -- ========================================
    -- Main loop
    -- ========================================
    local tick_timer = os.startTimer(cycle_interval)
    local stats_save_counter = 0
    local STATS_SAVE_INTERVAL = 30  -- save stats every ~60s (30 cycles * 2s)

    while state.running do
        local ev = {coroutine.yield()}

        if ev[1] == "timer" and ev[2] == tick_timer then
            if st.ready and #farms.plots > 0 then
                run_farm_cycle()
                stats_save_counter = stats_save_counter + 1
                if stats_save_counter >= STATS_SAVE_INTERVAL then
                    save_config()
                    stats_save_counter = 0
                end
            end
            check_tree_timeouts()
            tick_timer = os.startTimer(cycle_interval)

        elseif ev[1] == "modem_message" then
            local side, channel, reply_ch, msg = ev[2], ev[3], ev[4], ev[5]
            if channel == tree_ch.ping or channel == tree_ch.result then
                handle_tree_message(side, channel, reply_ch, msg)
            end

        elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            -- Farms wrap peripherals on-demand each cycle
            if not tree_modem then setup_tree_modem() end
        end
    end
end

return svc
