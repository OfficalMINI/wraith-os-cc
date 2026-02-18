-- =============================================
-- WRAITH OS - STORAGE SERVICE
-- =============================================
-- Background storage engine: scanning, import, extract, smelting.
-- Ported from JARVIS modules/storage.lua

local svc = {}

function svc.main(state, config, utils)
    local st = state.storage  -- shorthand

    -- Debug log file
    local log_file = _G.WRAITH_ROOT .. "/storage_debug.log"
    local function log(msg)
        local f = fs.open(log_file, "a")
        if f then
            f.write(string.format("[%.1f] %s\n", os.clock(), msg))
            f.close()
        end
    end
    -- Clear old log on startup
    if fs.exists(log_file) then fs.delete(log_file) end
    log("Storage service starting")

    -- Config persistence
    local config_file = _G.WRAITH_ROOT .. "/storage_config.lua"

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

    local function save_config(data)
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

    -- Analytics persistence
    local analytics_file = _G.WRAITH_ROOT .. "/analytics_data.lua"
    local ANALYTICS_SAVE_INTERVAL = 60  -- full save every 60 seconds

    local function load_analytics()
        if not fs.exists(analytics_file) then
            log("No analytics file found at: " .. analytics_file)
            return
        end
        local f = fs.open(analytics_file, "r")
        if not f then
            log("Failed to open analytics file")
            return
        end
        local data = f.readAll()
        f.close()
        if not data or data == "" then
            log("Analytics file is empty")
            return
        end
        -- Try textutils.unserialise first (canonical CC method)
        local saved = textutils.unserialise(data)
        if not saved then
            -- Fallback to loadstring for older format
            local fn = load("return " .. data)
            if fn then
                local ok, result = pcall(fn)
                if ok then saved = result end
            end
        end
        if type(saved) == "table" then
            local a = state.analytics
            if saved.totals then a.totals = saved.totals end
            if saved.top_extracted then a.top_extracted = saved.top_extracted end
            if saved.top_imported then a.top_imported = saved.top_imported end
            if saved.top_craft_used then a.top_craft_used = saved.top_craft_used end
            if saved.top_smelt_used then a.top_smelt_used = saved.top_smelt_used end
            if saved.peak_items_min then a.peak_items_min = saved.peak_items_min end
            local count = 0
            for _ in pairs(a.top_extracted) do count = count + 1 end
            log("Analytics restored: " .. count .. " tracked items")
        else
            log("Failed to parse analytics data")
        end
    end

    local function save_analytics()
        local a = state.analytics
        local data = {
            totals = a.totals,
            top_extracted = a.top_extracted,
            top_imported = a.top_imported,
            top_craft_used = a.top_craft_used,
            top_smelt_used = a.top_smelt_used,
            peak_items_min = a.peak_items_min,
        }
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 5 then return end
        local tmp = analytics_file .. ".tmp"
        local f = fs.open(tmp, "w")
        if f then
            f.write(content)
            f.close()
            if fs.exists(analytics_file) then fs.delete(analytics_file) end
            fs.move(tmp, analytics_file)
        end
    end

    -- Peripheral discovery helpers
    local function is_excluded_storage(ptype)
        if not ptype then return false end
        for _, etype in ipairs(config.storage.excluded_types or {}) do
            if ptype == etype then return true end
        end
        return false
    end

    local function is_storage_type(ptype)
        if not ptype then return false end
        if is_excluded_storage(ptype) then return false end
        for _, btype in ipairs(config.storage.bridge_types or {}) do
            if ptype == btype then return true end
        end
        for _, stype in ipairs(config.storage.storage_types or {}) do
            if ptype == stype then return true end
        end
        for _, pattern in ipairs(config.storage.storage_patterns or {}) do
            if ptype:find(pattern) then return true end
        end
        return false
    end

    local function is_furnace_type(ptype)
        if not ptype then return false end
        for _, pattern in ipairs(config.smelting.furnace_patterns) do
            if ptype:find(pattern) then return true end
        end
        return false
    end

    -- Smeltable / fuel lookups
    local smeltable_set = {}
    local fuel_set = {}
    for _, name in ipairs(config.smelting.fuel_items or {}) do fuel_set[name] = true end

    local function rebuild_smeltable_set()
        smeltable_set = {}
        for _, rule in ipairs(st.smelt_rules) do
            if rule.enabled then smeltable_set[rule.input] = true end
        end
        for _, task in ipairs(st.smelt_tasks) do
            if task.active then smeltable_set[task.input] = true end
        end
        -- Fallback to legacy config when no rules/tasks defined
        if next(smeltable_set) == nil and #st.smelt_rules == 0 and #st.smelt_tasks == 0 then
            for _, name in ipairs(config.smelting.smeltable_items) do
                smeltable_set[name] = true
            end
        end
    end

    local function is_smeltable(item_name)
        -- Legacy fallback when no rules/tasks
        if #st.smelt_rules == 0 and #st.smelt_tasks == 0 then
            if #config.smelting.smeltable_items == 0 then return true end
            if smeltable_set[item_name] then return true end
            for _, pattern in ipairs(config.smelting.smeltable_items) do
                if item_name:find(pattern, 1, true) then return true end
            end
            return false
        end
        return smeltable_set[item_name] == true
    end

    local function should_smelt_item(item_name)
        if not is_smeltable(item_name) then return false, nil end
        -- Active tasks take priority
        for _, task in ipairs(st.smelt_tasks) do
            if task.active and task.input == item_name and task.smelted < task.target then
                return true, "task"
            end
        end
        -- Check rules
        for _, rule in ipairs(st.smelt_rules) do
            if rule.enabled and rule.input == item_name then
                if rule.threshold == 0 then
                    return true, "rule"
                end
                local output_count = (st.output_stock or {})[rule.output] or 0
                if output_count < rule.threshold then
                    return true, "rule"
                end
                return false, nil  -- threshold met
            end
        end
        -- Legacy fallback
        if #st.smelt_rules == 0 and #st.smelt_tasks == 0 then
            return true, "legacy"
        end
        return false, nil
    end

    local function save_smelt_data()
        local saved = load_saved_config() or {}
        saved.smelt_rules = st.smelt_rules
        saved.smelt_tasks = st.smelt_tasks
        save_config(saved)
    end

    local function is_fuel(item_name)
        if fuel_set[item_name] then return true end
        for _, pattern in ipairs(config.smelting.fuel_items or {}) do
            if item_name:find(pattern, 1, true) then return true end
        end
        return false
    end

    -- Forward declarations for analytics (defined later, used by import/extract)
    local log_analytics
    local log_capacity

    -- Build set of all farm chest peripheral names (from file + live state)
    local function get_farm_chest_set()
        local set = {}
        -- From config file
        local farms_cfg_path = _G.WRAITH_ROOT .. "/farms_config.lua"
        if fs.exists(farms_cfg_path) then
            local ff = fs.open(farms_cfg_path, "r")
            if ff then
                local raw = ff.readAll()
                ff.close()
                if raw and raw ~= "" then
                    local parsed = textutils.unserialise(raw)
                    if parsed and parsed.plots then
                        for _, plot in ipairs(parsed.plots) do
                            if plot.input and plot.input ~= "" then set[plot.input] = true end
                            if plot.output and plot.output ~= "" then set[plot.output] = true end
                        end
                    end
                end
            end
        end
        -- From live state (covers dynamically added farms)
        if state.farms and state.farms.plots then
            for _, plot in ipairs(state.farms.plots) do
                if plot.input and plot.input ~= "" then set[plot.input] = true end
                if plot.output and plot.output ~= "" then set[plot.output] = true end
            end
        end
        return set
    end

    -- Remove any farm chests from st.peripherals (safety net)
    local function strip_farm_chests()
        local farm_set = get_farm_chest_set()
        local cleaned = {}
        for _, p in ipairs(st.peripherals) do
            if farm_set[p.name] then
                log("STRIPPED farm chest from storage: " .. p.name)
                st.names[p.name] = "farm"
            else
                table.insert(cleaned, p)
            end
        end
        if #cleaned ~= #st.peripherals then
            log("strip_farm_chests: removed " .. (#st.peripherals - #cleaned) .. " farm chests from storage list")
            st.peripherals = cleaned
        end
    end

    -- Expose farm chest strip so farms service can call it when chests are re-assigned
    st.strip_farm_chests = function()
        local before = #st.peripherals
        strip_farm_chests()
        if #st.peripherals < before then
            log("Farm chest stripped: removed " .. (before - #st.peripherals) .. " from storage")
            scan_all_items()
            reset_full_cache()
        end
    end

    -- Peripheral discovery
    local function discover_peripherals()
        st.peripherals = {}
        st.names = {}
        st.output_peripheral = nil
        st.depot_peripherals = {}
        st.furnace_peripherals = {}
        st.fuel_peripheral = nil

        local saved = load_saved_config()
        local saved_output = (saved and saved.output) or config.storage.output_chest
        local saved_fuel = saved and saved.fuel_chest or nil
        st.labels = saved and saved.labels or {}
        st.output_as_depot = not (saved and saved.output_as_depot == false)

        local depot_set = {}
        if saved and saved.depots then
            for _, name in ipairs(saved.depots) do depot_set[name] = true end
        end
        for _, name in ipairs(config.storage.input_depots or {}) do depot_set[name] = true end
        if saved and saved.input and not saved.depots then depot_set[saved.input] = true end

        local all_names = peripheral.getNames()
        log("discover: " .. #all_names .. " raw peripherals")
        local unassigned = {}
        local avail = {}
        local seen_names = {}  -- prevent duplicate peripherals

        local function add_storage(name, ptype, p)
            if seen_names[name] then return end
            seen_names[name] = true
            local slots = 0
            if p.size then
                local sz_ok, sz = pcall(p.size)
                if sz_ok then slots = sz end
            end
            table.insert(avail, {name = name, type = ptype or "unknown", slots = slots})

            if saved_output and name == saved_output then
                st.output_peripheral = p
                st.names[name] = "output"
            elseif saved_fuel and name == saved_fuel then
                st.fuel_peripheral = p
                st.names[name] = "fuel"
            elseif depot_set[name] then
                table.insert(st.depot_peripherals, {name = name, periph = p})
                st.names[name] = "depot"
            else
                table.insert(unassigned, {name = name, type = ptype or "unknown", periph = p, slots = slots})
                st.names[name] = "storage"
            end
        end

        -- Build set of loadout buffer barrels to exclude
        local loadout_buffers = {}
        if state.loadouts and state.loadouts.buffer_barrels then
            for _, bname in pairs(state.loadouts.buffer_barrels) do
                loadout_buffers[bname] = true
            end
        end

        -- Build set of farm input/output chests to exclude
        local farm_chests = get_farm_chest_set()
        for name in pairs(farm_chests) do
            log("discover: farm-excluded: " .. name)
        end

        -- Peripheral types managed by other services (not storage)
        local excluded_types = {inventoryManager = true, playerDetector = true}

        -- Helper: is this a barrel type? Barrels are never part of storage
        local function is_barrel_type(ptype)
            if not ptype then return false end
            return ptype == "minecraft:barrel" or ptype:find("barrel") ~= nil
        end

        for i, name in ipairs(all_names) do
            -- Skip loadout buffer barrels, farm chests, and all barrel types
            if not loadout_buffers[name] and not farm_chests[name] then
                local ok_t, ptype = pcall(peripheral.getType, name)
                if not ok_t then ptype = nil end

                if excluded_types[ptype] then
                    -- Skip: managed by another service
                elseif is_barrel_type(ptype) then
                    -- Skip: barrels are reserved for loadout buffers
                elseif is_furnace_type(ptype) then
                    local p = peripheral.wrap(name)
                    if p then
                        table.insert(st.furnace_peripherals, {name = name, type = ptype, periph = p})
                    end
                elseif is_storage_type(ptype) then
                    local p = peripheral.wrap(name)
                    if p and p.list then
                        add_storage(name, ptype, p)
                    end
                elseif is_excluded_storage(ptype) then
                    -- Skip: reserved for transport buffer (trapped chests etc.)
                else
                    local ok_w, p = pcall(peripheral.wrap, name)
                    if ok_w and p and type(p.list) == "function" then
                        add_storage(name, ptype or "inventory", p)
                    end
                end
            end
        end

        st.peripherals = unassigned
        st.furnace_count = #st.furnace_peripherals
        table.sort(avail, function(a, b) return a.name < b.name end)
        st.available_peripherals = avail

        -- Post-discovery: strip any farm chests that slipped through
        strip_farm_chests()

        log("discover DONE: " .. #avail .. " storage, " .. #st.furnace_peripherals .. " furnaces, " .. #unassigned .. " unassigned (after strip: " .. #st.peripherals .. ")")

        utils.add_notification(state,
            string.format("SCAN: %d peripherals found, %d storage, %d furnaces",
                #all_names, #avail, #st.furnace_peripherals), colors.cyan)

        return #st.available_peripherals > 0
    end

    -- Display name cache
    local display_name_cache = {}
    local tags_cache = {}  -- key -> tags table (from getItemDetail)

    -- In-memory item cache: updated incrementally by import/extract/smelt/fuel.
    -- Full peripheral scan only at startup + peripheral attach/detach events.
    local item_map = {}  -- key -> {name, displayName, count, nbt}
    local cache_dirty = false

    local function cache_adjust(item_name, nbt, delta, display)
        local key = item_name .. "|" .. (nbt or "")
        local entry = item_map[key]
        if entry then
            entry.count = entry.count + delta
            if entry.count <= 0 then
                item_map[key] = nil
            end
        elseif delta > 0 then
            item_map[key] = {
                name = item_name,
                displayName = display or display_name_cache[key] or utils.clean_name(item_name),
                count = delta,
                nbt = nbt,
                tags = tags_cache[key],
            }
        end
        cache_dirty = true
    end

    local function rebuild_item_list()
        if not cache_dirty then return end
        cache_dirty = false
        local sorted = {}
        local total_count = 0
        local type_count = 0
        local total_fuel = 0
        local total_smeltable = 0
        local output_stock_map = {}
        for _, item in pairs(item_map) do
            if item.count > 0 then
                table.insert(sorted, item)
                total_count = total_count + item.count
                type_count = type_count + 1
                output_stock_map[item.name] = (output_stock_map[item.name] or 0) + item.count
                if is_fuel(item.name) then total_fuel = total_fuel + item.count end
                if is_smeltable(item.name) then total_smeltable = total_smeltable + item.count end
            end
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        st.items = sorted
        st.item_count = total_count
        st.type_count = type_count
        st.cached_fuel_total = total_fuel
        st.cached_smeltable_total = total_smeltable
        st.output_stock = output_stock_map
    end

    -- Per-peripheral slot cache: avoids re-listing all storage for fuel/smelt/extract.
    -- Built during scan_all_items(), decremented when items pulled from storage.
    local storage_slots = {}       -- [periph_idx] -> {[slot] -> {name, count, nbt}}
    local dirty_peripherals = {}   -- set of periph indices that received imports (need re-list)

    local function refresh_dirty()
        for si in pairs(dirty_peripherals) do
            local store = st.peripherals[si]
            if store then
                local ok, list = pcall(store.periph.list)
                storage_slots[si] = ok and list or {}
            end
        end
        dirty_peripherals = {}
    end

    -- Update slot cache + aggregate cache after pulling items FROM a storage peripheral
    local function slot_pull(si, slot, count, item_name, item_nbt)
        local slots = storage_slots[si]
        if slots and slots[slot] then
            slots[slot].count = slots[slot].count - count
            if slots[slot].count <= 0 then slots[slot] = nil end
        end
        cache_adjust(item_name, item_nbt, -count)
    end

    -- Full item scan (startup + peripheral events only)
    local function scan_all_items()
        item_map = {}
        storage_slots = {}
        dirty_peripherals = {}
        local total_slots = 0
        local used_slots = 0
        local need_detail = {}

        for si, store in ipairs(st.peripherals) do
            total_slots = total_slots + (store.slots or 0)
            local ok, list = pcall(store.periph.list)
            storage_slots[si] = (ok and list) or {}
            if ok and list then
                for slot, item in pairs(list) do
                    used_slots = used_slots + 1
                    local key = item.name .. "|" .. (item.nbt or "")

                    if item_map[key] then
                        item_map[key].count = item_map[key].count + item.count
                    else
                        local display = display_name_cache[key]
                        if not display then
                            table.insert(need_detail, {store = store, slot = slot, key = key})
                        end
                        item_map[key] = {
                            name = item.name,
                            displayName = display or utils.clean_name(item.name),
                            count = item.count,
                            nbt = item.nbt,
                            tags = tags_cache[key],
                        }
                    end
                end
            end
        end

        -- Resolve display names and tags lazily
        for di, nd in ipairs(need_detail) do
            if nd.store.periph.getItemDetail then
                local dok, detail = pcall(nd.store.periph.getItemDetail, nd.slot)
                if dok and detail then
                    if detail.displayName then
                        display_name_cache[nd.key] = detail.displayName
                        if item_map[nd.key] then item_map[nd.key].displayName = detail.displayName end
                    else
                        display_name_cache[nd.key] = item_map[nd.key] and item_map[nd.key].displayName or ""
                    end
                    if detail.tags then
                        tags_cache[nd.key] = detail.tags
                        if item_map[nd.key] then item_map[nd.key].tags = detail.tags end
                    end
                else
                    display_name_cache[nd.key] = item_map[nd.key] and item_map[nd.key].displayName or ""
                end
            end
        end

        cache_dirty = true
        rebuild_item_list()
        st.last_scan_time = os.clock()
        st.ready = true

        st.stats = {
            total_slots = total_slots, used_slots = used_slots,
            free_slots = total_slots - used_slots,
            usage_pct = total_slots > 0 and (used_slots / total_slots) or 0,
            peripheral_count = #st.peripherals,
            item_count = st.item_count, type_count = st.type_count,
        }
    end

    -- Extract items
    local function extract_item(item, amount)
        if not st.output_peripheral then
            utils.set_status(state, "No output chest! Use Settings", colors.red, 3)
            return 0
        end

        local remaining = amount
        local output_name = nil
        for name, role in pairs(st.names) do
            if role == "output" then output_name = name; break end
        end
        if not output_name then return 0 end

        -- Refresh dirty peripherals so recently imported items are findable
        refresh_dirty()

        for si, slots in pairs(storage_slots) do
            if remaining <= 0 then break end
            for slot, slot_item in pairs(slots) do
                if remaining <= 0 then break end
                if slot_item.name == item.name and
                   (slot_item.nbt == item.nbt or (not slot_item.nbt and not item.nbt)) then
                    local to_extract = math.min(remaining, slot_item.count)
                    local store = st.peripherals[si]
                    local pushed_ok, pushed = pcall(store.periph.pushItems, output_name, slot, to_extract)
                    if pushed_ok and pushed and pushed > 0 then
                        remaining = remaining - pushed
                        slot_pull(si, slot, pushed, slot_item.name, slot_item.nbt)
                    elseif pushed_ok and (pushed == 0 or not pushed) then
                        slots[slot] = nil  -- phantom: slot empty or item gone
                    end
                end
            end
        end

        local extracted = amount - remaining
        if extracted > 0 then
            utils.set_status(state,
                string.format("Extracted %sx %s", utils.format_number(extracted), utils.truncate(item.displayName, 18)),
                colors.lime, 3)
            utils.add_notification(state,
                string.format("OUT: %sx %s", utils.format_number(extracted), item.displayName), colors.orange)
            local key = item.name .. "|" .. (item.nbt or "")
            local buf = st.extract_buffer[key]
            if buf then buf.count = buf.count + extracted; buf.time = os.clock()
            else st.extract_buffer[key] = {count = extracted, time = os.clock()} end
        else
            utils.set_status(state, "Failed to extract!", colors.red, 3)
        end
        return extracted
    end

    -- Push items from storage to a named peripheral (e.g. transport buffer)
    -- Returns number of items actually pushed
    local function extract_to_peripheral(target_name, item_name, amount)
        if not target_name or not item_name or amount <= 0 then return 0 end

        refresh_dirty()

        local remaining = amount
        for si, slots in pairs(storage_slots) do
            if remaining <= 0 then break end
            for slot, slot_item in pairs(slots) do
                if remaining <= 0 then break end
                if slot_item.name == item_name then
                    local to_push = math.min(remaining, slot_item.count)
                    local store = st.peripherals[si]
                    local push_ok, pushed = pcall(store.periph.pushItems, target_name, slot, to_push)
                    if push_ok and pushed and pushed > 0 then
                        remaining = remaining - pushed
                        slot_pull(si, slot, pushed, slot_item.name, slot_item.nbt)
                    end
                end
            end
        end
        return amount - remaining
    end

    -- Import items (optimized: rotating index + skip full peripherals)
    local import_start_idx = 1  -- rotating index for finding storage with space
    local full_peripherals = {}  -- set of indices that returned 0 (persisted across ticks)
    local full_reset_needed = false  -- set true when storage state changes

    local function reset_full_cache()
        full_peripherals = {}
        full_reset_needed = false
    end

    local function push_to_storage(source_periph, slot, item_name, item_nbt)
        -- Push items from source slot into storage.
        -- If item_name is given, try peripherals that already have that item first
        -- (consolidates stacks, reduces fragmentation).
        local n = #st.peripherals
        if n == 0 then return 0 end
        if import_start_idx > n then import_start_idx = 1 end
        local total = 0

        -- Phase 1: try peripherals that already contain this item (stack consolidation)
        -- Push directly into a partial stack slot. Skip stacks >= 64 (likely full).
        -- Limit attempts to avoid blocking the tick with many failed pushItems calls.
        if item_name then
            local attempts = 0
            for si, slots in pairs(storage_slots) do
                if attempts >= 3 then break end  -- cap peripheral calls
                if not full_peripherals[si] then
                    local store = st.peripherals[si]
                    if store then
                        for target_slot, sitem in pairs(slots) do
                            if sitem.name == item_name and (sitem.nbt or "") == (item_nbt or "")
                               and sitem.count < 64 then
                                attempts = attempts + 1
                                local push_ok, pushed = pcall(source_periph.pushItems, store.name, slot, nil, target_slot)
                                if push_ok and pushed and pushed > 0 then
                                    total = total + pushed
                                    import_start_idx = si
                                    dirty_peripherals[si] = true
                                    return total
                                end
                                break  -- one try per peripheral
                            end
                        end
                    end
                end
            end
        end

        -- Phase 2: rotating index fallback (new stacks or overflow)
        for offset = 0, n - 1 do
            local idx = ((import_start_idx - 1 + offset) % n) + 1
            if not full_peripherals[idx] then
                local store = st.peripherals[idx]
                local push_ok, pushed = pcall(source_periph.pushItems, store.name, slot)
                if push_ok and pushed and pushed > 0 then
                    total = total + pushed
                    import_start_idx = idx  -- remember this one had space
                    dirty_peripherals[idx] = true
                elseif push_ok then
                    -- pushItems returned 0: either source empty or destination full
                    if total > 0 then
                        -- We already moved some items; source slot might be empty now
                        break
                    else
                        -- Source still has items but this peripheral can't take them
                        full_peripherals[idx] = true
                    end
                end
            end
        end
        return total
    end

    -- Import diagnostics
    local import_tick_count = 0
    local import_skip_reason = ""
    local import_total_session = 0
    local import_slots_last = 0      -- slots seen in most recent tick
    local import_stuck_count = 0     -- consecutive ticks with slots but 0 imported
    local import_last_time = 0       -- os.clock() of last successful import

    local function import_items()
        -- Only reset full-peripheral cache when storage state has changed
        -- (after scan, extract, or peripheral event) — NOT every tick
        if full_reset_needed then
            reset_full_cache()
        end

        local t0 = os.clock()
        local now = t0
        for key, buf in pairs(st.extract_buffer) do
            if now - buf.time > 120 then st.extract_buffer[key] = nil end
        end

        local imported = 0
        local depot_slots_seen = 0
        local import_detail = {}  -- {display_name -> count}

        local function track_import(item, pushed)
            if pushed <= 0 then return end
            local key = item.name .. "|" .. (item.nbt or "")
            local display = display_name_cache[key] or utils.clean_name(item.name)
            import_detail[display] = (import_detail[display] or 0) + pushed
        end

        for di, depot in ipairs(st.depot_peripherals) do
            local ok, list = pcall(depot.periph.list)
            if ok and list then
                for slot, item in pairs(list) do
                    depot_slots_seen = depot_slots_seen + 1
                    local pushed = push_to_storage(depot.periph, slot, item.name, item.nbt)
                    imported = imported + pushed
                    track_import(item, pushed)
                    if pushed > 0 then cache_adjust(item.name, item.nbt, pushed) end
                end
            end
        end

        if st.output_as_depot and st.output_peripheral then
            local ok, list = pcall(st.output_peripheral.list)
            if ok and list then
                for slot, item in pairs(list) do
                    local key = item.name .. "|" .. (item.nbt or "")
                    local buf = st.extract_buffer[key]
                    if not buf or (now - buf.time > 120) then
                        depot_slots_seen = depot_slots_seen + 1
                        local pushed = push_to_storage(st.output_peripheral, slot, item.name, item.nbt)
                        imported = imported + pushed
                        track_import(item, pushed)
                        if pushed > 0 then cache_adjust(item.name, item.nbt, pushed) end
                    end
                end
            end
        end

        -- Update diagnostics
        import_slots_last = depot_slots_seen
        import_total_session = import_total_session + imported

        local elapsed = os.clock() - t0

        -- Count full cache size for logging
        local full_count = 0
        for _ in pairs(full_peripherals) do full_count = full_count + 1 end

        -- Log to debug file every 25 ticks or when something happens
        if import_tick_count % 25 == 0 or imported > 0 or (depot_slots_seen > 0 and imported == 0) or elapsed > 0.5 then
            log(string.format("import tick #%d: slots=%d, imported=%d, total=%d, %.1fs, full=%d/%d",
                import_tick_count, depot_slots_seen, imported, import_total_session,
                elapsed, full_count, #st.peripherals))
        end

        if imported > 0 then
            import_stuck_count = 0
            import_last_time = os.clock()
            utils.set_status(state, string.format("Imported %s items", utils.format_number(imported)), colors.lime, 3)
            utils.add_notification(state, string.format("IN: %s items imported", utils.format_number(imported)), colors.lime)
            -- Log per-item analytics
            for display, count in pairs(import_detail) do
                log_analytics("imported", count, display)
            end
        elseif depot_slots_seen > 0 then
            import_stuck_count = import_stuck_count + 1
        else
            import_stuck_count = 0
        end
        return imported
    end

    -- Smelting engine
    local function pull_furnace_outputs(furnace_lists)
        local pulled = 0
        -- Use a LOCAL full cache so we don't pollute the import cache
        local saved_full = full_peripherals
        full_peripherals = {}
        for fi, furnace in ipairs(st.furnace_peripherals) do
            local list = furnace_lists[fi]
            if list and list[3] then
                local item = list[3]
                local pushed = push_to_storage(furnace.periph, 3, item.name, item.nbt)
                if pushed > 0 then cache_adjust(item.name, item.nbt, pushed) end
                pulled = pulled + pushed
            end
        end
        full_peripherals = saved_full  -- restore import cache
        if pulled > 0 then
            st.items_pulled = st.items_pulled + pulled
            full_reset_needed = true  -- items added to storage, re-check space
        end
        return pulled
    end

    local function push_furnace_fuel(furnace_lists)
        if #st.furnace_peripherals == 0 or #st.peripherals == 0 then return 0 end
        local total_fuel = st.cached_fuel_total or 0
        if total_fuel == 0 then return 0 end
        local FUEL_RATIO = 8
        local pushed_total = 0

        for fi, furnace in ipairs(st.furnace_peripherals) do
            local list = furnace_lists[fi] or {}
            local fuel_item = list[2] or nil
            local fuel_count = fuel_item and fuel_item.count or 0
            local input_item = list[1] or nil
            local input_count = input_item and input_item.count or 0

            -- Only push fuel when slot is empty and there are items to smelt
            if fuel_count == 0 and input_count > 0 then
                local needed = math.ceil(input_count / FUEL_RATIO)
                local space = math.min(needed, 64)
                -- Use slot cache instead of listing all storage peripherals
                for si, slots in pairs(storage_slots) do
                    if space <= 0 then break end
                    for slot, item in pairs(slots) do
                        if space <= 0 then break end
                        if is_fuel(item.name) then
                            if fuel_item and fuel_item.name ~= item.name then
                                -- skip different fuel type
                            else
                                local to_push = math.min(space, item.count)
                                local store = st.peripherals[si]
                                local push_ok, pushed = pcall(store.periph.pushItems, furnace.name, slot, to_push, 2)
                                if push_ok and pushed and pushed > 0 then
                                    slot_pull(si, slot, pushed, item.name, item.nbt)
                                    pushed_total = pushed_total + pushed
                                    space = space - pushed
                                    fuel_item = item
                                elseif push_ok and (pushed == 0 or not pushed) then
                                    slots[slot] = nil  -- phantom
                                end
                            end
                        end
                    end
                end
            end
        end
        return pushed_total
    end

    local function push_furnace_inputs(furnace_lists)
        if #st.furnace_peripherals == 0 or #st.peripherals == 0 then return 0 end
        local total_smeltable = st.cached_smeltable_total or 0
        if total_smeltable == 0 then return 0 end
        local FUEL_RATIO = 8  -- 1 coal/charcoal smelts 8 items
        local MIN_BATCH = 8   -- don't transfer an ore unless we have at least 8 of it
        local pushed_total = 0
        local pushed_by_item = {}   -- {item_name -> count} for per-item analytics
        local remaining = total_smeltable

        -- Build per-item stock counts, only for items that should be smelted now
        local stock = {}
        -- Track task remaining caps
        local task_remaining = {}
        for _, task in ipairs(st.smelt_tasks) do
            if task.active and task.smelted < task.target then
                task_remaining[task.input] = (task_remaining[task.input] or 0) + (task.target - task.smelted)
            end
        end
        for _, item in ipairs(st.items or {}) do
            local ok, _ = should_smelt_item(item.name)
            if ok then
                stock[item.name] = item.count
            end
        end

        -- Spread items across furnaces: 8 per furnace per cycle (one coal's worth)
        -- Multiple cycles accumulate items; this ensures all furnaces run in parallel
        local per_furnace = FUEL_RATIO

        for fi, furnace in ipairs(st.furnace_peripherals) do
            if remaining <= 0 then break end
            local list = furnace_lists[fi] or {}
            local input_item = list[1] or nil
            local input_count = input_item and input_item.count or 0

            if input_count < 64 then
                local slot_space = 64 - input_count
                local partial = input_count % FUEL_RATIO
                local allocation = 0

                if partial > 0 then
                    -- Top up to next multiple of 8 only
                    allocation = FUEL_RATIO - partial
                elseif remaining >= FUEL_RATIO then
                    -- Empty or aligned furnace: give it 8 items (one coal's worth)
                    allocation = FUEL_RATIO
                end
                allocation = math.min(allocation, slot_space)

                if allocation > 0 then
                    local space = math.min(allocation, remaining)
                    local needs_match = input_item ~= nil
                    -- Use slot cache instead of listing all storage peripherals
                    for si, slots in pairs(storage_slots) do
                        if space <= 0 then break end
                        for slot, item in pairs(slots) do
                            if space <= 0 then break end
                            local smelt_ok, _ = should_smelt_item(item.name)
                            if smelt_ok then
                                if (stock[item.name] or 0) < MIN_BATCH then
                                    -- hold in storage until we accumulate enough
                                elseif needs_match and input_item and item.name ~= input_item.name then
                                    -- skip different item type
                                else
                                    local to_push = math.min(space, item.count)
                                    -- Cap by task remaining if applicable
                                    if task_remaining[item.name] then
                                        to_push = math.min(to_push, task_remaining[item.name])
                                    end
                                    if to_push > 0 then
                                        local store = st.peripherals[si]
                                        local push_ok, pushed = pcall(store.periph.pushItems, furnace.name, slot, to_push, 1)
                                        if push_ok and (pushed == 0 or not pushed) then
                                            slots[slot] = nil  -- phantom
                                        elseif push_ok and pushed and pushed > 0 then
                                            slot_pull(si, slot, pushed, item.name, item.nbt)
                                            pushed_total = pushed_total + pushed
                                            pushed_by_item[item.name] = (pushed_by_item[item.name] or 0) + pushed
                                            space = space - pushed
                                            remaining = remaining - pushed
                                            stock[item.name] = (stock[item.name] or 0) - pushed
                                            needs_match = true
                                            input_item = item
                                            -- Track task progress
                                            if task_remaining[item.name] then
                                                task_remaining[item.name] = task_remaining[item.name] - pushed
                                                for _, task in ipairs(st.smelt_tasks) do
                                                    if task.active and task.input == item.name and task.smelted < task.target then
                                                        local credit = math.min(pushed, task.target - task.smelted)
                                                        task.smelted = task.smelted + credit
                                                        if task.smelted >= task.target then
                                                            task.active = false
                                                            save_smelt_data()
                                                            rebuild_smeltable_set()
                                                            utils.add_notification(state,
                                                                string.format("SMELT TASK DONE: %s (%d)",
                                                                    task.input_display or item.name, task.target),
                                                                colors.lime)
                                                        end
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if pushed_total > 0 then st.items_smelted = st.items_smelted + pushed_total end
        return pushed_total, pushed_by_item
    end

    local fuel_log_tick = 0
    local function stock_fuel_chest()
        fuel_log_tick = fuel_log_tick + 1
        if not st.fuel_peripheral then
            if fuel_log_tick % 30 == 1 then log("fuel: SKIP - no fuel_peripheral") end
            return
        end
        local target = st.fuel_chest_target or 128
        local fuel_name = nil
        for name, role in pairs(st.names) do
            if role == "fuel" then fuel_name = name; break end
        end
        if not fuel_name then
            if fuel_log_tick % 30 == 1 then log("fuel: SKIP - no 'fuel' in st.names") end
            return
        end

        local ok, list = pcall(st.fuel_peripheral.list)
        if not ok or not list then
            if fuel_log_tick % 30 == 1 then log("fuel: SKIP - list failed: " .. tostring(list)) end
            return
        end

        local current_fuel = 0
        local non_fuel_slots = {}
        for slot, item in pairs(list) do
            if is_fuel(item.name) then current_fuel = current_fuel + item.count
            else table.insert(non_fuel_slots, slot) end
        end
        st.fuel_chest_level = current_fuel

        -- Push non-fuel items out using the rotating index
        -- Use a LOCAL full cache so we don't pollute the import cache
        if #non_fuel_slots > 0 then
            local saved_full = full_peripherals
            for _, slot in ipairs(non_fuel_slots) do
                full_peripherals = {}
                push_to_storage(st.fuel_peripheral, slot)
            end
            full_peripherals = saved_full  -- restore import cache
        end

        if current_fuel < target then
            local need = target - current_fuel
            local cached = st.cached_fuel_total or 0
            -- Reserve: don't drain storage below 128 fuel items
            local reserve = config.smelting.fuel_reserve or 128
            local available = math.max(0, cached - reserve)
            if available <= 0 then
                if fuel_log_tick % 30 == 1 then
                    log(string.format("fuel: level=%d/%d, need=%d but only %d in storage (reserve %d) — skipping",
                        current_fuel, target, need, cached, reserve))
                end
            else
                need = math.min(need, available)
                -- Log fuel status every 10 ticks (~10s) or when there's a deficit
                if fuel_log_tick % 10 == 1 then
                    log(string.format("fuel: level=%d/%d, need=%d, cached_in_storage=%d (reserve=%d), peripherals=%d",
                        current_fuel, target, need, cached, reserve, #st.peripherals))
                end
                -- Use slot cache instead of listing all storage peripherals
                refresh_dirty()
                local pushed_total = 0
                for si, slots in pairs(storage_slots) do
                    if need <= 0 then break end
                    for slot, item in pairs(slots) do
                        if need <= 0 then break end
                        if is_fuel(item.name) then
                            local to_push = math.min(need, item.count)
                            local store = st.peripherals[si]
                            local push_ok, pushed = pcall(store.periph.pushItems, fuel_name, slot, to_push)
                            if push_ok and pushed and pushed > 0 then
                                slot_pull(si, slot, pushed, item.name, item.nbt)
                                need = need - pushed
                                pushed_total = pushed_total + pushed
                            elseif push_ok and (pushed == 0 or not pushed) then
                                slots[slot] = nil  -- phantom
                            end
                        end
                    end
                end
                if pushed_total > 0 then
                    log(string.format("fuel: pushed %d to fuel chest", pushed_total))
                end
            end
        elseif current_fuel > target then
            local excess = current_fuel - target
            for slot, item in pairs(list) do
                if excess <= 0 then break end
                if is_fuel(item.name) then
                    local to_push = math.min(excess, item.count)
                    for _, store in ipairs(st.peripherals) do
                        local push_ok, pushed = pcall(st.fuel_peripheral.pushItems, store.name, slot, to_push)
                        if push_ok and pushed and pushed > 0 then excess = excess - pushed; break end
                    end
                end
            end
        end
    end

    -- ==================
    -- Analytics tracking
    -- ==================
    local analytics = state.analytics

    local function get_minute()
        return math.floor(os.clock() / 60)
    end

    local function get_bucket()
        local m = get_minute()
        if m ~= analytics.current_minute then
            analytics.current_minute = m
            -- Trim buckets older than 30 minutes
            for k, _ in pairs(analytics.buckets) do
                if k < m - 30 then analytics.buckets[k] = nil end
            end
        end
        if not analytics.buckets[m] then
            analytics.buckets[m] = {extracted = 0, imported = 0, smelted_in = 0, smelted_out = 0, fuel_pushed = 0}
        end
        return analytics.buckets[m]
    end

    log_analytics = function(event_type, count, item_display)
        if count <= 0 then return end
        local b = get_bucket()
        if b[event_type] then
            b[event_type] = b[event_type] + count
        end
        analytics.totals[event_type] = (analytics.totals[event_type] or 0) + count

        -- Track top extracted items
        if event_type == "extracted" and item_display then
            analytics.top_extracted[item_display] = (analytics.top_extracted[item_display] or 0) + count
        end

        -- Track top imported items
        if event_type == "imported" and item_display then
            analytics.top_imported[item_display] = (analytics.top_imported[item_display] or 0) + count
        end

        -- Track items consumed by crafting
        if event_type == "craft_used" and item_display then
            analytics.top_craft_used[item_display] = (analytics.top_craft_used[item_display] or 0) + count
        end

        -- Track items consumed by smelting
        if event_type == "smelt_used" and item_display then
            analytics.top_smelt_used[item_display] = (analytics.top_smelt_used[item_display] or 0) + count
        end

        -- Update peak rate
        if event_type == "extracted" or event_type == "imported" then
            local rate = (b.extracted or 0) + (b.imported or 0)
            if rate > analytics.peak_items_min then
                analytics.peak_items_min = rate
            end
        end
    end

    log_capacity = function()
        if st.stats then
            table.insert(analytics.capacity_log, {os.clock(), st.stats.usage_pct})
            -- Keep last 60 entries
            while #analytics.capacity_log > 60 do
                table.remove(analytics.capacity_log, 1)
            end
        end
    end

    local function run_smelt_cycle()
        -- Output pulling is handled in the main loop (every heavy tick)
        -- This function only handles input pushing and fuel
        if not st.smelting_enabled then return end

        local furnace_lists = {}
        for fi, furnace in ipairs(st.furnace_peripherals) do
            local ok, list = pcall(furnace.periph.list)
            furnace_lists[fi] = ok and list or {}
        end
        -- Refresh dirty storage slots so slot cache is current
        refresh_dirty()

        local fuel = 0
        local pushed_in = 0
        local smelt_items = nil
        if config.smelting.auto_push_input then pushed_in, smelt_items = push_furnace_inputs(furnace_lists) end
        -- Re-scan furnaces so fuel logic sees items we just pushed
        if pushed_in > 0 then
            for fi, furnace in ipairs(st.furnace_peripherals) do
                local ok, list = pcall(furnace.periph.list)
                furnace_lists[fi] = ok and list or {}
            end
        end
        if config.smelting.auto_push_fuel ~= false then fuel = push_furnace_fuel(furnace_lists) end
        log_analytics("fuel_pushed", fuel)
        log_analytics("smelted_in", pushed_in)
        -- Per-item smelting consumption tracking
        if smelt_items then
            for item_name, count in pairs(smelt_items) do
                local display = utils.clean_name(item_name)
                log_analytics("smelt_used", count, display)
            end
        end
    end

    -- ==================
    -- Stack Consolidation
    -- ==================
    -- Merges partial stacks of the same item to free slots.
    -- One operation per call — gentle on peripherals.
    local stack_last_key = ""

    local function stack_consolidate_step()
        refresh_dirty()

        -- Build item_key -> list of locations
        local item_locs = {}
        local keys_order = {}

        for si, slots in pairs(storage_slots) do
            for slot, item in pairs(slots) do
                local key = item.name .. "|" .. (item.nbt or "")
                if not item_locs[key] then
                    item_locs[key] = {}
                    table.insert(keys_order, key)
                end
                table.insert(item_locs[key], {
                    si = si, slot = slot, count = item.count,
                    name = item.name, nbt = item.nbt,
                })
            end
        end

        table.sort(keys_order)

        -- Count fragmented item types (multiple stacks of same item)
        local frag_count = 0
        for _, key in ipairs(keys_order) do
            if #item_locs[key] > 1 then frag_count = frag_count + 1 end
        end
        st.stack_stats.fragmented = frag_count

        if frag_count == 0 then
            st.stack_stats.last_result = "fully stacked"
            return
        end

        -- Round-robin: find next fragmented key after last one
        local target_key = nil
        local started = false
        for _, key in ipairs(keys_order) do
            if not started then
                if key > stack_last_key then started = true end
            end
            if started and #item_locs[key] > 1 then
                target_key = key
                break
            end
        end
        if not target_key then
            for _, key in ipairs(keys_order) do
                if #item_locs[key] > 1 then target_key = key; break end
            end
        end
        if not target_key then return end

        local locs = item_locs[target_key]
        -- Sort smallest first so we merge small stacks into larger ones
        table.sort(locs, function(a, b) return a.count < b.count end)

        local src = locs[1]
        for i = #locs, 2, -1 do
            local dst = locs[i]
            if src.si ~= dst.si or src.slot ~= dst.slot then
                local src_store = st.peripherals[src.si]
                local dst_store = st.peripherals[dst.si]
                if src_store and dst_store then
                    local ok, pushed = pcall(src_store.periph.pushItems,
                        dst_store.name, src.slot, src.count, dst.slot)
                    if ok and pushed and pushed > 0 then
                        -- Update source slot cache
                        local ss = storage_slots[src.si]
                        if ss and ss[src.slot] then
                            ss[src.slot].count = ss[src.slot].count - pushed
                            if ss[src.slot].count <= 0 then
                                ss[src.slot] = nil
                                st.stack_stats.slots_freed = st.stack_stats.slots_freed + 1
                                -- Update live storage stats
                                if st.stats then
                                    st.stats.used_slots = st.stats.used_slots - 1
                                    st.stats.free_slots = st.stats.total_slots - st.stats.used_slots
                                    st.stats.usage_pct = st.stats.total_slots > 0
                                        and (st.stats.used_slots / st.stats.total_slots) or 0
                                end
                                local display = utils.clean_name(src.name)
                                utils.add_notification(state,
                                    string.format("DEFRAG: freed slot (%s) | %d total",
                                        display:sub(1, 16), st.stack_stats.slots_freed),
                                    colors.lime)
                            end
                        end
                        -- Update dest slot cache
                        local ds = storage_slots[dst.si]
                        if ds and ds[dst.slot] then
                            ds[dst.slot].count = ds[dst.slot].count + pushed
                        end

                        st.stack_stats.ops = st.stack_stats.ops + 1
                        st.stack_stats.items_moved = st.stack_stats.items_moved + pushed
                        local display = utils.clean_name(src.name)
                        st.stack_stats.last_result = string.format("%dx %s", pushed, display:sub(1, 20))
                        st.stack_stats.last_time = os.clock()
                        stack_last_key = target_key

                        log(string.format("stack: merged %d %s (freed=%d, frag=%d)",
                            pushed, src.name, st.stack_stats.slots_freed, frag_count))
                        return
                    end
                end
            end
        end

        -- Couldn't merge (all destination stacks at max)
        stack_last_key = target_key
        st.stack_stats.last_result = "skip: full stacks"
    end

    -- Expose functions via state (with analytics wrappers)
    st.extract = function(item, amount)
        local count = extract_item(item, amount)
        if count > 0 then full_reset_needed = true end  -- freed space in storage
        log_analytics("extracted", count, item.displayName)
        return count
    end

    -- Withdraw: try player inventory first, fall back to output chest
    st.withdraw = function(item, amount)
        local ld = state.loadouts
        local given = 0
        local remaining = amount

        -- Try player inventory via IM
        if ld and ld.give_to_player then
            given, remaining = ld.give_to_player(item.name, item.nbt, amount, item.displayName)
        end

        -- Fall back to output chest for any remaining
        local chest_count = 0
        if remaining > 0 then
            chest_count = extract_item(item, remaining)
        end

        local total = given + chest_count
        log_analytics("extracted", total, item.displayName)

        -- Status feedback
        if given > 0 and chest_count > 0 then
            utils.set_status(state,
                string.format("%sx to inventory, %sx to chest: %s",
                    utils.format_number(given), utils.format_number(chest_count),
                    utils.truncate(item.displayName, 14)),
                colors.lime, 3)
        elseif given > 0 then
            utils.set_status(state,
                string.format("Sent %sx %s to inventory",
                    utils.format_number(given), utils.truncate(item.displayName, 18)),
                colors.lime, 3)
        end
        -- chest-only case is already handled by extract_item's own status

        return total
    end
    st.import = function()
        return import_items()  -- analytics logged internally with per-item tracking
    end
    st.extract_to_peripheral = function(target_name, item_name, amount)
        local count = extract_to_peripheral(target_name, item_name, amount)
        if count > 0 then full_reset_needed = true end
        return count
    end
    st.import_from_peripheral = function(source_name)
        -- Pull all items from a named peripheral into storage
        local source = peripheral.wrap(source_name)
        if not source or not source.list then return 0 end
        local imported = 0
        local ok, list = pcall(source.list)
        if ok and list then
            for slot, item in pairs(list) do
                local pushed = push_to_storage(source, slot, item.name, item.nbt)
                imported = imported + pushed
                if pushed > 0 then cache_adjust(item.name, item.nbt, pushed) end
            end
        end
        if imported > 0 then full_reset_needed = true end
        return imported
    end
    st.get_import_info = function()
        return {
            last_time = import_last_time,
            total_session = import_total_session,
            tick_count = import_tick_count,
        }
    end
    st.get_stats = function() return st.stats end

    -- Pull items from storage to any destination (uses slot cache + updates both caches)
    -- any_nbt: if true, match item by name only (ignore NBT)
    st.pull_from_storage = function(dest_name, item_name, item_nbt, amount, any_nbt)
        refresh_dirty()
        local remaining = amount
        for si, slots in pairs(storage_slots) do
            if remaining <= 0 then break end
            for slot, slot_item in pairs(slots) do
                if remaining <= 0 then break end
                if slot_item.name == item_name and
                   (any_nbt or slot_item.nbt == item_nbt or (not slot_item.nbt and not item_nbt)) then
                    local to_push = math.min(remaining, slot_item.count)
                    local store = st.peripherals[si]
                    local push_ok, pushed = pcall(store.periph.pushItems, dest_name, slot, to_push)
                    if push_ok and pushed and pushed > 0 then
                        remaining = remaining - pushed
                        slot_pull(si, slot, pushed, slot_item.name, slot_item.nbt)
                    elseif push_ok and (pushed == 0 or not pushed) then
                        -- Phantom entry: slot is empty or item gone, remove from cache
                        slots[slot] = nil
                    end
                end
            end
        end
        if remaining < amount then full_reset_needed = true end
        return amount - remaining
    end

    -- Pull items from storage to a specific slot in the destination
    -- Used by crafting to push ingredients to exact turtle grid slots
    st.pull_to_slot = function(dest_name, dest_slot, item_name, item_nbt, amount, any_nbt)
        refresh_dirty()
        local remaining = amount
        for si, slots in pairs(storage_slots) do
            if remaining <= 0 then break end
            for slot, slot_item in pairs(slots) do
                if remaining <= 0 then break end
                if slot_item.name == item_name and
                   (any_nbt or slot_item.nbt == item_nbt or (not slot_item.nbt and not item_nbt)) then
                    local to_push = math.min(remaining, slot_item.count)
                    local store = st.peripherals[si]
                    local push_ok, pushed = pcall(store.periph.pushItems, dest_name, slot, to_push, dest_slot)
                    if push_ok and pushed and pushed > 0 then
                        remaining = remaining - pushed
                        slot_pull(si, slot, pushed, slot_item.name, slot_item.nbt)
                    elseif push_ok and (pushed == 0 or not pushed) then
                        slots[slot] = nil
                    end
                end
            end
        end
        if remaining < amount then full_reset_needed = true end
        return amount - remaining
    end

    -- Notify cache that items were removed from storage by external code
    st.notify_withdrawn = function(item_name, nbt, count, periph_name)
        cache_adjust(item_name, nbt, -count)
        if periph_name then
            for si, store in ipairs(st.peripherals) do
                if store.name == periph_name then
                    dirty_peripherals[si] = true
                    break
                end
            end
        end
        full_reset_needed = true
    end

    -- Notify cache that items were added to storage by external code
    st.notify_deposited = function(item_name, nbt, count, periph_name)
        cache_adjust(item_name, nbt, count)
        if periph_name then
            for si, store in ipairs(st.peripherals) do
                if store.name == periph_name then
                    dirty_peripherals[si] = true
                    break
                end
            end
        end
        full_reset_needed = true
    end

    st.get_filtered = function(query)
        if not query or query == "" then return st.items end
        local q = query:lower()
        local results = {}
        for _, item in ipairs(st.items) do
            if item.displayName:lower():find(q, 1, true) or
               item.name:lower():find(q, 1, true) then
                table.insert(results, item)
            end
        end
        return results
    end

    st.get_stock_color = function(count)
        if count <= config.storage.critical_stock_threshold then return colors.red
        elseif count <= config.storage.low_stock_threshold then return colors.yellow
        else return colors.lime end
    end

    st.toggle_smelting = function()
        st.smelting_enabled = not st.smelting_enabled
        local status = st.smelting_enabled and "ON" or "OFF"
        utils.set_status(state, "Auto-Smelt: " .. status, st.smelting_enabled and colors.lime or colors.lightGray, 3)
        local saved = load_saved_config() or {}
        saved.smelting_enabled = st.smelting_enabled
        save_config(saved)
        return st.smelting_enabled
    end

    st.set_smelting = function(on)
        st.smelting_enabled = on
        local saved = load_saved_config() or {}
        saved.smelting_enabled = st.smelting_enabled
        save_config(saved)
    end

    st.get_smelting_stats = function()
        return {
            enabled = st.smelting_enabled, furnace_count = st.furnace_count,
            items_smelted = st.items_smelted, items_pulled = st.items_pulled,
        }
    end

    st.setup_output = function(chosen_name)
        local all = st.available_peripherals or {}
        local found = false
        for _, p in ipairs(all) do if p.name == chosen_name then found = true; break end end
        if not found then return false, "Peripheral not found" end
        local saved = load_saved_config() or {}
        saved.output = chosen_name
        if save_config(saved) then
            discover_peripherals()
            scan_all_items()
            utils.add_notification(state, "SETUP: Output -> " .. chosen_name, colors.lime)
            return true
        end
        return false, "Failed to save"
    end

    st.clear_output = function()
        local saved = load_saved_config() or {}
        saved.output = nil
        if save_config(saved) then
            discover_peripherals()
            scan_all_items()
            return true
        end
        return false
    end

    st.add_depot = function(chosen_name)
        local saved = load_saved_config() or {}
        if not saved.depots then saved.depots = {} end
        for _, d in ipairs(saved.depots) do if d == chosen_name then return false, "Already a depot" end end
        table.insert(saved.depots, chosen_name)
        if save_config(saved) then
            discover_peripherals()
            scan_all_items()
            utils.add_notification(state, "SETUP: Added depot " .. chosen_name, colors.lime)
            return true
        end
        return false
    end

    st.remove_depot = function(chosen_name)
        local saved = load_saved_config() or {}
        if not saved.depots then return false end
        for i, d in ipairs(saved.depots) do
            if d == chosen_name then
                table.remove(saved.depots, i)
                if save_config(saved) then
                    discover_peripherals()
                    scan_all_items()
                    return true
                end
                return false
            end
        end
        return false
    end

    st.get_assignments = function()
        local output_name, depot_names, fuel_name = nil, {}, nil
        for name, role in pairs(st.names) do
            if role == "output" then output_name = name end
            if role == "depot" then table.insert(depot_names, name) end
            if role == "fuel" then fuel_name = name end
        end
        table.sort(depot_names)
        return {
            output = output_name or "Not set",
            output_ok = st.output_peripheral ~= nil,
            output_as_depot = st.output_as_depot,
            fuel = fuel_name or "Not set",
            fuel_ok = st.fuel_peripheral ~= nil,
            depots = depot_names,
            depot_count = #st.depot_peripherals,
        }
    end

    st.toggle_output_depot = function()
        st.output_as_depot = not st.output_as_depot
        local saved = load_saved_config() or {}
        saved.output_as_depot = st.output_as_depot
        save_config(saved)
        return st.output_as_depot
    end

    st.setup_fuel = function(chosen_name)
        local saved = load_saved_config() or {}
        saved.fuel_chest = chosen_name
        if save_config(saved) then discover_peripherals(); scan_all_items(); return true end
        return false
    end

    st.clear_fuel = function()
        local saved = load_saved_config() or {}
        saved.fuel_chest = nil
        if save_config(saved) then discover_peripherals(); scan_all_items(); return true end
        return false
    end

    st.list_peripherals = function() return st.available_peripherals or {} end

    st.set_label = function(name, label)
        local saved = load_saved_config() or {}
        if not saved.labels then saved.labels = {} end
        saved.labels[name] = label
        if save_config(saved) then st.labels = saved.labels; return true end
        return false
    end

    st.get_label = function(name) return (st.labels or {})[name] end
    st.get_all_labels = function() return st.labels or {} end
    st.rescan = function()
        log("Manual rescan triggered")
        discover_peripherals()
        scan_all_items()
        return #st.available_peripherals
    end


    -- ==================
    -- Smelt Rules API
    -- ==================
    st.add_smelt_rule = function(input, output, threshold, enabled, input_display, output_display)
        local rule = {
            input = input,
            output = output or "",
            threshold = threshold or 0,
            enabled = enabled ~= false,
            input_display = input_display or utils.clean_name(input),
            output_display = output_display or (output and utils.clean_name(output) or ""),
        }
        table.insert(st.smelt_rules, rule)
        save_smelt_data()
        rebuild_smeltable_set()
        utils.add_notification(state,
            string.format("SMELT: Rule added - %s", rule.input_display), colors.lime)
        return #st.smelt_rules
    end

    st.remove_smelt_rule = function(idx)
        if st.smelt_rules[idx] then
            local name = st.smelt_rules[idx].input_display or "?"
            table.remove(st.smelt_rules, idx)
            save_smelt_data()
            rebuild_smeltable_set()
            utils.add_notification(state,
                string.format("SMELT: Rule removed - %s", name), colors.orange)
            return true
        end
        return false
    end

    st.update_smelt_rule = function(idx, field, value)
        if st.smelt_rules[idx] then
            st.smelt_rules[idx][field] = value
            save_smelt_data()
            if field == "enabled" or field == "input" then
                rebuild_smeltable_set()
            end
            return true
        end
        return false
    end

    st.get_smelt_rules = function()
        return st.smelt_rules
    end

    -- ==================
    -- Smelt Tasks API
    -- ==================
    st.add_smelt_task = function(input, target, input_display)
        local task = {
            input = input,
            target = target,
            smelted = 0,
            active = true,
            input_display = input_display or utils.clean_name(input),
        }
        table.insert(st.smelt_tasks, task)
        save_smelt_data()
        rebuild_smeltable_set()
        utils.add_notification(state,
            string.format("SMELT TASK: %s x%d", task.input_display, target), colors.cyan)
        return #st.smelt_tasks
    end

    st.cancel_smelt_task = function(idx)
        if st.smelt_tasks[idx] then
            st.smelt_tasks[idx].active = false
            save_smelt_data()
            rebuild_smeltable_set()
            return true
        end
        return false
    end

    st.get_smelt_tasks = function()
        return st.smelt_tasks
    end

    st.clear_completed_tasks = function()
        local new_tasks = {}
        for _, task in ipairs(st.smelt_tasks) do
            if task.active then
                table.insert(new_tasks, task)
            end
        end
        st.smelt_tasks = new_tasks
        save_smelt_data()
    end

    -- ==================
    -- Main loop
    -- ==================
    -- Defer discovery to kernel event loop so sleep(0) yields work correctly
    -- (boot.lua's sleep(0.3) would consume our timer events during boot)
    log("Deferring discovery to kernel event loop")
    utils.set_status(state, "Scanning peripherals...", colors.cyan)
    local init_timer = os.startTimer(0.1)
    coroutine.yield("timer")  -- yield back to boot, resume in kernel loop
    log("Resumed in kernel loop, starting discovery")

    local ok_disc, found = pcall(discover_peripherals)
    if not ok_disc then
        log("discover_peripherals CRASHED: " .. tostring(found))
        utils.add_notification(state, "STORAGE CRASH: " .. tostring(found), colors.red)
        found = false
    end

    if not found then
        utils.set_status(state, "Waiting for storage peripherals...", colors.orange)
        utils.add_notification(state, "STORAGE: No peripherals detected - waiting", colors.orange)
        local retry_timer = os.startTimer(3)
        while not found do
            local ev = {coroutine.yield()}
            if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
                found = discover_peripherals()
                if not found then retry_timer = os.startTimer(3) end
            elseif ev[1] == "timer" and ev[2] == retry_timer then
                found = discover_peripherals()
                if not found then retry_timer = os.startTimer(3) end
            end
        end
    end

    utils.set_status(state,
        string.format("Found %d storage, %d furnaces", #st.peripherals, st.furnace_count),
        colors.lime, 3)
    utils.add_notification(state, string.format("STORAGE: %d units online", #st.peripherals), colors.lime)

    if st.furnace_count > 0 then
        utils.add_notification(state, string.format("SMELT: %d furnaces detected", st.furnace_count), colors.orange)
    end

    -- Report assignments
    local assign = st.get_assignments()
    if assign.output_ok then
        utils.add_notification(state, "WITHDRAW: " .. assign.output, colors.cyan)
    else
        utils.add_notification(state, "WITHDRAW: Not configured - use Settings", colors.orange)
    end
    if assign.depot_count > 0 then
        utils.add_notification(state, string.format("DEPOTS: %d input points", assign.depot_count), colors.cyan)
    end

    -- Run an early import pass BEFORE the slow initial scan so depot items
    -- don't sit for 20+ seconds while display names are resolved
    if #st.depot_peripherals > 0 or (st.output_as_depot and st.output_peripheral) then
        log("Early import pass (pre-scan)")
        local early = import_items()
        if early > 0 then
            log("Early import: " .. early .. " items pulled from depots")
        end
    end

    scan_all_items()
    -- Clear full_peripherals cache from early import so main loop starts fresh
    reset_full_cache()

    -- Initialize stack consolidation stats
    st.stack_stats = {
        ops = 0, slots_freed = 0, items_moved = 0,
        fragmented = 0, last_result = "starting", last_time = 0,
    }

    utils.add_notification(state,
        string.format("STORAGE: %s items indexed (%d types)", utils.format_number(st.item_count), st.type_count),
        colors.cyan)

    -- Restore smelting toggle + rules/tasks
    local saved_smelt = load_saved_config()
    if saved_smelt and saved_smelt.smelting_enabled ~= nil then
        st.smelting_enabled = saved_smelt.smelting_enabled
    else
        st.smelting_enabled = config.smelting.enabled
    end
    if saved_smelt then
        st.smelt_rules = saved_smelt.smelt_rules or {}
        st.smelt_tasks = saved_smelt.smelt_tasks or {}
    end

    -- Import legacy config items as initial rules (first boot only)
    if #st.smelt_rules == 0 and #st.smelt_tasks == 0
       and config.smelting.smeltable_items and #config.smelting.smeltable_items > 0 then
        local known_outputs = {
            ["minecraft:raw_iron"]      = "minecraft:iron_ingot",
            ["minecraft:raw_gold"]      = "minecraft:gold_ingot",
            ["minecraft:raw_copper"]    = "minecraft:copper_ingot",
            ["minecraft:ancient_debris"] = "minecraft:netherite_scrap",
            ["minecraft:cobblestone"]   = "minecraft:stone",
            ["minecraft:sand"]          = "minecraft:glass",
            ["minecraft:clay_ball"]     = "minecraft:brick",
            ["minecraft:iron_ore"]      = "minecraft:iron_ingot",
            ["minecraft:gold_ore"]      = "minecraft:gold_ingot",
            ["minecraft:copper_ore"]    = "minecraft:copper_ingot",
        }
        for _, item_name in ipairs(config.smelting.smeltable_items) do
            local output = known_outputs[item_name] or ""
            table.insert(st.smelt_rules, {
                input = item_name,
                output = output,
                threshold = 0,
                enabled = true,
                input_display = utils.clean_name(item_name),
                output_display = output ~= "" and utils.clean_name(output) or "",
            })
        end
        save_smelt_data()
        utils.add_notification(state,
            string.format("SMELT: Imported %d items from config as rules", #st.smelt_rules), colors.lime)
    end

    rebuild_smeltable_set()

    local rule_count = #st.smelt_rules
    local task_count = 0
    for _, t in ipairs(st.smelt_tasks) do if t.active then task_count = task_count + 1 end end
    if rule_count > 0 or task_count > 0 then
        utils.add_notification(state,
            string.format("SMELT: %d rules, %d active tasks loaded", rule_count, task_count), colors.cyan)
    end

    -- Restore analytics from previous session
    load_analytics()

    -- Main loop: single timer drives import + staggered heavy ops.
    -- No periodic full scan — item cache is updated incrementally.
    local TICK_INTERVAL    = 0.2  -- base tick rate (matches import)
    local import_interval  = config.storage.import_interval or 0.2
    local HEAVY_INTERVAL   = 2   -- seconds between heavy ops (fuel/smelt)
    local farm_strip_done  = false  -- deferred farm chest cleanup (after farms service loads)

    local now = os.clock()
    local next_import = now + import_interval
    local next_heavy  = now + HEAVY_INTERVAL
    local heavy_turn  = 0  -- 0=fuel, 1=smelt (one per cycle)
    local analytics_clock = 0

    local tick_timer = os.startTimer(TICK_INTERVAL)
    log("Single-timer loop started, tick=" .. TICK_INTERVAL .. "s (no periodic scan)")

    while state.running do
        local ev = {coroutine.yield()}

        if ev[1] == "timer" and ev[2] == tick_timer then
            now = os.clock()

            -- Deferred farm chest cleanup: runs once after farms service has loaded
            if not farm_strip_done and state.farms and state.farms.ready then
                local before = #st.peripherals
                strip_farm_chests()
                farm_strip_done = true
                if #st.peripherals < before then
                    log("DEFERRED STRIP: removed " .. (before - #st.peripherals) .. " farm chests that slipped past initial discovery")
                    scan_all_items()
                    reset_full_cache()
                end
            end

            -- Import (every ~0.2s)
            if now >= next_import then
                next_import = now + import_interval
                import_tick_count = import_tick_count + 1
                local depot_count = #st.depot_peripherals + (st.output_as_depot and st.output_peripheral and 1 or 0)
                if depot_count > 0 and #st.peripherals > 0 then
                    import_items()
                end

                -- Import diagnostics
                local is_diag_tick = import_tick_count % 25 == 0
                local is_idle_tick = import_tick_count % 150 == 0
                if is_diag_tick then
                    if depot_count == 0 and is_idle_tick then
                        utils.add_notification(state,
                            string.format("IMPORT: no depots configured (%d storage)", #st.peripherals),
                            colors.orange)
                    elseif #st.peripherals == 0 and is_idle_tick then
                        utils.add_notification(state,
                            string.format("IMPORT: no storage peripherals, %d depots", depot_count),
                            colors.orange)
                    elseif import_stuck_count > 10 then
                        utils.add_notification(state,
                            string.format("IMPORT: %d slots STUCK, %d depots, %d storage",
                                import_slots_last, depot_count, #st.peripherals),
                            colors.red)
                    elseif import_slots_last > 0 then
                        utils.add_notification(state,
                            string.format("IMPORT: %d depot slots, session=%s",
                                import_slots_last, utils.format_number(import_total_session)),
                            colors.cyan)
                    elseif is_idle_tick then
                        local full_count = 0
                        for _ in pairs(full_peripherals) do full_count = full_count + 1 end
                        local ago_str = "never"
                        if import_last_time > 0 then
                            local ago = math.floor(os.clock() - import_last_time)
                            if ago < 60 then ago_str = ago .. "s ago"
                            else ago_str = math.floor(ago / 60) .. "m ago" end
                        end
                        utils.add_notification(state,
                            string.format("IMPORT: idle, last=%s, session=%s",
                                ago_str, utils.format_number(import_total_session)),
                            colors.lightGray)
                    end
                end
            end

            -- One heavy op per cycle (staggered to keep import responsive)
            if now >= next_heavy then
                -- Always pull furnace outputs (cheap, keeps furnaces running)
                if st.furnace_count > 0 and config.smelting.auto_pull_output then
                    local furnace_lists = {}
                    for fi, furnace in ipairs(st.furnace_peripherals) do
                        local ok, list = pcall(furnace.periph.list)
                        furnace_lists[fi] = ok and list or {}
                    end
                    local pulled = pull_furnace_outputs(furnace_lists)
                    log_analytics("smelted_out", pulled)
                end

                if heavy_turn == 0 then
                    stock_fuel_chest()
                    heavy_turn = 1
                elseif heavy_turn == 1 then
                    if st.furnace_count > 0 then run_smelt_cycle() end
                    heavy_turn = 2
                else
                    stack_consolidate_step()
                    heavy_turn = 0
                end
                next_heavy = os.clock() + HEAVY_INTERVAL
                full_reset_needed = true  -- heavy ops may have freed storage space
            end

            -- Clear expired status
            if state.status_timeout > 0 and os.clock() > state.status_timeout then
                utils.clear_status(state)
            end

            -- Rebuild item list from cache if anything changed
            rebuild_item_list()

            -- Periodic analytics save + capacity log
            analytics_clock = analytics_clock + TICK_INTERVAL
            if analytics_clock >= ANALYTICS_SAVE_INTERVAL then
                analytics_clock = 0
                log_capacity()
                save_analytics()
            end

            tick_timer = os.startTimer(TICK_INTERVAL)

        elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            -- Peripheral added/removed: rediscover
            local periph_delay = os.startTimer(0.5)
            while true do
                local pe = {coroutine.yield()}
                if pe[1] == "timer" and pe[2] == periph_delay then break end
                os.queueEvent(pe[1], pe[2], pe[3], pe[4], pe[5])
            end
            discover_peripherals()
            scan_all_items()
            reset_full_cache()
            utils.add_notification(state,
                string.format("STORAGE: Rescan - %d units", #st.peripherals), colors.cyan)
            -- Reset schedules
            now = os.clock()
            next_import = now + import_interval
            next_heavy  = now + HEAVY_INTERVAL
        end
    end
end

return svc
