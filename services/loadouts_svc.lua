-- =============================================
-- WRAITH OS - LOADOUTS SERVICE
-- =============================================
-- Inventory Manager integration for player gear
-- snapshots, strip, and equip via buffer barrel.
--
-- Physical layout per IM:
--   [Player]              <- standing on top
--   [Inventory Manager]   <- wired modem on side
--   [Barrel]              <- directly under IM (buffer)
--
-- Equip flow:  storage -> barrel -> player (via IM "bottom")
-- Strip flow:  player -> barrel (via IM "bottom") -> storage

local svc = {}

function svc.main(state, config, utils)
    local ld = state.loadouts
    local cfg = config.loadouts
    local st = state.storage

    -- ========================================
    -- Persistence
    -- ========================================
    local SAVE_PATH = cfg.save_file

    local function save_data()
        local data = {
            saved = ld.saved,
            buffer_barrels = ld.buffer_barrels,
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

    local function load_data()
        if fs.exists(SAVE_PATH) then
            local file = fs.open(SAVE_PATH, "r")
            if file then
                local raw = file.readAll()
                file.close()
                local fn = loadstring("return " .. raw)
                if fn then
                    local ok, data = pcall(fn)
                    if ok and type(data) == "table" then
                        if data.saved then
                            ld.saved = data.saved
                        end
                        if data.buffer_barrels then
                            ld.buffer_barrels = data.buffer_barrels
                        end
                    end
                end
            end
        end
    end

    -- ========================================
    -- Buffer Barrel Helpers
    -- ========================================
    local function get_buffer_barrel(im_name)
        local barrel_name = ld.buffer_barrels[im_name]
        if not barrel_name then return nil, nil end
        local barrel = peripheral.wrap(barrel_name)
        if not barrel then return nil, nil end
        return barrel, barrel_name
    end

    -- Push all items from barrel back into storage
    local function drain_barrel(barrel, barrel_name)
        local ok, list = pcall(barrel.list)
        if not ok or not list then return 0 end
        local drained = 0
        for slot, item in pairs(list) do
            if item and item.name then
                -- Push to any storage peripheral that has space
                for _, store in ipairs(st.peripherals) do
                    local push_ok, pushed = pcall(barrel.pushItems, store.name, slot)
                    if push_ok and pushed and pushed > 0 then
                        drained = drained + pushed
                        -- Notify storage cache items returned
                        if st.notify_deposited then
                            st.notify_deposited(item.name, item.nbt, pushed, store.name)
                        end
                        break
                    end
                end
            end
        end
        return drained
    end

    -- ========================================
    -- Storage Search
    -- ========================================
    -- Find item by name, preferring exact NBT match but falling back to name-only
    local function find_item_in_storage(item_name, item_nbt)
        local fallback_store, fallback_slot, fallback_item = nil, nil, nil
        for _, store in ipairs(st.peripherals) do
            local ok, list = pcall(store.periph.list)
            if ok and list then
                for slot, item in pairs(list) do
                    if item.name == item_name then
                        -- Exact NBT match - return immediately
                        if item.nbt == item_nbt then
                            return store, slot, item
                        end
                        -- Name match without exact NBT - save as fallback
                        if not fallback_store then
                            fallback_store = store
                            fallback_slot = slot
                            fallback_item = item
                        end
                    end
                end
            end
        end
        return fallback_store, fallback_slot, fallback_item
    end

    -- ========================================
    -- IM Discovery
    -- ========================================
    local function scan_managers()
        local managers = {}
        local all = {peripheral.find("inventoryManager")}
        for _, im in ipairs(all) do
            local name = peripheral.getName(im)
            local ok, owner = pcall(im.getOwner)
            managers[name] = {
                name = name,
                owner = ok and owner or "unknown",
                online = true,
                buffer = ld.buffer_barrels[name] or nil,
            }
        end
        ld.managers = managers
    end

    -- ========================================
    -- Player Detection (which IMs have players?)
    -- ========================================
    local function find_ims_with_players()
        local results = {}
        for im_name, mgr in pairs(ld.managers) do
            if mgr.buffer then
                local im = peripheral.wrap(im_name)
                if im then
                    local ok, owner = pcall(im.getOwner)
                    if ok and owner and owner ~= "" then
                        table.insert(results, {
                            im_name = im_name,
                            owner = owner,
                            barrel_name = mgr.buffer,
                        })
                    end
                end
            end
        end
        return results
    end

    -- Filter IM list to only players near the computer (within 5 blocks of playerDetector)
    local function filter_nearby(active)
        if #active <= 1 then return active end
        local detector = state.lighting and state.lighting.detector
        if not detector then return active end
        local close_ok, close_players = pcall(detector.getPlayersInRange, 5)
        if not close_ok or not close_players or #close_players == 0 then return active end
        local close_set = {}
        for _, name in ipairs(close_players) do
            close_set[name] = true
        end
        local filtered = {}
        for _, a in ipairs(active) do
            if close_set[a.owner] then
                table.insert(filtered, a)
            end
        end
        return #filtered > 0 and filtered or active
    end

    -- ========================================
    -- Find Best IM (nearest player who owns one)
    -- ========================================
    ld.find_best_im = function()
        -- Gather all IMs where getOwner returns a valid player
        local candidates = {}
        for im_name, mgr in pairs(ld.managers) do
            local im = peripheral.wrap(im_name)
            if im then
                local ok, owner = pcall(im.getOwner)
                if ok and owner and owner ~= "" then
                    table.insert(candidates, {
                        im_name = im_name,
                        owner = owner,
                        barrel_name = mgr.buffer,
                    })
                end
            end
        end
        if #candidates == 0 then return nil end
        -- Use player detector to pick closest
        local best = filter_nearby(candidates)
        return best[1] and best[1].im_name or candidates[1].im_name
    end

    -- ========================================
    -- Buffer Assignment
    -- ========================================
    -- Trigger storage rescan so it excludes/includes the barrel
    local function notify_storage()
        if st.rescan then pcall(st.rescan) end
    end

    ld.assign_buffer = function(im_name, barrel_name)
        if not im_name or not barrel_name then return false end
        local barrel = peripheral.wrap(barrel_name)
        if not barrel then return false end
        ld.buffer_barrels[im_name] = barrel_name
        -- Update manager entry
        if ld.managers[im_name] then
            ld.managers[im_name].buffer = barrel_name
        end
        save_data()
        notify_storage()
        utils.add_notification(state,
            string.format("LOADOUTS: Barrel '%s' assigned to IM", barrel_name), colors.lime)
        return true
    end

    ld.clear_buffer = function(im_name)
        if not im_name then return false end
        ld.buffer_barrels[im_name] = nil
        if ld.managers[im_name] then
            ld.managers[im_name].buffer = nil
        end
        save_data()
        notify_storage()
        utils.add_notification(state,
            string.format("LOADOUTS: Buffer cleared for IM"), colors.orange)
        return true
    end

    -- List barrels on the wired network not already assigned as buffers
    -- Excludes barrels assigned to storage roles (output, depot, fuel)
    ld.list_available_barrels = function()
        -- Build set of already-assigned buffer barrel names
        local assigned = {}
        for _, bname in pairs(ld.buffer_barrels) do
            assigned[bname] = true
        end

        -- Build set of peripherals assigned to storage roles
        local storage_assigned = {}
        local st = state.storage
        if st and st.names then
            for name, role in pairs(st.names) do
                storage_assigned[name] = true
            end
        end

        local seen = {}
        local barrels = {}
        for _, name in ipairs(peripheral.getNames()) do
            if not assigned[name] and not storage_assigned[name] and not seen[name] then
                seen[name] = true
                local ok, ptype = pcall(peripheral.getType, name)
                if ok and ptype and (ptype == "minecraft:barrel" or ptype:find("barrel")) then
                    table.insert(barrels, name)
                end
            end
        end
        table.sort(barrels)
        return barrels
    end

    -- ========================================
    -- Safe IM Call (retry up to N times)
    -- ========================================
    local function safe_im_call(im, method_name, retries)
        retries = retries or 3
        local method = im[method_name]
        if not method then return false, method_name .. " not available" end
        for attempt = 1, retries do
            local ok, result = pcall(method)
            if ok then return true, result end
            if attempt < retries then sleep(0.2) end
        end
        -- Return last error
        local ok, result = pcall(method)
        return ok, result
    end

    -- ========================================
    -- Snapshot
    -- ========================================
    ld.snapshot = function(im_name)
        local im = peripheral.wrap(im_name)
        if not im then return nil, "IM not found" end

        -- All calls get retries - IM can be flaky
        local ok_i, items = safe_im_call(im, "getItems", 3)
        local ok_a, armor = safe_im_call(im, "getArmor", 3)
        local ok_h, hand = safe_im_call(im, "getItemInHand", 2)
        local ok_o, offhand = safe_im_call(im, "getItemInOffHand", 2)

        if not ok_a then
            utils.add_notification(state,
                "LOADOUT: getArmor failed: " .. tostring(armor):sub(1, 40),
                colors.orange)
            armor = nil
        end
        if not ok_i then
            utils.add_notification(state,
                "LOADOUT: getItems failed: " .. tostring(items):sub(1, 40),
                colors.red)
            return nil, "Failed to read inventory: " .. tostring(items):sub(1, 60)
        end

        -- Filter out empty slots
        local armor_list = {}
        if armor then
            for slot, item in pairs(armor) do
                if item and item.name then
                    table.insert(armor_list, {
                        slot = slot,
                        name = item.name,
                        count = item.count or 1,
                        nbt = item.nbt,
                        displayName = item.displayName or item.name,
                    })
                end
            end
        elseif im.isWearing then
            -- Fallback: probe armor slots individually (100=boots..103=helmet)
            local slot_names = {[100] = "feet", [101] = "legs", [102] = "chest", [103] = "head"}
            for slot = 100, 103 do
                local w_ok, wearing = pcall(im.isWearing, slot)
                if w_ok and wearing then
                    -- We know the slot is occupied but can't get item details
                    -- Try removeItemFromPlayer to a temp direction and immediately give back
                    -- For snapshot, just mark as occupied with slot number
                    table.insert(armor_list, {
                        slot = slot,
                        name = "unknown:" .. slot_names[slot],
                        count = 1,
                        nbt = nil,
                        displayName = "Armor (" .. slot_names[slot] .. ")",
                    })
                end
            end
            if #armor_list > 0 then
                utils.add_notification(state,
                    string.format("LOADOUT: Detected %d armor via isWearing (no details)", #armor_list),
                    colors.yellow)
            end
        end

        local inv_list = {}
        if items then
            for slot, item in pairs(items) do
                if item and item.name then
                    table.insert(inv_list, {
                        slot = slot,
                        name = item.name,
                        count = item.count or 1,
                        nbt = item.nbt,
                        displayName = item.displayName or item.name,
                    })
                end
            end
        end

        local hand_item = nil
        if ok_h and hand and hand.name then
            hand_item = {
                name = hand.name,
                count = hand.count or 1,
                nbt = hand.nbt,
                displayName = hand.displayName or hand.name,
            }
        end

        local offhand_item = nil
        if ok_o and offhand and offhand.name then
            offhand_item = {
                name = offhand.name,
                count = offhand.count or 1,
                nbt = offhand.nbt,
                displayName = offhand.displayName or offhand.name,
            }
        end

        return {
            armor = armor_list,
            inventory = inv_list,
            hand = hand_item,
            offhand = offhand_item,
        }
    end

    -- ========================================
    -- Save / Delete / Rename
    -- ========================================
    ld.save_loadout = function(name, data)
        if not name or name == "" then return false end
        ld.saved[name] = {
            name = name,
            armor = data.armor or {},
            inventory = data.inventory or {},
            hand = data.hand,
            offhand = data.offhand,
            created = os.clock(),
        }
        save_data()
        utils.add_notification(state,
            string.format("LOADOUTS: Saved '%s'", name), colors.lime)
        return true
    end

    ld.delete_loadout = function(name)
        ld.saved[name] = nil
        save_data()
        utils.add_notification(state,
            string.format("LOADOUTS: Deleted '%s'", name), colors.orange)
    end

    ld.rename_loadout = function(old_name, new_name)
        if not old_name or not new_name or new_name == "" then return false end
        if not ld.saved[old_name] then return false end
        if ld.saved[new_name] then return false end
        local data = ld.saved[old_name]
        data.name = new_name
        ld.saved[new_name] = data
        ld.saved[old_name] = nil
        save_data()
        utils.add_notification(state,
            string.format("LOADOUTS: Renamed '%s' -> '%s'", old_name, new_name), colors.cyan)
        return true
    end

    -- ========================================
    -- Item Classification (for Quick Depot)
    -- ========================================
    local function is_armor(item_name)
        if not item_name then return false end
        local n = item_name:lower()
        return n:find("helmet") or n:find("cap") or n:find("_head")
            or n:find("chestplate") or n:find("tunic") or n:find("_chest")
            or n:find("leggings") or n:find("pants") or n:find("_legs")
            or n:find("boots") or n:find("_feet")
    end

    local function is_tool(item_name)
        if not item_name then return false end
        local n = item_name:lower()
        return n:find("sword") or n:find("pickaxe") or n:find("_axe")
            or n:find("shovel") or n:find("hoe")
            or n:find("bow") or n:find("crossbow") or n:find("trident")
            or n:find("shield") or n:find("fishing_rod") or n:find("shears")
            or n:find("flint_and_steel") or n:find("spyglass")
            or n:find("brush") or n:find("mace")
    end

    local function is_food(item)
        if not item then return false end
        -- Accept string (item name) or table (item with tags)
        local name, tags
        if type(item) == "table" then
            name = item.name
            tags = item.tags
        else
            name = item
        end
        -- Check item tags first (works with modded foods automatically)
        if tags then
            if tags["minecraft:foods"] or tags["c:foods"] then return true end
        end
        -- Fallback: name-based
        if not name then return false end
        local n = name:lower()
        return n:find("apple") or n:find("bread") or n:find("cooked_")
            or n:find("steak") or n:find("porkchop") or n:find("mutton")
            or n:find("stew") or n:find("soup")
            or n:find("baked_potato") or n:find("melon_slice")
            or n:find("cookie") or n:find("pumpkin_pie") or n:find("cake")
            or n:find("golden_apple") or n:find("golden_carrot")
            or n:find("dried_kelp") and not n:find("block")
            or n:find("berries") or n:find("honey_bottle")
            or n:find("chorus_fruit") or n:find("salmon") or n:find("cod")
            or n:find("carrot") or n:find("potato")
    end

    local function should_keep_quick(item)
        if not item then return false end
        local name = type(item) == "table" and item.name or item
        if not name then return false end
        local n = name:lower()
        if n:find("backpack") or n:find("hammer") or n:find("torch") then return true end
        return is_armor(name) or is_tool(name) or is_food(item)
    end

    -- ========================================
    -- Quick Deposit (keep armour, tools, food)
    -- ========================================
    ld.quick_deposit = function(im_name)
        local im = peripheral.wrap(im_name)
        if not im then return false, "IM not found" end

        local barrel, barrel_name = get_buffer_barrel(im_name)
        if not barrel then return false, "No buffer barrel assigned" end

        local dir = cfg.buffer_direction

        local ok_owner, owner = pcall(im.getOwner)
        if not ok_owner or not owner or owner == "" then
            utils.set_status(state, "Player not detected at IM - stand on top", colors.red, 5)
            return false, "Player not at IM"
        end

        utils.set_status(state, "Quick deposit...", colors.cyan, 5)

        local removed = 0
        local kept = 0

        -- Inventory items (skip armour slots entirely)
        local ok_i, items = safe_im_call(im, "getItems", 3)
        if ok_i and items then
            for slot, item in pairs(items) do
                if item and item.name then
                    if should_keep_quick(item) then
                        kept = kept + 1
                    else
                        local ok = pcall(im.removeItemFromPlayer, dir, item)
                        if ok then removed = removed + 1 end
                        sleep(cfg.equip_delay)
                    end
                end
            end
        end

        -- Hand item
        local ok_h, hand = safe_im_call(im, "getItemInHand", 2)
        if ok_h and hand and hand.name then
            if not should_keep_quick(hand) then
                local ok = pcall(im.removeItemFromPlayer, dir, hand)
                if ok then removed = removed + 1 end
                sleep(cfg.equip_delay)
            else
                kept = kept + 1
            end
        end

        -- Offhand item
        local ok_o, offhand = safe_im_call(im, "getItemInOffHand", 2)
        if ok_o and offhand and offhand.name then
            if not should_keep_quick(offhand) then
                local ok = pcall(im.removeItemFromPlayer, dir, offhand)
                if ok then removed = removed + 1 end
                sleep(cfg.equip_delay)
            else
                kept = kept + 1
            end
        end

        -- Drain barrel contents back into storage
        drain_barrel(barrel, barrel_name)

        utils.set_status(state,
            string.format("Deposited %d items (kept %d)", removed, kept), colors.lime, 3)
        utils.add_notification(state,
            string.format("DEPOT: Quick deposit %d items (kept %d)", removed, kept), colors.lime)
        return true, removed
    end

    -- ========================================
    -- Depot Readiness Check
    -- ========================================
    ld.has_depot_ready = function()
        for _, mgr in pairs(ld.managers) do
            if mgr.buffer then return true end
        end
        return false
    end

    -- ========================================
    -- Withdraw to Player Inventory
    -- ========================================
    ld.give_to_player = function(item_name, item_nbt, amount, display_name)
        -- Find an IM with a player standing on it, filtered to nearest
        local active = filter_nearby(find_ims_with_players())
        if #active == 0 then
            return 0, amount  -- no player detected, all remaining
        end

        local entry = active[1]
        local im = peripheral.wrap(entry.im_name)
        if not im then return 0, amount end

        local barrel, barrel_name = get_buffer_barrel(entry.im_name)
        if not barrel then return 0, amount end

        local dir = cfg.buffer_direction
        local given = 0
        local remaining = amount

        -- Push items from storage -> barrel -> player (one stack at a time)
        while remaining > 0 do
            local batch = math.min(remaining, 64)
            -- Use storage cache-aware pull (updates slot + aggregate caches)
            local pulled = st.pull_from_storage
                and st.pull_from_storage(barrel_name, item_name, item_nbt, batch)
                or 0
            if pulled == 0 then break end  -- no more of this item in storage

            sleep(cfg.equip_delay)
            -- Barrel -> player
            local filter = {name = item_name, count = pulled}
            local add_ok = pcall(im.addItemToPlayer, dir, filter)
            if add_ok then
                given = given + pulled
                remaining = remaining - pulled
            else
                -- Player inventory full - drain barrel back to storage
                drain_barrel(barrel, barrel_name)
                return given, remaining
            end
            sleep(cfg.equip_delay)
        end

        -- Drain any leftovers
        drain_barrel(barrel, barrel_name)
        return given, remaining
    end

    -- ========================================
    -- Strip
    -- ========================================
    ld.strip = function(im_name)
        local im = peripheral.wrap(im_name)
        if not im then return false, "IM not found" end

        local barrel, barrel_name = get_buffer_barrel(im_name)
        if not barrel then return false, "No buffer barrel assigned" end

        local dir = cfg.buffer_direction

        -- Verify player is near the IM
        local ok_owner, owner = pcall(im.getOwner)
        if not ok_owner or not owner or owner == "" then
            utils.set_status(state, "Player not detected at IM - stand on top", colors.red, 5)
            return false, "Player not at IM"
        end

        utils.set_status(state, "Stripping gear...", colors.cyan, 5)

        local removed = 0

        -- Strip armor (player -> barrel)
        local ok_a, armor = safe_im_call(im, "getArmor", 3)
        if ok_a and armor then
            for slot, item in pairs(armor) do
                if item and item.name then
                    local ok = pcall(im.removeItemFromPlayer, dir, item)
                    if ok then removed = removed + 1 end
                    sleep(cfg.equip_delay)
                end
            end
        elseif im.isWearing then
            -- Fallback: try removing from each armor slot directly
            for slot = 100, 103 do
                local w_ok, wearing = pcall(im.isWearing, slot)
                if w_ok and wearing then
                    local ok = pcall(im.removeItemFromPlayer, dir, {slot = slot, count = 1})
                    if ok then removed = removed + 1 end
                    sleep(cfg.equip_delay)
                end
            end
        end

        -- Strip inventory (player -> barrel)
        local ok_i, items = safe_im_call(im, "getItems", 3)
        if ok_i and items then
            for slot, item in pairs(items) do
                if item and item.name then
                    local ok = pcall(im.removeItemFromPlayer, dir, item)
                    if ok then removed = removed + 1 end
                    sleep(cfg.equip_delay)
                end
            end
        end

        -- Strip hand items (player -> barrel)
        local ok_h, hand = safe_im_call(im, "getItemInHand", 2)
        if ok_h and hand and hand.name then
            local ok = pcall(im.removeItemFromPlayer, dir, hand)
            if ok then removed = removed + 1 end
            sleep(cfg.equip_delay)
        end

        local ok_o, offhand = safe_im_call(im, "getItemInOffHand", 2)
        if ok_o and offhand and offhand.name then
            local ok = pcall(im.removeItemFromPlayer, dir, offhand)
            if ok then removed = removed + 1 end
            sleep(cfg.equip_delay)
        end

        -- Drain barrel contents back into storage
        local drained = drain_barrel(barrel, barrel_name)

        utils.set_status(state,
            string.format("Stripped %d items", removed), colors.lime, 3)
        utils.add_notification(state,
            string.format("LOADOUTS: Stripped %d items", removed), colors.orange)
        return true, removed
    end

    -- ========================================
    -- Equip
    -- ========================================
    ld.equip = function(im_name, loadout_name)
        local im = peripheral.wrap(im_name)
        if not im then return false, "IM not found" end

        local loadout = ld.saved[loadout_name]
        if not loadout then return false, "Loadout not found" end

        local barrel, barrel_name = get_buffer_barrel(im_name)
        if not barrel then return false, "No buffer barrel assigned" end

        local dir = cfg.buffer_direction

        -- Verify player is near the IM (getOwner returns nil if not bound / not nearby)
        local ok_owner, owner = pcall(im.getOwner)
        if not ok_owner or not owner or owner == "" then
            utils.set_status(state, "Player not detected at IM - stand on top", colors.red, 5)
            return false, "Player not at IM"
        end

        -- Strip first
        utils.set_status(state, "Stripping before equip...", colors.cyan, 5)
        ld.strip(im_name)
        sleep(0.5)

        local item_count = 0
        for _ in ipairs(loadout.armor or {}) do item_count = item_count + 1 end
        for _ in ipairs(loadout.inventory or {}) do item_count = item_count + 1 end
        if loadout.hand then item_count = item_count + 1 end
        if loadout.offhand then item_count = item_count + 1 end

        utils.set_status(state,
            string.format("Equipping '%s' (%d items, %d chests)...",
                loadout_name, item_count, #st.peripherals), colors.cyan, 10)

        local equipped = 0
        local failed = 0

        -- Map armor item name to player equipment slot (MC numbering)
        local function get_armor_slot(item_name)
            if not item_name then return nil end
            local n = item_name:lower()
            if n:find("helmet") or n:find("cap") or n:find("_head") then return 103 end
            if n:find("chestplate") or n:find("tunic") or n:find("_chest") then return 102 end
            if n:find("leggings") or n:find("pants") or n:find("_legs") then return 101 end
            if n:find("boots") or n:find("_feet") then return 100 end
            return nil
        end

        -- Helper: push item from storage to barrel, then give to player
        local function give_item(item_info, is_armor)
            -- Try cache-aware pull first, fall back to manual scan
            local pushed = 0
            if st.pull_from_storage then
                pushed = st.pull_from_storage(barrel_name, item_info.name, item_info.nbt, item_info.count or 1)
                -- Fallback: try name-only match if exact NBT failed
                if pushed == 0 and item_info.nbt then
                    pushed = st.pull_from_storage(barrel_name, item_info.name, nil, item_info.count or 1, true)
                end
            end

            -- Legacy fallback if pull_from_storage unavailable or returned 0
            if pushed == 0 then
                local store, slot, item = find_item_in_storage(item_info.name, item_info.nbt)
                if not store then
                    utils.add_notification(state,
                        "LOADOUT: Not in storage: " .. (item_info.displayName or item_info.name),
                        colors.red)
                    failed = failed + 1
                    return false
                end
                local push_ok
                push_ok, pushed = pcall(store.periph.pushItems, barrel_name, slot, item_info.count or 1)
                if push_ok and pushed and pushed > 0 and st.notify_withdrawn then
                    st.notify_withdrawn(item_info.name, item_info.nbt or item.nbt, pushed, store.name)
                end
            end

            if not pushed or pushed == 0 then
                utils.add_notification(state,
                    "LOADOUT: Push to barrel failed: " .. (item_info.displayName or item_info.name),
                    colors.red)
                failed = failed + 1
                return false
            end
            sleep(cfg.equip_delay)

            -- Build item filter for addItemToPlayer
            local filter = {
                name = item_info.name,
                count = pushed,
            }

            -- Target armor slot if this is an armor piece
            if is_armor then
                local armor_slot = get_armor_slot(item_info.name)
                if armor_slot then
                    filter.toSlot = armor_slot
                end
            end

            -- Give from barrel -> player (IM pulls from direction)
            local add_ok, add_err = pcall(im.addItemToPlayer, dir, filter)
            if add_ok then
                equipped = equipped + 1
            else
                -- Item is stuck in barrel - will be drained at end
                utils.add_notification(state,
                    "LOADOUT: Give to player failed: " .. (item_info.displayName or item_info.name),
                    colors.red)
                failed = failed + 1
            end
            sleep(cfg.equip_delay)
            return add_ok
        end

        -- Equip armor (to armor slots)
        for _, armor_item in ipairs(loadout.armor or {}) do
            give_item(armor_item, true)
        end

        -- Equip inventory items
        for _, inv_item in ipairs(loadout.inventory or {}) do
            give_item(inv_item)
        end

        -- Equip hand
        if loadout.hand then
            give_item(loadout.hand)
        end

        -- Equip offhand
        if loadout.offhand then
            give_item(loadout.offhand)
        end

        -- Drain any leftovers from barrel back to storage
        drain_barrel(barrel, barrel_name)

        if failed == 0 then
            utils.set_status(state,
                string.format("Equipped '%s' (%d items)", loadout_name, equipped), colors.lime, 3)
        else
            utils.set_status(state,
                string.format("Equipped %d, failed %d", equipped, failed), colors.orange, 5)
        end
        utils.add_notification(state,
            string.format("LOADOUTS: Equipped '%s' (%d ok, %d fail)", loadout_name, equipped, failed),
            failed == 0 and colors.lime or colors.orange)
        return failed == 0, equipped
    end

    -- ========================================
    -- Get Inventory (live view)
    -- ========================================
    ld.get_inventory = function(im_name)
        local im = peripheral.wrap(im_name)
        if not im then return nil end
        local ok, items = safe_im_call(im, "getItems", 3)
        if not ok then return nil end
        return items
    end

    -- ========================================
    -- List Managers
    -- ========================================
    ld.list_managers = function()
        local list = {}
        for name, mgr in pairs(ld.managers) do
            table.insert(list, {
                name = mgr.name,
                owner = mgr.owner,
                online = mgr.online,
                buffer = mgr.buffer,
            })
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list
    end

    -- ========================================
    -- Main Loop
    -- ========================================
    load_data()
    scan_managers()

    local mgr_count = 0
    for _ in pairs(ld.managers) do mgr_count = mgr_count + 1 end
    if mgr_count > 0 then
        utils.add_notification(state,
            string.format("LOADOUTS: %d Inventory Manager(s) found", mgr_count), colors.lime)
    else
        utils.set_status(state, "LOADOUTS: No Inventory Managers found", colors.orange, 5)
    end

    local saved_count = 0
    for _ in pairs(ld.saved) do saved_count = saved_count + 1 end
    if saved_count > 0 then
        utils.add_notification(state,
            string.format("LOADOUTS: %d saved loadout(s) loaded", saved_count), colors.cyan)
    end

    ld.ready = true

    local next_scan = os.clock() + cfg.scan_interval

    while state.running do
        local ev = {os.pullEvent()}
        local now = os.clock()

        -- Rescan IMs periodically
        if now >= next_scan then
            scan_managers()
            next_scan = now + cfg.scan_interval
        end

        -- Desktop quick-equip event
        if ev[1] == "loadout:equip" then
            local loadout_name = ev[2]
            if not ld.saved[loadout_name] then
                utils.set_status(state, "Loadout not found: " .. tostring(loadout_name), colors.red, 3)
            else
                local active = filter_nearby(find_ims_with_players())
                if #active == 0 then
                    utils.set_status(state, "Stand on an IM to equip", colors.red, 3)
                elseif #active > 1 then
                    utils.set_status(state, "Multiple players detected - one at a time", colors.orange, 3)
                else
                    ld.equip(active[1].im_name, loadout_name)
                end
            end
        end

        -- Desktop depot events
        if ev[1] == "depot:quick" or ev[1] == "depot:full" then
            local active = filter_nearby(find_ims_with_players())
            if #active == 0 then
                utils.set_status(state, "Stand on an IM to deposit", colors.red, 3)
            else
                for _, entry in ipairs(active) do
                    if ev[1] == "depot:quick" then
                        ld.quick_deposit(entry.im_name)
                    else
                        ld.strip(entry.im_name)
                    end
                end
            end
        end

        -- Peripheral hotplug
        if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            sleep(0.3)
            scan_managers()
        end
    end
end

return svc
