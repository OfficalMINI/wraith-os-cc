-- =============================================
-- WRAITH OS - CRAFTING SERVICE
-- =============================================
-- Discovers crafty turtles on the wired modem network,
-- manages crafting rules/tasks, and coordinates craft execution.

local svc = {}

function svc.main(state, config, utils)
    local cr = state.crafting
    local cfg = config.crafting
    local proto = cfg.protocols

    -- ========================================
    -- Config Persistence
    -- ========================================
    local config_file = (_G.WRAITH_ROOT or ".") .. "/" .. cfg.save_file:gsub("^wraith/", "")
    -- Handle if save_file already has full path
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

    local function save_craft_data()
        local saved = load_saved_config() or {}
        saved.craft_rules = cr.craft_rules
        saved.craft_tasks = cr.craft_tasks
        saved.crafting_enabled = cr.crafting_enabled
        saved.craft_history = cr.craft_history
        save_config(saved)
    end

    -- ========================================
    -- Turtle Discovery
    -- ========================================
    local turtle_by_id = {}  -- {[computer_id] = turtle_entry}

    local function discover_turtles()
        -- Find turtles on wired network by peripheral type
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            local ptype = peripheral.getType(name)
            if ptype and ptype:find("turtle") then
                -- Check if we already track this peripheral by name
                local found = false
                for _, t in ipairs(cr.turtles) do
                    if t.name == name then
                        -- Update peripheral ref in case it was lost
                        if not t.periph then
                            t.periph = peripheral.wrap(name)
                        end
                        found = true
                        break
                    end
                end
                if not found then
                    -- Check if any existing entry is missing a peripheral (registered via ping only)
                    local merged = false
                    for _, t in ipairs(cr.turtles) do
                        if not t.periph then
                            t.name = name
                            t.periph = peripheral.wrap(name)
                            merged = true
                            break
                        end
                    end
                    if not merged then
                        local p = peripheral.wrap(name)
                        if p then
                            table.insert(cr.turtles, {
                                id = nil,   -- filled in when turtle pings us
                                name = name,
                                label = name,
                                periph = p,
                                state = "idle",
                                last_seen = os.clock(),
                            })
                        end
                    end
                end
            end
        end
    end

    local function find_idle_turtle()
        for _, t in ipairs(cr.turtles) do
            if t.state == "idle" and t.id and t.periph then
                return t
            end
        end
        return nil
    end

    local function get_turtle_by_id(computer_id)
        for _, t in ipairs(cr.turtles) do
            if t.id == computer_id then return t end
        end
        return nil
    end

    -- ========================================
    -- Grid/Recipe Helpers
    -- ========================================

    -- Grid slot (1-9) to turtle inventory slot
    local GRID_TO_TURTLE = {1, 2, 3, 5, 6, 7, 9, 10, 11}
    -- All 16 turtle slots
    local ALL_TURTLE_SLOTS = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}

    -- Count how many of each ingredient a recipe needs per craft
    local function count_ingredients(rule)
        local counts = {}  -- {[item_name] = count_per_craft}
        for slot = 1, 9 do
            local item_name = rule.grid[slot]
            if item_name then
                counts[item_name] = (counts[item_name] or 0) + 1
            end
        end
        return counts
    end

    -- Find ingredient entry by name
    local function find_ingredient(rule, item_name)
        for _, ing in ipairs(rule.ingredients) do
            if ing.name == item_name then return ing end
        end
        return nil
    end

    -- Get current stock of an item from storage (sum across all NBT variants)
    local function get_stock(item_name)
        local st = state.storage
        if not st or not st.items then return 0 end
        local total = 0
        for _, item in ipairs(st.items) do
            if item.name == item_name then total = total + item.count end
        end
        return total
    end

    -- Check if a rule can be crafted (all ingredients above thresholds)
    local function can_craft(rule, crafts)
        crafts = crafts or 1
        local ing_counts = count_ingredients(rule)

        for item_name, per_craft in pairs(ing_counts) do
            local needed = per_craft * crafts
            local stock = get_stock(item_name)
            local ing = find_ingredient(rule, item_name)
            local threshold = ing and ing.threshold or 0

            -- Must have enough stock above the ingredient threshold
            if stock < needed + threshold then
                return false
            end
        end
        return true
    end

    -- Max crafts possible respecting ingredient thresholds
    local function max_crafts(rule)
        local ing_counts = count_ingredients(rule)
        local max_c = cfg.max_batch  -- cap at max_batch

        for item_name, per_craft in pairs(ing_counts) do
            local stock = get_stock(item_name)
            local ing = find_ingredient(rule, item_name)
            local threshold = ing and ing.threshold or 0
            local available = math.max(0, stock - threshold)
            local possible = math.floor(available / per_craft)
            max_c = math.min(max_c, possible)
        end

        return math.max(0, max_c)
    end

    -- ========================================
    -- Craft Execution
    -- ========================================

    local craft_queue = {}  -- {{rule_idx, count, task_idx_or_nil}}
    local crafting_turtle = nil  -- currently crafting turtle

    -- Pull all items from turtle back to storage (uses pullItems from storage side)
    local function retrieve_turtle_items(turtle)
        local st = state.storage
        if not st or not st.peripherals or #st.peripherals == 0 then
            utils.add_notification(state, "CRAFT RETRIEVE: no storage peripherals", colors.red)
            return 0, 0
        end
        if not turtle.periph then
            utils.add_notification(state,
                "CRAFT RETRIEVE: turtle has no periph ref", colors.red)
            return 0, 0
        end

        local ok, items = pcall(turtle.periph.list)
        if not ok then
            utils.add_notification(state,
                "CRAFT RETRIEVE: list() failed: " .. tostring(items):sub(1, 30), colors.red)
            return 0, 0
        end
        if not items or not next(items) then return 0, 0 end

        local retrieved = 0
        local stuck = 0
        local first_err = nil
        for s, item in pairs(items) do
            local remaining = item.count
            -- Loop until slot is fully empty (handles partial pulls from near-full chests)
            while remaining > 0 do
                local pulled_any = false
                -- Primary: pull from storage side (more reliable for wired peripherals)
                for _, store in ipairs(st.peripherals) do
                    local p_ok, pulled = pcall(store.periph.pullItems, turtle.name, s)
                    if p_ok and pulled and pulled > 0 then
                        retrieved = retrieved + pulled
                        remaining = remaining - pulled
                        st.notify_deposited(item.name, item.nbt, pulled, store.name)
                        pulled_any = true
                        break
                    elseif not p_ok and not first_err then
                        first_err = tostring(pulled):sub(1, 40)
                    end
                end
                -- Fallback: push from turtle side
                if not pulled_any then
                    for _, store in ipairs(st.peripherals) do
                        local p_ok, pushed = pcall(turtle.periph.pushItems, store.name, s)
                        if p_ok and pushed and pushed > 0 then
                            retrieved = retrieved + pushed
                            remaining = remaining - pushed
                            st.notify_deposited(item.name, item.nbt, pushed, store.name)
                            pulled_any = true
                            break
                        elseif not p_ok and not first_err then
                            first_err = tostring(pushed):sub(1, 40)
                        end
                    end
                end
                if not pulled_any then
                    stuck = stuck + remaining
                    break
                end
            end
        end
        if first_err then
            utils.add_notification(state,
                "CRAFT RETRIEVE ERR: " .. first_err, colors.red)
        end
        return retrieved, stuck
    end

    local function execute_craft(rule, count, task_idx)
        local turtle = find_idle_turtle()
        if not turtle then
            utils.set_status(state, "No idle turtles available", colors.orange, 3)
            return 0
        end

        -- Must have a wired peripheral to push/pull items
        if not turtle.periph then
            utils.add_notification(state,
                "CRAFT: " .. (turtle.label or "?") .. " has no wired peripheral",
                colors.orange)
            return 0
        end

        local st = state.storage
        if not st or not st.peripherals then
            cr.craft_status = "storage not ready"
            return 0
        end

        local crafts = math.min(count, cfg.max_batch)
        -- Verify we can still craft this many
        if not can_craft(rule, crafts) then
            crafts = max_crafts(rule)
            if crafts <= 0 then
                cr.craft_status = "insufficient ingredients"
                return 0
            end
        end

        local out_name = rule.output and (rule.output.display or rule.output.name) or "?"
        utils.add_notification(state,
            string.format("CRAFT: Starting %s x%d on %s",
                out_name:sub(1, 16), crafts, turtle.label or "?"),
            colors.cyan)

        turtle.state = "crafting"
        turtle.craft_started = os.clock()
        crafting_turtle = turtle

        -- Step 1: Clear turtle inventory — pull everything from turtle to storage
        retrieve_turtle_items(turtle)

        -- Step 2: Push ingredients from storage to specific turtle slots
        -- Pre-snapshot ingredient stocks and track cumulative pushes to enforce thresholds
        local ing_counts = count_ingredients(rule)
        local ing_stock_snapshot = {}   -- {item_name -> stock at start}
        for item_name, _ in pairs(ing_counts) do
            ing_stock_snapshot[item_name] = get_stock(item_name)
        end
        local pushed_by_item = {}       -- {item_name -> total pushed so far}

        local push_failed = false
        for grid_slot = 1, 9 do
            local item_name = rule.grid[grid_slot]
            if item_name then
                local turtle_slot = GRID_TO_TURTLE[grid_slot]
                local needed = crafts  -- 1 item per slot per craft

                -- Enforce ingredient threshold during push
                local ing = find_ingredient(rule, item_name)
                local threshold = ing and ing.threshold or 0
                local stock = ing_stock_snapshot[item_name] or 0
                local already_pushed = pushed_by_item[item_name] or 0
                local max_pushable = math.max(0, stock - threshold - already_pushed)
                if needed > max_pushable then
                    push_failed = true
                    utils.add_notification(state,
                        string.format("CRAFT: %s threshold %d, stock %d, already used %d",
                            item_name:gsub("minecraft:", ""), threshold, stock, already_pushed),
                        colors.red)
                    break
                end

                -- Use storage API to push to a specific turtle slot
                local pushed_total = 0
                if st.pull_to_slot then
                    pushed_total = st.pull_to_slot(turtle.name, turtle_slot, item_name, nil, needed, true)
                end
                pushed_by_item[item_name] = already_pushed + pushed_total

                if pushed_total < needed then
                    push_failed = true
                    utils.add_notification(state,
                        string.format("CRAFT: Need %s slot %d (%d/%d)",
                            item_name:gsub("minecraft:", ""), turtle_slot, pushed_total, needed),
                        colors.red)
                    break
                end
            end
        end

        if push_failed then
            utils.add_notification(state,
                "CRAFT: Push failed, returning items to storage", colors.orange)
            cr.craft_status = "push failed"
            -- Pull ingredients back from turtle to storage
            retrieve_turtle_items(turtle)
            turtle.state = "idle"
            crafting_turtle = nil
            return 0
        end

        -- Record what was pushed so finish_craft can update cache correctly
        turtle.pending_pushed_items = pushed_by_item

        -- Per-item crafting consumption analytics
        local an = state.analytics
        if an and an.top_craft_used then
            for item_name, count in pairs(pushed_by_item) do
                local display = utils.clean_name(item_name)
                an.top_craft_used[display] = (an.top_craft_used[display] or 0) + count
            end
        end

        -- Step 3: Send craft command via rednet (include storage names for turtle to push results back)
        if turtle.id then
            local storage_names = {}
            for _, store in ipairs(st.peripherals) do
                table.insert(storage_names, store.name)
            end
            rednet.send(turtle.id, {action = "craft", count = crafts, storage_names = storage_names}, proto.command)
            utils.add_notification(state,
                string.format("CRAFT: Sent craft x%d to %s (#%d)",
                    crafts, turtle.label or "?", turtle.id),
                colors.cyan)

            -- Step 4: Wait for result (handled asynchronously via event loop)
            -- Store pending craft info on turtle
            turtle.pending_crafts = crafts
            turtle.pending_task_idx = task_idx
            turtle.pending_rule = rule
            turtle.pending_yield = rule.yield or 1
            turtle.craft_started = os.clock()
            -- Result will be processed in the event loop
            return crafts
        else
            -- No rednet ID — can't command this turtle
            turtle.state = "idle"
            crafting_turtle = nil
            utils.add_notification(state, "CRAFT: Turtle has no rednet ID", colors.orange)
            return 0
        end
    end

    local function finish_craft(turtle, success, crafted, items_returned, items_stuck)
        if not turtle then return end

        local st = state.storage
        local rule = turtle.pending_rule
        local task_idx = turtle.pending_task_idx
        local yield = turtle.pending_yield or 1
        items_returned = items_returned or 0
        items_stuck = items_stuck or 0

        if success and st and st.peripherals then
            local total_produced = crafted * yield

            -- Turtle already pushed items back to storage — update cache with actual output
            if items_returned > 0 then
                if rule and rule.output and rule.output.name and st.notify_deposited then
                    st.notify_deposited(rule.output.name, rule.output.nbt or nil, total_produced, nil)
                end
                utils.add_notification(state,
                    string.format("CRAFT: Turtle returned %d items to storage", items_returned),
                    colors.lime)
            end

            -- Server-side fallback: retrieve any items still on the turtle
            if items_stuck > 0 or items_returned == 0 then
                local retrieved, stuck = retrieve_turtle_items(turtle)
                if retrieved > 0 then
                    utils.add_notification(state,
                        string.format("CRAFT: Server retrieved %d more items from %s",
                            retrieved, turtle.label or "?"),
                        colors.lime)
                end
                if stuck > 0 then
                    utils.add_notification(state,
                        string.format("CRAFT: %d items stuck on turtle %s!",
                            stuck, turtle.label or "?"),
                        colors.orange)
                end
            end

            -- Update task progress
            if task_idx and cr.craft_tasks[task_idx] then
                local task = cr.craft_tasks[task_idx]
                task.crafted = task.crafted + total_produced
                if task.crafted >= task.target then
                    task.active = false
                end
                save_craft_data()
            end

            cr.items_crafted = cr.items_crafted + total_produced

            -- Track persistent craft history (per-item counts)
            if rule and rule.output then
                local key = rule.output.display or rule.output.name or "?"
                cr.craft_history[key] = (cr.craft_history[key] or 0) + total_produced
                save_craft_data()
            end

            if rule and rule.output then
                local msg = string.format("Crafted %sx %s",
                    utils.format_number(total_produced),
                    utils.truncate(rule.output.display or "items", 18))
                utils.set_status(state, msg, colors.lime, 3)
                utils.add_notification(state, "CRAFT: " .. msg, colors.lime)
                cr.craft_status = msg
            end
        else
            cr.craft_status = "craft failed"
            -- Turtle may have pushed ingredients back already — restore cache
            if items_returned > 0 then
                if turtle.pending_pushed_items and st.notify_deposited then
                    for item_name, count in pairs(turtle.pending_pushed_items) do
                        st.notify_deposited(item_name, nil, count, nil)
                    end
                end
                utils.add_notification(state,
                    string.format("CRAFT: Turtle returned %d items from failed craft", items_returned),
                    colors.yellow)
            end
            -- Server-side fallback for remaining items
            local retrieved, stuck = retrieve_turtle_items(turtle)
            if retrieved > 0 then
                utils.add_notification(state,
                    string.format("CRAFT: Recovered %d items from failed craft", retrieved),
                    colors.yellow)
            end
            if stuck > 0 then
                utils.add_notification(state,
                    string.format("CRAFT: %d items stuck on turtle after failed craft!", stuck),
                    colors.red)
            end
            utils.add_notification(state, "CRAFT: Turtle craft failed", colors.red)
        end

        -- Reset turtle state
        turtle.state = "idle"
        turtle.pending_crafts = nil
        turtle.pending_task_idx = nil
        turtle.pending_rule = nil
        turtle.pending_yield = nil
        turtle.pending_pushed_items = nil
        turtle.craft_started = nil
        crafting_turtle = nil
    end

    -- ========================================
    -- Auto-Craft Logic
    -- ========================================

    local function process_auto_craft()
        if not cr.crafting_enabled then
            cr.craft_status = "disabled"
            return
        end

        -- Diagnose turtle availability
        if #cr.turtles == 0 then
            cr.craft_status = "no turtles"
            return
        end

        local idle_no_id = 0
        local idle_no_periph = 0
        for _, t in ipairs(cr.turtles) do
            if t.state == "idle" then
                if not t.id then idle_no_id = idle_no_id + 1
                elseif not t.periph then idle_no_periph = idle_no_periph + 1
                end
            end
        end

        if not find_idle_turtle() then
            if idle_no_id > 0 then
                cr.craft_status = "turtle has no rednet ID"
            elseif idle_no_periph > 0 then
                cr.craft_status = "turtle has no wired periph"
            else
                cr.craft_status = "all turtles busy"
            end
            return
        end

        if #cr.craft_rules == 0 then
            cr.craft_status = "no rules"
            return
        end

        -- Check rules with output thresholds
        -- Craft 1 at a time: small pushes (1 item per slot) are reliable.
        -- The loop repeats each tick so throughput is steady.
        local any_rule_checked = false
        for idx, rule in ipairs(cr.craft_rules) do
            if rule.enabled and rule.output_threshold > 0 and rule.output and rule.output.name then
                any_rule_checked = true
                local output_stock = get_stock(rule.output.name)
                if output_stock < rule.output_threshold then
                    if can_craft(rule, 1) then
                        local out_name = rule.output.display or rule.output.name or "?"
                        cr.craft_status = string.format("crafting %s", out_name:sub(1, 20))
                        execute_craft(rule, 1, nil)
                        return  -- one craft per tick
                    else
                        cr.craft_status = "low ingredients"
                    end
                end
            end
        end

        -- Check active tasks
        for idx, task in ipairs(cr.craft_tasks) do
            if task.active and cr.craft_rules[task.rule_idx] then
                any_rule_checked = true
                local rule = cr.craft_rules[task.rule_idx]
                local remaining = task.target - task.crafted
                if remaining > 0 then
                    if can_craft(rule, 1) then
                        local out_name = rule.output and (rule.output.display or rule.output.name) or "?"
                        cr.craft_status = string.format("task: %s", out_name:sub(1, 20))
                        execute_craft(rule, 1, idx)
                        return  -- one craft per tick
                    else
                        cr.craft_status = "task: low ingredients"
                    end
                end
            end
        end

        if not any_rule_checked then
            cr.craft_status = "no active rules"
        else
            cr.craft_status = cr.craft_status or "all stocked"
        end
    end

    -- ========================================
    -- Public API
    -- ========================================

    cr.add_rule = function(output, grid, ingredients, yield, output_threshold)
        table.insert(cr.craft_rules, {
            output = output,
            output_threshold = output_threshold or 0,
            grid = grid,
            ingredients = ingredients or {},
            yield = yield or 1,
            enabled = true,
        })
        save_craft_data()
        return #cr.craft_rules
    end

    cr.remove_rule = function(idx)
        if cr.craft_rules[idx] then
            table.remove(cr.craft_rules, idx)
            -- Fix task references
            for _, task in ipairs(cr.craft_tasks) do
                if task.rule_idx == idx then
                    task.active = false  -- orphaned task
                elseif task.rule_idx > idx then
                    task.rule_idx = task.rule_idx - 1
                end
            end
            save_craft_data()
            return true
        end
        return false
    end

    cr.update_rule = function(idx, field, value)
        if cr.craft_rules[idx] then
            cr.craft_rules[idx][field] = value
            save_craft_data()
            return true
        end
        return false
    end

    cr.toggle_rule = function(idx)
        if cr.craft_rules[idx] then
            cr.craft_rules[idx].enabled = not cr.craft_rules[idx].enabled
            save_craft_data()
            return cr.craft_rules[idx].enabled
        end
        return false
    end

    cr.add_task = function(rule_idx, target)
        if cr.craft_rules[rule_idx] then
            table.insert(cr.craft_tasks, {
                rule_idx = rule_idx,
                target = target or 64,
                crafted = 0,
                active = true,
            })
            save_craft_data()
            return #cr.craft_tasks
        end
        return nil
    end

    cr.cancel_task = function(idx)
        if cr.craft_tasks[idx] then
            cr.craft_tasks[idx].active = false
            save_craft_data()
            return true
        end
        return false
    end

    cr.clear_completed_tasks = function()
        local i = 1
        while i <= #cr.craft_tasks do
            if not cr.craft_tasks[i].active then
                table.remove(cr.craft_tasks, i)
            else
                i = i + 1
            end
        end
        save_craft_data()
    end

    cr.toggle_crafting = function()
        cr.crafting_enabled = not cr.crafting_enabled
        save_craft_data()
        utils.set_status(state,
            "Auto-Craft: " .. (cr.crafting_enabled and "ON" or "OFF"),
            cr.crafting_enabled and colors.lime or colors.lightGray, 3)
        return cr.crafting_enabled
    end

    cr.get_stats = function()
        local idle, crafting, offline = 0, 0, 0
        local usable = 0  -- idle + has ID + has periph
        for _, t in ipairs(cr.turtles) do
            if t.state == "crafting" then crafting = crafting + 1
            elseif t.state == "offline" then offline = offline + 1
            else idle = idle + 1 end
            if t.state == "idle" and t.id and t.periph then usable = usable + 1 end
        end
        return {
            turtle_count = #cr.turtles,
            idle = idle,
            usable = usable,
            crafting = crafting,
            offline = offline,
            items_crafted = cr.items_crafted,
            rules_count = #cr.craft_rules,
            tasks_count = #cr.craft_tasks,
            enabled = cr.crafting_enabled,
            craft_status = cr.craft_status or "...",
        }
    end

    -- ========================================
    -- Load Saved Data
    -- ========================================

    local saved = load_saved_config()
    if saved then
        cr.craft_rules = saved.craft_rules or {}
        cr.craft_tasks = saved.craft_tasks or {}
        cr.crafting_enabled = saved.crafting_enabled or false
        cr.craft_history = saved.craft_history or {}
    end
    cr.craft_history = cr.craft_history or {}

    -- ========================================
    -- Initialize
    -- ========================================

    discover_turtles()
    cr.ready = true

    utils.add_notification(state,
        string.format("CRAFT: %d turtles, %d rules", #cr.turtles, #cr.craft_rules),
        colors.cyan)

    -- ========================================
    -- Main Event Loop
    -- ========================================

    local TICK_INTERVAL = cfg.tick_interval or 3
    local TURTLE_TIMEOUT = 30
    local CLEANUP_INTERVAL = 30  -- check idle turtles for stray items every 30s
    local next_cleanup = os.clock() + CLEANUP_INTERVAL
    local tick_timer = os.startTimer(TICK_INTERVAL)

    while state.running do
        local ev = {coroutine.yield()}

        if ev[1] == "timer" and ev[2] == tick_timer then
            local tick_ok, tick_err = pcall(function()
                local now = os.clock()

                -- Check turtle heartbeats
                for _, t in ipairs(cr.turtles) do
                    if t.state ~= "offline" and t.last_seen > 0 and (now - t.last_seen) > TURTLE_TIMEOUT then
                        t.state = "offline"
                    end
                end

                -- Check for stuck crafts (timeout after 15s, or missing timestamp)
                for _, t in ipairs(cr.turtles) do
                    if t.state == "crafting" then
                        if not t.craft_started or (now - t.craft_started) > 15 then
                            utils.add_notification(state,
                                "CRAFT: Turtle " .. (t.label or "?") .. " timed out, resetting",
                                colors.orange)
                            finish_craft(t, false, 0)
                        end
                    end
                end

                -- Clean idle turtles with stray items (every ~30s)
                if now >= next_cleanup then
                    for _, t in ipairs(cr.turtles) do
                        if t.state == "idle" and t.periph then
                            local list_ok, items = pcall(t.periph.list)
                            if list_ok and items and next(items) then
                                local retrieved, stuck = retrieve_turtle_items(t)
                                if retrieved > 0 then
                                    utils.add_notification(state,
                                        string.format("CRAFT: Cleaned %d stray items from %s",
                                            retrieved, t.label or "?"),
                                        colors.yellow)
                                end
                            end
                        end
                    end
                    next_cleanup = now + CLEANUP_INTERVAL
                end

                -- Auto-craft check
                process_auto_craft()
            end)
            if not tick_ok then
                utils.add_notification(state,
                    "CRAFT ERR: " .. tostring(tick_err):sub(1, 40),
                    colors.red)
            end

            tick_timer = os.startTimer(TICK_INTERVAL)

        elseif ev[1] == "rednet_message" then
            local net_ok, net_err = pcall(function()
            local sender = ev[2]
            local msg = ev[3]
            local protocol = ev[4]

            if protocol == proto.ping and type(msg) == "table" and msg.type == "crafty" then
                -- Crafting turtle checking in
                local turtle_entry = get_turtle_by_id(sender)

                if not turtle_entry then
                    -- Try to match existing entries: prefer one with periph but no id
                    local best_match = nil
                    for _, t in ipairs(cr.turtles) do
                        if not t.id then
                            if t.periph then
                                best_match = t  -- has wired peripheral, perfect match
                                break
                            elseif not best_match then
                                best_match = t  -- fallback: entry without periph
                            end
                        end
                    end

                    if best_match then
                        best_match.id = sender
                        best_match.label = msg.label or best_match.name
                        best_match.state = "idle"
                        best_match.last_seen = os.clock()
                        turtle_entry = best_match
                    else
                        -- No existing entry — create new and try to find wired peripheral
                        turtle_entry = {
                            id = sender,
                            name = "turtle_" .. sender,
                            label = msg.label or ("Turtle " .. sender),
                            periph = nil,
                            state = "idle",
                            last_seen = os.clock(),
                        }
                        -- Scan for an unmatched turtle peripheral on the wired network
                        for _, name in ipairs(peripheral.getNames()) do
                            local ptype = peripheral.getType(name)
                            if ptype and ptype:find("turtle") then
                                local already_used = false
                                for _, t in ipairs(cr.turtles) do
                                    if t.name == name then
                                        already_used = true
                                        break
                                    end
                                end
                                if not already_used then
                                    turtle_entry.name = name
                                    turtle_entry.periph = peripheral.wrap(name)
                                    break
                                end
                            end
                        end
                        table.insert(cr.turtles, turtle_entry)
                        utils.add_notification(state,
                            string.format("CRAFT: Turtle registered - %s %s",
                                turtle_entry.label,
                                turtle_entry.periph and "(wired OK)" or "(no wired!)"),
                            turtle_entry.periph and colors.lime or colors.orange)
                    end
                else
                    turtle_entry.last_seen = os.clock()
                    turtle_entry.label = msg.label or turtle_entry.label
                    if turtle_entry.state == "offline" then
                        turtle_entry.state = "idle"
                    end
                end

                -- Respond to confirm we're here
                rednet.send(sender, {status = "wraith_craft_hub"}, proto.status)

            elseif protocol == proto.status and type(msg) == "table" and msg.action == "heartbeat" then
                -- Heartbeat from turtle
                local t = get_turtle_by_id(sender)
                if t then
                    t.last_seen = os.clock()
                    t.label = msg.label or t.label
                    if t.state == "offline" then
                        t.state = "idle"
                    end
                end

            elseif protocol == proto.result and type(msg) == "table" then
                -- Craft result from turtle
                if msg.action == "craft_result" then
                    local t = get_turtle_by_id(sender)
                    if t then
                        utils.add_notification(state,
                            string.format("CRAFT: Result from #%d: %s (crafted:%d returned:%d)",
                                sender, msg.success and "OK" or "FAIL",
                                msg.crafted or 0, msg.items_returned or 0),
                            msg.success and colors.lime or colors.red)
                        finish_craft(t, msg.success, msg.crafted or 0,
                            msg.items_returned or 0, msg.items_stuck or 0)
                    end
                end
            end

            end) -- end pcall(function()
            if not net_ok then
                utils.add_notification(state,
                    "CRAFT NET ERR: " .. tostring(net_err):sub(1, 40),
                    colors.red)
            end

        elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            -- Re-discover turtles on peripheral changes (no sleep — would eat events)
            discover_turtles()
        end
    end
end

return svc
