-- =============================================
-- WRAITH OS - TRANSPORT SERVICE
-- =============================================
-- Manages rail transport network: stations,
-- dispatch coordination, logistics scheduling,
-- and buffer chest item management.

local svc = {}

function svc.main(state, config, utils)
    local tr = state.transport
    local cfg = config.transport
    local proto = cfg.protocols
    local st = state.storage

    -- ========================================
    -- Config Persistence
    -- ========================================
    local config_file = (_G.WRAITH_ROOT or ".") .. "/" .. cfg.save_file:gsub("^wraith/", "")
    if cfg.save_file:find("^wraith/") then
        config_file = (_G.WRAITH_ROOT or ".") .. "/" .. cfg.save_file:sub(8)
    else
        config_file = (_G.WRAITH_ROOT or ".") .. "/" .. cfg.save_file
    end

    local function load_saved_config()
        if fs.exists(config_file) then
            local f = fs.open(config_file, "r")
            if f then
                local data = f.readAll()
                f.close()
                local fn = loadstring("return " .. data)
                if fn then
                    local ok, saved = pcall(fn)
                    if ok and type(saved) == "table" then return saved end
                end
            end
        end
        return nil
    end

    local function save_config_file(data)
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 5 then return false end
        local tmp = config_file .. ".tmp"
        local f = fs.open(tmp, "w")
        if f then
            f.write(content)
            f.close()
            if fs.exists(config_file) then fs.delete(config_file) end
            fs.move(tmp, config_file)
            return true
        end
        return false
    end

    local function save_transport_data()
        local saved = load_saved_config() or {}
        saved.stations = {}
        for id, s in pairs(tr.stations) do
            saved.stations[id] = {
                label = s.label,
                x = s.x, y = s.y, z = s.z,
                is_hub = s.is_hub,
                rules = s.rules,
                switches = s.switches,
                storage_bays = s.storage_bays,
                rail_periph = s.rail_periph,
                rail_face = s.rail_face,
                detector_periph = s.detector_periph,
                detector_face = s.detector_face,
                integrators = s.integrators,
            }
        end
        saved.hub_id = tr.hub_id
        -- Logistics
        saved.buffer_chest = tr.buffer_chest
        saved.allowed_items = tr.allowed_items
        saved.fuel_item = tr.fuel_item
        saved.fuel_per_trip = tr.fuel_per_trip
        saved.station_schedules = tr.station_schedules
        save_config_file(saved)
    end

    -- ========================================
    -- Buffer Chest Management
    -- ========================================

    local function wrap_buffer()
        if tr.buffer_chest then
            local ok, p = pcall(peripheral.wrap, tr.buffer_chest)
            if ok and p and p.list then
                tr.buffer_periph = p
                return true
            else
                tr.buffer_periph = nil
            end
        end
        return false
    end

    tr.list_trapped_chests = function()
        local result = {}
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            local ok, ptype = pcall(peripheral.getType, name)
            if ok and ptype == "minecraft:trapped_chest" then
                table.insert(result, name)
            end
        end
        table.sort(result)
        return result
    end

    tr.set_buffer_chest = function(name)
        tr.buffer_chest = name
        wrap_buffer()
        save_transport_data()
        utils.add_notification(state, "RAIL: Buffer chest set to " .. name, colors.lime)
    end

    tr.clear_buffer_chest = function()
        tr.buffer_chest = nil
        tr.buffer_periph = nil
        save_transport_data()
        utils.add_notification(state, "RAIL: Buffer chest cleared", colors.orange)
    end

    tr.get_buffer_contents = function()
        if not tr.buffer_periph then return {} end
        local ok, list = pcall(tr.buffer_periph.list)
        if ok and list then return list end
        return {}
    end

    -- ========================================
    -- Allow List Management
    -- ========================================

    tr.add_allowed_item = function(item_name, display_name, min_keep)
        -- Check for duplicates
        for _, ai in ipairs(tr.allowed_items) do
            if ai.item == item_name then return false end
        end
        table.insert(tr.allowed_items, {
            item = item_name,
            display_name = display_name or utils.clean_name(item_name),
            min_keep = min_keep or 64,
        })
        save_transport_data()
        return true
    end

    tr.remove_allowed_item = function(idx)
        if tr.allowed_items[idx] then
            table.remove(tr.allowed_items, idx)
            save_transport_data()
            return true
        end
        return false
    end

    tr.update_allowed_item = function(idx, field, value)
        if tr.allowed_items[idx] then
            tr.allowed_items[idx][field] = value
            save_transport_data()
            return true
        end
        return false
    end

    -- ========================================
    -- Schedule Management
    -- ========================================

    tr.add_schedule = function(station_id, schedule)
        if not tr.station_schedules[station_id] then
            tr.station_schedules[station_id] = {}
        end
        table.insert(tr.station_schedules[station_id], {
            type = schedule.type or "delivery",  -- "delivery" or "collection"
            items = schedule.items or {},         -- item names from allow list (delivery only)
            amounts = schedule.amounts or {},     -- {[item_name] = count}
            period = schedule.period or 3600,     -- seconds between runs
            last_run = 0,
            enabled = schedule.enabled ~= false,
        })
        save_transport_data()
        return true
    end

    tr.remove_schedule = function(station_id, idx)
        local scheds = tr.station_schedules[station_id]
        if scheds and scheds[idx] then
            table.remove(scheds, idx)
            if #scheds == 0 then
                tr.station_schedules[station_id] = nil
            end
            save_transport_data()
            return true
        end
        return false
    end

    tr.update_schedule = function(station_id, idx, field, value)
        local scheds = tr.station_schedules[station_id]
        if scheds and scheds[idx] then
            scheds[idx][field] = value
            save_transport_data()
            return true
        end
        return false
    end

    tr.toggle_schedule = function(station_id, idx)
        local scheds = tr.station_schedules[station_id]
        if scheds and scheds[idx] then
            scheds[idx].enabled = not scheds[idx].enabled
            save_transport_data()
            return true
        end
        return false
    end

    -- ========================================
    -- Logistics: Item Stock Helpers
    -- ========================================

    local function get_stock(item_name)
        local stock_map = st.output_stock
        if stock_map then
            return stock_map[item_name] or 0
        end
        return 0
    end

    local function get_available(item_name, min_keep)
        local stock = get_stock(item_name)
        return math.max(0, stock - (min_keep or 0))
    end

    -- Build allowed_items lookup by item name
    local function get_allowed_map()
        local m = {}
        for _, ai in ipairs(tr.allowed_items) do
            m[ai.item] = ai
        end
        return m
    end

    -- ========================================
    -- Logistics: Trip Execution
    -- ========================================

    local trip_in_progress = false

    local function log_trip(trip_type, station_id, items_sent, items_collected)
        local label = tr.stations[station_id] and tr.stations[station_id].label or ("#" .. station_id)
        local entry = {
            type = trip_type,
            station = label,
            station_id = station_id,
            items_sent = items_sent or 0,
            items_collected = items_collected or 0,
            time = os.epoch("utc"),
        }
        table.insert(tr.last_trip_log, 1, entry)
        -- Keep last 20 entries
        while #tr.last_trip_log > 20 do
            table.remove(tr.last_trip_log)
        end
    end

    local function push_items_to_buffer(item_list)
        if not tr.buffer_chest or not st.extract_to_peripheral then return 0 end
        local allowed_map = get_allowed_map()
        local total = 0

        for _, req in ipairs(item_list) do
            local ai = allowed_map[req.item]
            if ai then
                local avail = get_available(req.item, ai.min_keep)
                local to_send = math.min(req.amount or 64, avail)
                if to_send > 0 then
                    local pushed = st.extract_to_peripheral(tr.buffer_chest, req.item, to_send)
                    total = total + pushed
                end
            end
        end
        return total
    end

    local function push_fuel_to_buffer()
        if not tr.buffer_chest or not st.extract_to_peripheral then return 0 end
        local fuel = tr.fuel_item or cfg.fuel_item
        local count = tr.fuel_per_trip or cfg.fuel_per_trip
        if not fuel or count <= 0 then return 0 end
        return st.extract_to_peripheral(tr.buffer_chest, fuel, count)
    end

    tr.execute_trip = function(station_id, trip_type, item_requests)
        if trip_in_progress then return false, "trip in progress" end
        if not tr.hub_id then return false, "no hub" end
        local hub = tr.stations[tr.hub_id]
        if not hub or not hub.online then return false, "hub offline" end
        local dest = tr.stations[station_id]
        if not dest then return false, "station not found" end

        trip_in_progress = true
        local items_pushed = 0

        if trip_type == "delivery" then
            -- Push requested items + fuel to buffer
            if item_requests and #item_requests > 0 then
                items_pushed = push_items_to_buffer(item_requests)
            end
            push_fuel_to_buffer()

            -- Tell hub station to send train with items to destination
            rednet.send(tr.hub_id, {
                action = "request_train",
                target = station_id,
                target_label = dest.label,
                trip_type = "delivery",
            }, proto.station_command)

            log_trip("delivery", station_id, items_pushed, 0)
            utils.add_notification(state,
                string.format("RAIL: Delivery to %s (%d items)", dest.label, items_pushed),
                colors.lime)

        elseif trip_type == "collection" then
            -- Push fuel only (no items — train goes empty to collect)
            push_fuel_to_buffer()

            -- Tell hub station to send empty train to destination for pickup
            rednet.send(tr.hub_id, {
                action = "request_train",
                target = station_id,
                target_label = dest.label,
                trip_type = "collection",
            }, proto.station_command)

            log_trip("collection", station_id, 0, 0)
            utils.add_notification(state,
                string.format("RAIL: Collection from %s", dest.label),
                colors.cyan)
        end

        trip_in_progress = false
        return true
    end

    -- Import items from buffer after a collection trip arrives back at hub
    local function import_buffer_to_storage()
        if not tr.buffer_chest or not st.import_from_peripheral then return 0 end
        local imported = st.import_from_peripheral(tr.buffer_chest)
        if imported > 0 then
            utils.add_notification(state,
                string.format("RAIL: Imported %d items from buffer", imported),
                colors.lime)
        end
        return imported
    end

    -- ========================================
    -- Station Management
    -- ========================================

    tr.register_station = function(sender_id, data)
        local existing = tr.stations[sender_id]
        local was_hub = (existing and existing.is_hub) or false
        tr.stations[sender_id] = {
            id = sender_id,
            label = data.label or ("Station " .. sender_id),
            x = data.x or 0,
            y = data.y or 0,
            z = data.z or 0,
            is_hub = was_hub or data.is_hub or false,
            online = true,
            last_seen = os.clock(),
            rules = existing and existing.rules or {},
            switches = existing and existing.switches or data.switches or {},
            storage_bays = existing and existing.storage_bays or data.storage_bays or {},
            rail_periph = existing and existing.rail_periph or data.rail_periph,
            rail_face = existing and existing.rail_face or data.rail_face or "top",
            detector_periph = existing and existing.detector_periph or data.detector_periph,
            detector_face = existing and existing.detector_face or data.detector_face or "top",
            integrators = data.integrators or (existing and existing.integrators) or {},
            has_train = data.has_train or false,
        }
        -- Auto-set hub if station declares itself as hub
        if data.is_hub and not tr.hub_id then
            tr.hub_id = sender_id
            tr.stations[sender_id].is_hub = true
        elseif tr.hub_id == sender_id then
            tr.stations[sender_id].is_hub = true
        end
        save_transport_data()
        utils.add_notification(state,
            string.format("RAIL: Station registered - %s (#%d)",
                tr.stations[sender_id].label, sender_id),
            colors.cyan)
        return true
    end

    tr.remove_station = function(station_id)
        if tr.stations[station_id] then
            local label = tr.stations[station_id].label
            tr.stations[station_id] = nil
            if tr.hub_id == station_id then
                tr.hub_id = nil
            end
            tr.station_schedules[station_id] = nil
            save_transport_data()
            utils.add_notification(state,
                "RAIL: Station removed - " .. label, colors.orange)
            return true
        end
        return false
    end

    tr.set_hub = function(station_id)
        for id, s in pairs(tr.stations) do
            s.is_hub = false
        end
        if station_id and tr.stations[station_id] then
            tr.stations[station_id].is_hub = true
            tr.hub_id = station_id
            utils.add_notification(state,
                "RAIL: Hub set to " .. tr.stations[station_id].label,
                colors.lime)
        else
            tr.hub_id = nil
        end
        save_transport_data()
    end

    -- ========================================
    -- Route Map
    -- ========================================

    tr.get_route_map = function()
        return {
            stations = tr.stations,
            hub_id = tr.hub_id,
        }
    end

    -- ========================================
    -- Switch Control
    -- ========================================

    tr.set_switch = function(station_id, switch_idx, state_on)
        local station = tr.stations[station_id]
        if not station then return false end
        local sw = station.switches[switch_idx]
        if not sw then return false end

        sw.state = state_on
        if station.online then
            rednet.send(station_id, {
                action = "set_switch",
                switch_idx = switch_idx,
                state = state_on,
            }, proto.station_command)
        end
        save_transport_data()
        return true
    end

    -- ========================================
    -- Station Rules
    -- ========================================

    tr.add_station_rule = function(station_id, rule)
        local station = tr.stations[station_id]
        if not station then return false end
        table.insert(station.rules, {
            type = rule.type or "dispatch",
            item_filter = rule.item_filter or nil,
            destination = rule.destination or nil,
            enabled = true,
        })
        save_transport_data()
        return #station.rules
    end

    tr.remove_station_rule = function(station_id, rule_idx)
        local station = tr.stations[station_id]
        if not station or not station.rules[rule_idx] then return false end
        table.remove(station.rules, rule_idx)
        save_transport_data()
        return true
    end

    tr.update_station_rule = function(station_id, rule_idx, field, value)
        local station = tr.stations[station_id]
        if not station or not station.rules[rule_idx] then return false end
        station.rules[rule_idx][field] = value
        save_transport_data()
        return true
    end

    -- ========================================
    -- Dispatch Coordination
    -- ========================================

    tr.dispatch_train = function(from_station_id, to_station_id)
        local from = tr.stations[from_station_id]
        local to = tr.stations[to_station_id]
        if not from or not to then return false, "station not found" end
        if not from.online then return false, "origin station offline" end
        if not from.has_train then return false, "no train at station" end

        local from_is_hub = (from_station_id == tr.hub_id)
        local to_is_hub = (to_station_id == tr.hub_id)

        for id, station in pairs(tr.stations) do
            if station.online and station.switches and #station.switches > 0 then
                for sw_idx, sw in ipairs(station.switches) do
                    if sw.parking then
                        if to_is_hub then
                            tr.set_switch(id, sw_idx, false)
                        elseif from_is_hub then
                            tr.set_switch(id, sw_idx, true)
                        end
                    elseif sw.routes and sw.routes[tostring(to_station_id)] ~= nil then
                        tr.set_switch(id, sw_idx, sw.routes[tostring(to_station_id)])
                    end
                end
            end
        end

        rednet.send(from_station_id, {
            action = "dispatch",
            destination = to_station_id,
            destination_label = to.label,
        }, proto.station_command)

        table.insert(tr.dispatches, {
            from_id = from_station_id,
            to_id = to_station_id,
            status = "dispatching",
            started = os.clock(),
        })

        utils.add_notification(state,
            string.format("RAIL: Dispatching %s -> %s", from.label, to.label),
            colors.lime)

        return true
    end

    tr.dispatch_to_parking = function(from_station_id, parking_sw_idx)
        local hub = tr.stations[tr.hub_id]
        if not hub then return false, "no hub" end
        local from = tr.stations[from_station_id]
        if not from then return false, "station not found" end
        if not from.online then return false, "origin offline" end
        if not from.has_train then return false, "no train at station" end

        local from_is_hub = (from_station_id == tr.hub_id)

        if hub.switches then
            for sw_idx, sw in ipairs(hub.switches) do
                if sw.parking then
                    if sw_idx == parking_sw_idx then
                        tr.set_switch(tr.hub_id, sw_idx, not from_is_hub)
                    else
                        if from_is_hub then
                            tr.set_switch(tr.hub_id, sw_idx, true)
                        else
                            tr.set_switch(tr.hub_id, sw_idx, false)
                        end
                    end
                end
            end
        end

        rednet.send(from_station_id, {
            action = "dispatch",
            destination = tr.hub_id,
            destination_label = "Parking Bay #" .. parking_sw_idx,
        }, proto.station_command)

        local bay_desc = hub.switches[parking_sw_idx]
            and hub.switches[parking_sw_idx].description or ("Bay #" .. parking_sw_idx)
        utils.add_notification(state,
            string.format("RAIL: Parking %s -> %s", from.label, bay_desc),
            colors.yellow)

        return true
    end

    tr.dispatch_from_parking = function(parking_sw_idx, to_station_id)
        local hub = tr.stations[tr.hub_id]
        if not hub then return false, "no hub" end
        if not hub.online then return false, "hub offline" end

        local sw = hub.switches and hub.switches[parking_sw_idx]
        if not sw or not sw.parking then return false, "invalid bay" end

        local bay_occupied = hub.bay_train_states and hub.bay_train_states[parking_sw_idx]
        if not bay_occupied then return false, "bay empty" end

        if hub.switches then
            for sw_idx, s in ipairs(hub.switches) do
                if s.parking then
                    if sw_idx == parking_sw_idx then
                        tr.set_switch(tr.hub_id, sw_idx, true)
                    else
                        tr.set_switch(tr.hub_id, sw_idx, false)
                    end
                elseif s.routes and s.routes[tostring(to_station_id)] ~= nil then
                    tr.set_switch(tr.hub_id, sw_idx, s.routes[tostring(to_station_id)])
                end
            end
        end

        rednet.send(tr.hub_id, {
            action = "dispatch_from_bay",
            switch_idx = parking_sw_idx,
            destination = to_station_id,
            destination_label = tr.stations[to_station_id] and tr.stations[to_station_id].label or "?",
        }, proto.station_command)

        local bay_desc = sw.description or ("Bay #" .. parking_sw_idx)
        utils.add_notification(state,
            string.format("RAIL: Unpark %s -> %s", bay_desc,
                tr.stations[to_station_id] and tr.stations[to_station_id].label or "?"),
            colors.cyan)

        return true
    end

    tr.send_station_cmd = function(station_id, cmd)
        if tr.stations[station_id] and tr.stations[station_id].online then
            rednet.send(station_id, cmd, proto.station_command)
            return true
        end
        return false
    end

    -- ========================================
    -- Automation Engine
    -- ========================================

    local function process_automation()
        if not tr.hub_id then return end
        local hub = tr.stations[tr.hub_id]
        if not hub or not hub.online then return end

        for _, rule in ipairs(hub.rules or {}) do
            if rule.enabled then
                if rule.type == "dispatch" and rule.destination then
                    if hub.has_train and tr.stations[rule.destination] then
                        tr.dispatch_train(tr.hub_id, rule.destination)
                    end
                end
            end
        end

        -- Auto-park: if hub has a train and no active dispatches, send to parking
        if hub.has_train then
            local has_pending = false
            for _, d in ipairs(tr.dispatches) do
                if d.from_id == tr.hub_id and d.status == "dispatching" then
                    has_pending = true
                    break
                end
            end
            if not has_pending then
                local empty_bay = nil
                if hub.switches then
                    for sw_idx, sw in ipairs(hub.switches) do
                        if sw.parking then
                            local occupied = hub.bay_train_states
                                and hub.bay_train_states[sw_idx]
                            if not occupied then
                                empty_bay = sw_idx
                                break
                            end
                        end
                    end
                end
                if empty_bay then
                    tr.dispatch_to_parking(tr.hub_id, empty_bay)
                end
            end
        end
    end

    -- ========================================
    -- Schedule Engine
    -- ========================================

    local function process_schedules()
        if not tr.hub_id or not tr.buffer_chest then return end
        local hub = tr.stations[tr.hub_id]
        if not hub or not hub.online then return end
        if trip_in_progress then return end

        local now = os.epoch("utc") / 1000  -- seconds since epoch

        for station_id, scheds in pairs(tr.station_schedules) do
            local dest = tr.stations[station_id]
            if dest and dest.online and station_id ~= tr.hub_id then
                for _, sched in ipairs(scheds) do
                    if sched.enabled and sched.period > 0 then
                        local elapsed = now - (sched.last_run or 0)
                        if elapsed >= sched.period then
                            -- Build item request list for delivery
                            local reqs = {}
                            if sched.type == "delivery" then
                                for _, item_name in ipairs(sched.items or {}) do
                                    local amt = (sched.amounts and sched.amounts[item_name]) or 64
                                    table.insert(reqs, {item = item_name, amount = amt})
                                end
                            end

                            local ok, err = tr.execute_trip(station_id, sched.type, reqs)
                            if ok then
                                sched.last_run = now
                                save_transport_data()
                            end
                            -- Only process one trip per tick to avoid overwhelming
                            return
                        end
                    end
                end
            end
        end
    end

    -- ========================================
    -- Load Saved Data
    -- ========================================

    local saved = load_saved_config()
    if saved then
        tr.hub_id = saved.hub_id
        if saved.stations then
            for id, st_data in pairs(saved.stations) do
                tr.stations[id] = {
                    id = id,
                    label = st_data.label or ("Station " .. id),
                    x = st_data.x or 0,
                    y = st_data.y or 0,
                    z = st_data.z or 0,
                    is_hub = st_data.is_hub or false,
                    online = false,
                    last_seen = 0,
                    rules = st_data.rules or {},
                    switches = st_data.switches or {},
                    storage_bays = st_data.storage_bays or {},
                    rail_periph = st_data.rail_periph,
                    rail_face = st_data.rail_face or "top",
                    detector_periph = st_data.detector_periph,
                    detector_face = st_data.detector_face or "top",
                    integrators = st_data.integrators or {},
                    has_train = false,
                }
            end
        end
        -- Logistics
        tr.buffer_chest = saved.buffer_chest
        if saved.allowed_items then tr.allowed_items = saved.allowed_items end
        tr.fuel_item = saved.fuel_item
        tr.fuel_per_trip = saved.fuel_per_trip
        if saved.station_schedules then tr.station_schedules = saved.station_schedules end
    end

    -- Try to wrap buffer peripheral
    wrap_buffer()

    -- ========================================
    -- Initialize
    -- ========================================

    tr.ready = true
    local station_count = 0
    for _ in pairs(tr.stations) do station_count = station_count + 1 end
    local buf_str = tr.buffer_chest or "none"
    utils.add_notification(state,
        string.format("RAIL: Transport ready (%d stations, buf=%s)", station_count, buf_str),
        colors.cyan)

    -- ========================================
    -- Main Event Loop
    -- ========================================

    -- Host on station ping protocol so station clients can discover Wraith
    rednet.host(proto.station_ping, "wraith_rail_hub")

    local TICK_INTERVAL = cfg.status_interval or 5
    local tick_timer = os.startTimer(TICK_INTERVAL)

    while state.running do
        local ev = {coroutine.yield()}

        if ev[1] == "timer" and ev[2] == tick_timer then
            local tick_ok, tick_err = pcall(function()
                local now = os.clock()

                -- Check station heartbeats
                for id, station in pairs(tr.stations) do
                    if station.online and station.last_seen > 0
                       and (now - station.last_seen) > cfg.heartbeat_timeout then
                        station.online = false
                        utils.add_notification(state,
                            "RAIL: Station offline - " .. station.label, colors.orange)
                    end
                end

                -- Clean up stale dispatches (> 5 min)
                local i = 1
                while i <= #tr.dispatches do
                    if (now - tr.dispatches[i].started) > 300 then
                        table.remove(tr.dispatches, i)
                    else
                        i = i + 1
                    end
                end

                -- Re-wrap buffer if needed
                if tr.buffer_chest and not tr.buffer_periph then
                    wrap_buffer()
                end

                -- Automation
                process_automation()

                -- Logistics schedules
                process_schedules()
            end)
            if not tick_ok then
                utils.add_notification(state,
                    "RAIL ERR: " .. tostring(tick_err):sub(1, 40), colors.red)
            end

            tick_timer = os.startTimer(TICK_INTERVAL)

        elseif ev[1] == "rednet_message" then
            local net_ok, net_err = pcall(function()
                local sender = ev[2]
                local msg = ev[3]
                local protocol = ev[4]

                if protocol == proto.station_ping and type(msg) == "table" then
                    tr.register_station(sender, msg)
                    rednet.send(sender, {
                        status = "wraith_rail_hub",
                        hub_id = tr.hub_id,
                        stations = tr.get_route_map(),
                    }, proto.station_status)

                elseif protocol == proto.station_register and type(msg) == "table" then
                    tr.register_station(sender, msg)
                    rednet.send(sender, {
                        status = "registered",
                        hub_id = tr.hub_id,
                    }, proto.station_status)

                elseif protocol == proto.station_heartbeat and type(msg) == "table" then
                    local station = tr.stations[sender]
                    if station then
                        station.last_seen = os.clock()
                        station.online = true
                        if msg.has_train ~= nil then station.has_train = msg.has_train end
                        if msg.label then station.label = msg.label end
                        if msg.bay_train_states then station.bay_train_states = msg.bay_train_states end
                    end

                    -- If hub reports a train arrived and we have collection buffer, import
                    if sender == tr.hub_id and msg.has_train and tr.buffer_chest then
                        import_buffer_to_storage()
                    end

                elseif protocol == proto.station_status and type(msg) == "table" then
                    local station = tr.stations[sender]
                    if station then
                        station.last_seen = os.clock()
                        station.online = true
                        if msg.rules then station.rules = msg.rules end
                        if msg.switches then station.switches = msg.switches end
                        if msg.storage_bays then station.storage_bays = msg.storage_bays end
                        if msg.rail_periph then station.rail_periph = msg.rail_periph end
                        if msg.rail_face then station.rail_face = msg.rail_face end
                        if msg.detector_periph then station.detector_periph = msg.detector_periph end
                        if msg.detector_face then station.detector_face = msg.detector_face end
                        if msg.integrators then station.integrators = msg.integrators end
                        if msg.has_train ~= nil then station.has_train = msg.has_train end
                        if msg.bay_train_states then station.bay_train_states = msg.bay_train_states end
                        save_transport_data()
                    end

                elseif protocol == proto.station_command and type(msg) == "table" then
                    -- Schedule management commands from station clients
                    if msg.action == "get_allow_list" then
                        rednet.send(sender, {
                            action = "allow_list",
                            items = tr.allowed_items,
                        }, proto.station_command)

                    elseif msg.action == "get_schedules" then
                        rednet.send(sender, {
                            action = "schedules",
                            schedules = tr.station_schedules[sender] or {},
                        }, proto.station_command)

                    elseif msg.action == "add_schedule" and msg.schedule then
                        local ok = tr.add_schedule(sender, msg.schedule)
                        rednet.send(sender, {
                            action = ok and "schedule_ok" or "schedule_error",
                            message = ok and "Schedule added" or "Failed to add",
                        }, proto.station_command)
                        if ok then
                            rednet.send(sender, {
                                action = "schedules",
                                schedules = tr.station_schedules[sender] or {},
                            }, proto.station_command)
                        end

                    elseif msg.action == "toggle_schedule" and msg.idx then
                        local ok = tr.toggle_schedule(sender, msg.idx)
                        rednet.send(sender, {
                            action = ok and "schedule_ok" or "schedule_error",
                            message = ok and "Toggled" or "Not found",
                        }, proto.station_command)
                        if ok then
                            rednet.send(sender, {
                                action = "schedules",
                                schedules = tr.station_schedules[sender] or {},
                            }, proto.station_command)
                        end

                    elseif msg.action == "remove_schedule" and msg.idx then
                        local ok = tr.remove_schedule(sender, msg.idx)
                        rednet.send(sender, {
                            action = ok and "schedule_ok" or "schedule_error",
                            message = ok and "Removed" or "Not found",
                        }, proto.station_command)
                        if ok then
                            rednet.send(sender, {
                                action = "schedules",
                                schedules = tr.station_schedules[sender] or {},
                            }, proto.station_command)
                        end

                    elseif msg.action == "update_schedule" and msg.idx and msg.field then
                        local ok = tr.update_schedule(sender, msg.idx, msg.field, msg.value)
                        rednet.send(sender, {
                            action = ok and "schedule_ok" or "schedule_error",
                            message = ok and "Updated" or "Not found",
                        }, proto.station_command)
                        if ok then
                            rednet.send(sender, {
                                action = "schedules",
                                schedules = tr.station_schedules[sender] or {},
                            }, proto.station_command)
                        end

                    elseif msg.action == "run_schedule" and msg.idx then
                        local scheds = tr.station_schedules[sender]
                        if scheds and scheds[msg.idx] then
                            local sched = scheds[msg.idx]
                            local reqs = {}
                            if sched.type == "delivery" then
                                for _, item_name in ipairs(sched.items or {}) do
                                    local amt = (sched.amounts and sched.amounts[item_name]) or 64
                                    table.insert(reqs, {item = item_name, amount = amt})
                                end
                            end
                            local ok, err = tr.execute_trip(sender, sched.type, reqs)
                            if ok then
                                sched.last_run = math.floor(os.epoch("utc") / 1000)
                                save_transport_data()
                                rednet.send(sender, {action = "schedule_run_ok", message = "Trip started"}, proto.station_command)
                            else
                                rednet.send(sender, {action = "schedule_run_error", message = err or "Failed"}, proto.station_command)
                            end
                        else
                            rednet.send(sender, {action = "schedule_run_error", message = "Schedule not found"}, proto.station_command)
                        end
                    end
                end
            end)
            if not net_ok then
                utils.add_notification(state,
                    "RAIL NET ERR: " .. tostring(net_err):sub(1, 40), colors.red)
            end

        elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            -- Re-check buffer chest on peripheral changes
            if tr.buffer_chest then
                wrap_buffer()
            end
        end
    end
end

return svc
