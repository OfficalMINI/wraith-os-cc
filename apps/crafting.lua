-- =============================================
-- WRAITH OS - CRAFTING APP
-- =============================================
-- Configure craft rules with 3x3 grid recipes,
-- per-ingredient thresholds, and batch tasks.
-- Uses IM to detect held items for grid placement.

local app = {
    id = "crafting",
    name = "Crafting",
    icon = "crafting",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1       -- 1=Overview, 2=Rules, 3=Tasks
local TAB_COUNT = 4
local scroll = 0
local sel_rule = 1
local sel_task = 1
local hits = {}

-- Item picker state (for output selection)
local picking = nil         -- nil | "output"
local picker_query = ""
local picker_scroll = 0
local picker_hits = {}
local picker_selected = nil

-- Recipe editor state
local editing = false       -- true when recipe editor overlay is active
local editor = {
    grid = {nil, nil, nil, nil, nil, nil, nil, nil, nil},
    output = nil,           -- {name, nbt, display}
    yield = 1,
    output_threshold = 0,
    ingredients = {},       -- built from grid: {[idx] = {name, nbt, display, threshold}}
    edit_idx = nil,         -- rule index if editing existing, nil if new
}

-- Grid slot (1-9) to turtle inventory slot mapping (for display)
local GRID_TO_TURTLE = {1, 2, 3, 5, 6, 7, 9, 10, 11}

-- ========================================
-- Helpers
-- ========================================

-- Build unique ingredients list from grid
local function rebuild_ingredients()
    local seen = {}
    local list = {}
    for slot = 1, 9 do
        local item_name = editor.grid[slot]
        if item_name and not seen[item_name] then
            seen[item_name] = true
            -- Preserve existing threshold if ingredient was already in list
            local existing_thr = 0
            for _, old in ipairs(editor.ingredients) do
                if old.name == item_name then
                    existing_thr = old.threshold
                    break
                end
            end
            table.insert(list, {
                name = item_name,
                nbt = nil,
                display = item_name,  -- will be overridden by IM data
                threshold = existing_thr,
            })
        end
    end
    editor.ingredients = list
end

-- Get the IM for the closest player, then return their held item.
-- Returns: item_detail_or_nil  (nil means empty hand or no IM)
local function get_held_item()
    local all_ims = {peripheral.find("inventoryManager")}
    if #all_ims == 0 then return nil end

    -- Find closest player via playerDetector
    local detector = peripheral.find("playerDetector")
    if detector then
        local ok, nearest = pcall(detector.getPlayersInRange, 8)
        if ok and nearest and #nearest > 0 then
            -- Match nearest player to their IM
            local closest_name = nearest[1]
            for _, im in ipairs(all_ims) do
                local owk, owner = pcall(im.getOwner)
                if owk and owner == closest_name then
                    local hok, held = pcall(im.getItemInHand)
                    if hok and held and held.name then return held end
                    return nil  -- closest player has empty hand
                end
            end
        end
    end

    -- No detector: fall back to first IM
    local ok, held = pcall(all_ims[1].getItemInHand)
    if ok and held and held.name then return held end
    return nil
end

-- ========================================
-- Render: Item Picker overlay
-- ========================================
local function render_item_picker(ctx, buf, x, y, w, h, purpose)
    local draw = ctx.draw
    local theme = ctx.theme
    local st = ctx.state.storage

    picker_hits = {}

    -- Title
    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Pick " .. purpose, theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    picker_hits.cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    -- Search bar
    draw.fill(buf, y, x + w, theme.surface2)
    local search_text_w = w - 22
    draw.put(buf, x + 1, y, "\16 [", theme.fg_dim, theme.surface2)
    local sq = picker_query ~= "" and picker_query or "search..."
    local sq_fg = picker_query ~= "" and theme.fg or theme.fg_dim
    draw.put(buf, x + 4, y, sq:sub(1, search_text_w - 2), sq_fg, theme.surface2)
    draw.put(buf, x + 4 + search_text_w - 2, y, "]", theme.fg_dim, theme.surface2)
    picker_hits.search_bar = {x = 1, y = y - hits.oy + 1, w = search_text_w + 3, h = 1}
    draw.button(buf, x + w - 10, y, 9, 1, "MANUAL ID", theme.accent, theme.btn_text, true)
    picker_hits.manual = {x = w - 10 + 1, y = y - hits.oy + 1, w = 9, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Filter items
    local items = st.items or {}
    local filtered = {}
    if picker_query == "" then
        filtered = items
    else
        local q = picker_query:lower()
        for _, item in ipairs(items) do
            if item.displayName:lower():find(q, 1, true) or
               item.name:lower():find(q, 1, true) then
                table.insert(filtered, item)
            end
        end
    end

    local has_sel = picker_selected ~= nil
    local area_h = h - 3 - (has_sel and 1 or 0)
    local max_scroll = math.max(0, #filtered - area_h)
    if picker_scroll > max_scroll then picker_scroll = max_scroll end
    picker_hits.max_scroll = max_scroll
    picker_hits.rows = {}

    for vi = 1, area_h do
        local idx = picker_scroll + vi
        local item = idx <= #filtered and filtered[idx] or nil
        local is_sel = item and picker_selected and item.name == picker_selected.name
        local rbg = is_sel and theme.accent or ((vi % 2 == 0) and theme.surface2 or theme.surface)
        local rfg = is_sel and theme.bg or theme.fg
        local rfg_dim = is_sel and theme.bg or theme.fg_dim
        draw.fill(buf, y, x + w, rbg)
        if item then
            local name_display = item.displayName or item.name
            if #name_display > 28 then name_display = name_display:sub(1, 26) .. ".." end
            draw.put(buf, x + 1, y, name_display, rfg, rbg)
            local count_str = tostring(item.count)
            draw.put(buf, x + w - #count_str - 1, y, count_str, rfg_dim, rbg)
            table.insert(picker_hits.rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1,
                name = item.name,
                nbt = item.nbt,
                displayName = item.displayName,
            })
        end
        y = y + 1
    end

    if has_sel then
        draw.fill(buf, y, x + w, theme.success)
        local sel_lbl = (picker_selected.displayName or "?"):sub(1, 25)
        draw.put(buf, x + 1, y, "\16 " .. sel_lbl, theme.bg, theme.success)
        draw.button(buf, x + w - 10, y, 9, 1, "CONFIRM", theme.accent, theme.btn_text, true)
        picker_hits.confirm = {x = w - 10 + 1, y = y - hits.oy + 1, w = 9, h = 1}
    end
end

-- ========================================
-- Render: Recipe Editor overlay
-- ========================================
local function render_editor(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils

    hits.editor = {}

    -- Title bar
    draw.fill(buf, y, x + w, theme.accent)
    local title = editor.edit_idx and "EDIT RECIPE" or "NEW RECIPE"
    draw.put(buf, x + 1, y, title, theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    hits.editor.cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    -- Instruction
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "Hold item & touch grid cell to place", theme.fg_dim, theme.surface2)
    y = y + 1

    -- Grid (3x3) + Output/Yield/Threshold info on the right
    local cell_w = 6
    local cell_h = 3
    local grid_x = x + 2
    local grid_y = y
    local info_x = x + 24

    hits.editor.grid_cells = {}

    -- Grid background fill
    local grid_total_w = cell_w * 3 + 4  -- 3 cells + 2 gaps + 2 border
    local grid_total_h = cell_h * 3 + 4  -- 3 cells + 2 gaps + 2 border
    draw.fillRect(buf, grid_x, grid_y, grid_total_w, grid_total_h, theme.border)

    for row = 0, 2 do
        for col = 0, 2 do
            local slot = row * 3 + col + 1
            local cx = grid_x + 1 + col * (cell_w + 1)
            local cy = grid_y + 1 + row * (cell_h + 1)

            -- Cell background
            local item_name = editor.grid[slot]
            local cbg = item_name and theme.surface2 or theme.surface
            draw.fillRect(buf, cx, cy, cell_w, cell_h, cbg)

            -- Cell content
            if item_name then
                local short = utils.clean_name and utils.clean_name(item_name) or item_name
                if #short > cell_w then short = short:sub(1, cell_w) end
                draw.put(buf, cx, cy + 1, short, theme.fg, cbg)
                -- Slot number in corner
                draw.put(buf, cx, cy, tostring(slot), theme.fg_dim, cbg)
            else
                draw.put(buf, cx + 1, cy + 1, " -- ", theme.fg_dim, cbg)
            end

            hits.editor.grid_cells[slot] = {
                x = cx - hits.ox + 1, y = cy - hits.oy + 1,
                w = cell_w, h = cell_h,
            }
        end
    end

    -- Arrow pointing to output
    local arrow_y = grid_y + grid_total_h / 2
    draw.put(buf, grid_x + grid_total_w + 1, arrow_y, "\16\16", theme.fg_dim, theme.bg)

    -- Right side: output, yield, thresholds
    local ry = grid_y

    -- Output
    draw.put(buf, info_x, ry, "OUTPUT:", theme.fg_dim, theme.bg)
    ry = ry + 1
    if editor.output then
        local out_label = (editor.output.display or editor.output.name):sub(1, 18)
        draw.put(buf, info_x, ry, out_label, theme.success, theme.bg)
    else
        draw.put(buf, info_x, ry, "(none)", theme.fg_dim, theme.bg)
    end
    draw.button(buf, info_x + 20, ry, 6, 1, "PICK", theme.accent, theme.btn_text, true)
    hits.editor.pick_output = {x = info_x + 20 - hits.ox + 1, y = ry - hits.oy + 1, w = 6, h = 1}
    ry = ry + 2

    -- Yield
    draw.put(buf, info_x, ry, "Yield:", theme.fg_dim, theme.bg)
    local yield_str = tostring(editor.yield)
    draw.button(buf, info_x + 7, ry, math.max(4, #yield_str + 2), 1,
        yield_str, theme.surface2, theme.fg, true)
    hits.editor.yield = {x = info_x + 7 - hits.ox + 1, y = ry - hits.oy + 1, w = math.max(4, #yield_str + 2), h = 1}
    ry = ry + 1

    -- Output threshold
    draw.put(buf, info_x, ry, "Out Thr:", theme.fg_dim, theme.bg)
    local thr_str = tostring(editor.output_threshold)
    draw.button(buf, info_x + 9, ry, math.max(4, #thr_str + 2), 1,
        thr_str, theme.surface2, theme.fg, true)
    hits.editor.out_threshold = {x = info_x + 9 - hits.ox + 1, y = ry - hits.oy + 1, w = math.max(4, #thr_str + 2), h = 1}
    ry = ry + 2

    -- Ingredients + thresholds
    draw.put(buf, info_x, ry, "INGREDIENTS:", theme.fg_dim, theme.bg)
    ry = ry + 1
    hits.editor.ing_thresholds = {}

    for i, ing in ipairs(editor.ingredients) do
        if ry >= y + h - 2 then break end
        local name = utils.clean_name and utils.clean_name(ing.name) or ing.name
        if #name > 10 then name = name:sub(1, 9) .. "." end
        draw.put(buf, info_x, ry, name, theme.fg, theme.bg)
        local ithr = tostring(ing.threshold)
        draw.put(buf, info_x + 12, ry, "f:", theme.fg_dim, theme.bg)
        draw.button(buf, info_x + 14, ry, math.max(4, #ithr + 2), 1,
            ithr, theme.surface2, theme.fg, true)
        hits.editor.ing_thresholds[i] = {
            x = info_x + 14 - hits.ox + 1, y = ry - hits.oy + 1,
            w = math.max(4, #ithr + 2), h = 1,
        }
        ry = ry + 1
    end

    -- Bottom buttons
    local btn_y = y + h - 1
    draw.fill(buf, btn_y, x + w, theme.surface)
    local bx = x + 2
    draw.button(buf, bx, btn_y, 12, 1, "CLEAR GRID", theme.warning, theme.btn_text, true)
    hits.editor.clear_grid = {x = bx - hits.ox + 1, y = btn_y - hits.oy + 1, w = 12, h = 1}

    local has_grid = false
    for s = 1, 9 do if editor.grid[s] then has_grid = true; break end end
    local can_save = editor.output ~= nil and has_grid

    draw.button(buf, x + w - 18, btn_y, 8, 1, "SAVE",
        can_save and theme.success or theme.surface2,
        can_save and theme.btn_text or theme.fg_dim, can_save)
    hits.editor.save = {x = w - 18 + 1, y = btn_y - hits.oy + 1, w = 8, h = 1}

    draw.button(buf, x + w - 9, btn_y, 8, 1, "CANCEL", theme.danger, theme.btn_text, true)
    hits.editor.cancel2 = {x = w - 9 + 1, y = btn_y - hits.oy + 1, w = 8, h = 1}
end

-- ========================================
-- Render: Overview Tab
-- ========================================
local function render_overview(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local cr = ctx.state.crafting
    local utils = ctx.utils

    local stats = cr.get_stats and cr.get_stats() or {}

    -- Helper: get stock of an item (sum across all NBT variants)
    local function get_stock(item_name)
        local st = ctx.state.storage
        if not st or not st.items then return 0 end
        local total = 0
        for _, item in ipairs(st.items) do
            if item.name == item_name then total = total + item.count end
        end
        return total
    end

    -- Helper: diagnose why a rule isn't crafting
    local function diagnose_rule(rule)
        if not rule.enabled then return "OFF", theme.fg_dim end
        if not cr.crafting_enabled then return "Auto-craft OFF", theme.fg_dim end
        if (stats.usable or 0) == 0 then
            if (stats.turtle_count or 0) == 0 then return "No turtles", theme.danger end
            -- Check why turtles aren't usable
            local has_idle = false
            for _, t in ipairs(cr.turtles) do
                if t.state == "idle" then has_idle = true; break end
            end
            if not has_idle then return "Turtles busy", theme.warning end
            return "No usable turtle", theme.danger
        end

        -- Check output threshold
        if rule.output_threshold > 0 then
            local stock = rule.output and get_stock(rule.output.name) or 0
            if stock >= rule.output_threshold then
                return string.format("Stocked %d/%d", stock, rule.output_threshold), theme.fg_dim
            end
        else
            return "Manual only", theme.fg_dim
        end

        -- Check ingredients
        local ing_counts = {}
        for s = 1, 9 do
            local n = rule.grid[s]
            if n then ing_counts[n] = (ing_counts[n] or 0) + 1 end
        end

        for item_name, per_craft in pairs(ing_counts) do
            local stock = get_stock(item_name)
            local ing_thr = 0
            for _, ing in ipairs(rule.ingredients or {}) do
                if ing.name == item_name then ing_thr = ing.threshold or 0; break end
            end
            local needed = per_craft + ing_thr
            if stock < needed then
                local short_name = utils.clean_name and utils.clean_name(item_name) or item_name
                if #short_name > 12 then short_name = short_name:sub(1, 11) .. "." end
                if ing_thr > 0 then
                    -- Show "item stock<need+reserve" so threshold is visible
                    return string.format("%s %d<%d+%d", short_name, stock, per_craft, ing_thr), theme.danger
                else
                    return string.format("Need %s %d/%d", short_name, stock, per_craft), theme.danger
                end
            end
        end

        return "Ready to craft", theme.success
    end

    -- Toggle + status
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("Turtles: %d (%d usable)",
        stats.turtle_count or 0, stats.usable or 0), theme.fg, theme.surface)
    local on = cr.crafting_enabled
    local sl = on and "CRAFT ON" or "CRAFT OFF"
    draw.button(buf, x + w - 11, y, 10, 1, sl, on and theme.success or theme.danger, theme.btn_text, true)
    hits.toggle = {x = w - 11 + 1, y = y - hits.oy + 1, w = 10, h = 1}
    y = y + 1

    -- Service craft status line
    draw.fill(buf, y, x + w, theme.surface)
    local cs = stats.craft_status or "..."
    local cs_col = theme.fg_dim
    if cs:find("^crafting") or cs:find("^task:") then cs_col = theme.success
    elseif cs:find("no ") or cs:find("busy") then cs_col = theme.warning
    elseif cs == "disabled" then cs_col = theme.fg_dim
    end
    draw.put(buf, x + 1, y, "Status: ", theme.fg_dim, theme.surface)
    draw.put(buf, x + 9, y, cs, cs_col, theme.surface)
    y = y + 1

    -- Turtle list
    for _, t in ipairs(cr.turtles) do
        if y >= ctx.content_y + h - 2 then break end
        draw.fill(buf, y, x + w, theme.surface)
        local lbl = t.label or t.name or "?"
        if #lbl > 16 then lbl = lbl:sub(1, 15) .. "." end
        local scol = t.state == "crafting" and theme.success
            or t.state == "offline" and theme.danger
            or theme.fg_dim
        local sid = t.id and ("#" .. t.id) or "no ID"
        local periph_ok = t.periph and "W" or "!W"
        draw.put(buf, x + 1, y, "\7", scol, theme.surface)
        draw.put(buf, x + 3, y, lbl, theme.fg, theme.surface)
        draw.put(buf, x + 20, y, t.state, scol, theme.surface)
        draw.put(buf, x + 30, y, sid, t.id and theme.fg_dim or theme.danger, theme.surface)
        draw.put(buf, x + 38, y, periph_ok, t.periph and theme.success or theme.danger, theme.surface)
        y = y + 1
    end
    if #cr.turtles == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No turtles connected", theme.fg_dim, theme.surface)
        y = y + 1
    end

    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("Items crafted: %s",
        utils.format_number(cr.items_crafted or 0)),
        theme.fg_dim, theme.surface)
    y = y + 1

    -- Rules with diagnostics
    local rules = cr.craft_rules or {}
    local tasks = cr.craft_tasks or {}
    local active_tasks_count = 0
    for _, t in ipairs(tasks) do if t.active then active_tasks_count = active_tasks_count + 1 end end
    -- Reserve space for tasks section: header + active tasks + 1 padding (min 3)
    local task_reserve = math.max(3, active_tasks_count + 2)

    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "RULES", theme.accent, theme.surface2)
    y = y + 1

    for i, rule in ipairs(rules) do
        if y >= ctx.content_y + h - task_reserve then break end

        -- Rule name line
        draw.fill(buf, y, x + w, theme.surface)
        local status_col = rule.enabled and theme.success or theme.fg_dim
        draw.put(buf, x + 1, y, rule.enabled and "\7" or "\8", status_col, theme.surface)
        local lbl = rule.output and (rule.output.display or rule.output.name) or "?"
        if #lbl > 18 then lbl = lbl:sub(1, 17) .. "." end
        draw.put(buf, x + 3, y, lbl, theme.fg, theme.surface)
        draw.put(buf, x + 22, y, "x" .. (rule.yield or 1), theme.fg_dim, theme.surface)

        -- Diagnostic (start earlier, allow more room)
        local diag, dcol = diagnose_rule(rule)
        local diag_max = w - 26
        if #diag > diag_max then diag = diag:sub(1, diag_max - 1) .. "." end
        draw.put(buf, x + 26, y, diag, dcol, theme.surface)
        y = y + 1
    end
    if #rules == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No rules. Go to Rules tab to add one.", theme.fg_dim, theme.surface)
        y = y + 1
    end
    y = y + 1

    -- Tasks summary (tasks/active_tasks_count already computed above)
    if y < ctx.content_y + h - 2 then
        draw.fill(buf, y, x + w, theme.surface2)
        draw.put(buf, x + 1, y, string.format("TASKS: %d active", active_tasks_count), theme.accent, theme.surface2)
        y = y + 1

        for _, task in ipairs(tasks) do
            if not task.active then goto cont_task end
            if y >= ctx.content_y + h - 1 then break end
            draw.fill(buf, y, x + w, theme.surface)
            local rule = cr.craft_rules[task.rule_idx]
            local lbl = rule and rule.output and (rule.output.display or "?") or "?"
            if #lbl > 18 then lbl = lbl:sub(1, 17) .. "." end
            draw.put(buf, x + 1, y, lbl, theme.fg, theme.surface)
            local pct = task.target > 0 and (task.crafted / task.target) or 0
            local bar_w = 12
            local filled = math.floor(pct * bar_w)
            buf.setCursorPos(x + 22, y)
            buf.setBackgroundColor(theme.success)
            buf.write(string.rep(" ", filled))
            buf.setBackgroundColor(theme.border)
            buf.write(string.rep(" ", bar_w - filled))
            draw.put(buf, x + 35, y,
                string.format("%d/%d %d%%", task.crafted, task.target, math.floor(pct * 100)),
                theme.fg_dim, theme.surface)
            y = y + 1
            ::cont_task::
        end
    end
end

-- ========================================
-- Render: Rules Tab
-- ========================================
local function render_rules(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local cr = ctx.state.crafting
    local utils = ctx.utils

    local rules = cr.craft_rules or {}

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "OUTPUT", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 22, y, "YIELD", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 30, y, "THR", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 38, y, "ON", theme.fg_dim, theme.surface2)
    y = y + 1

    -- Reserve rows for selected rule detail + buttons
    local detail_rows = 0
    if sel_rule >= 1 and sel_rule <= #rules then
        local rule = rules[sel_rule]
        detail_rows = 2 + #(rule.ingredients or {})  -- separator + header + ingredients
        detail_rows = math.min(detail_rows, 6)  -- cap
    end

    local area_h = h - 3 - detail_rows
    local max_scroll = math.max(0, #rules - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.rule_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local is_sel = (idx == sel_rule)
        local rbg = is_sel and theme.accent or ((vi % 2 == 0) and theme.surface2 or theme.surface)
        local rfg = is_sel and theme.bg or theme.fg
        local rfg_dim = is_sel and theme.bg or theme.fg_dim
        draw.fill(buf, y, x + w, rbg)
        if idx <= #rules then
            local rule = rules[idx]
            local outp = rule.output and (rule.output.display or rule.output.name) or "?"
            if #outp > 19 then outp = outp:sub(1, 18) .. "." end
            draw.put(buf, x + 1, y, outp, rfg, rbg)
            draw.put(buf, x + 22, y, "x" .. (rule.yield or 1), rfg_dim, rbg)
            if rule.output_threshold > 0 then
                draw.put(buf, x + 30, y, tostring(rule.output_threshold), rfg, rbg)
            else
                draw.put(buf, x + 30, y, "0", rfg_dim, rbg)
            end
            local on_col = is_sel and theme.bg or (rule.enabled and theme.success or theme.danger)
            draw.put(buf, x + 38, y, rule.enabled and "YES" or "NO", on_col, rbg)

            table.insert(hits.rule_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx,
            })
        end
        y = y + 1
    end

    -- Selected rule ingredient detail
    if sel_rule >= 1 and sel_rule <= #rules then
        local rule = rules[sel_rule]
        draw.fill(buf, y, x + w, theme.surface2)
        draw.put(buf, x + 1, y, "INGREDIENTS:", theme.accent, theme.surface2)

        -- Count per ingredient
        local ing_counts = {}
        for s = 1, 9 do
            local n = rule.grid[s]
            if n then ing_counts[n] = (ing_counts[n] or 0) + 1 end
        end
        y = y + 1

        local shown = 0
        for _, ing in ipairs(rule.ingredients or {}) do
            if shown >= 5 then break end
            draw.fill(buf, y, x + w, theme.surface)
            local name = utils.clean_name and utils.clean_name(ing.name) or ing.name
            if #name > 18 then name = name:sub(1, 17) .. "." end
            local cnt = ing_counts[ing.name] or 0
            draw.put(buf, x + 2, y, name, theme.fg, theme.surface)
            draw.put(buf, x + 22, y, "x" .. cnt, theme.fg_dim, theme.surface)
            if ing.threshold > 0 then
                draw.put(buf, x + 28, y, "floor:" .. ing.threshold, theme.warning, theme.surface)
            else
                draw.put(buf, x + 28, y, "floor:0", theme.fg_dim, theme.surface)
            end
            y = y + 1
            shown = shown + 1
        end
        if #(rule.ingredients or {}) == 0 then
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 2, y, "(no ingredients)", theme.fg_dim, theme.surface)
            y = y + 1
        end
    end

    -- Info
    draw.fill(buf, y, x + w, theme.surface2)
    draw.center(buf, string.format("%d rules", #rules), y, x + w, theme.fg_dim, theme.surface2)
    y = y + 1

    -- Buttons
    draw.fill(buf, y, x + w, theme.surface)
    local bx = x + 1
    draw.button(buf, bx, y, 7, 1, "+ ADD", theme.accent, theme.btn_text, true)
    hits.rule_add = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 7, h = 1}
    bx = bx + 8
    local has_sel = sel_rule >= 1 and sel_rule <= #rules
    draw.button(buf, bx, y, 6, 1, "EDIT", has_sel and theme.accent or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_edit = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 6, h = 1}
    bx = bx + 7
    draw.button(buf, bx, y, 10, 1, "EDIT THR", has_sel and theme.accent or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_edit_thr = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 10, h = 1}
    bx = bx + 11
    draw.button(buf, bx, y, 4, 1, "ON", has_sel and theme.warning or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_toggle = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 4, h = 1}
    bx = bx + 5
    draw.button(buf, bx, y, 5, 1, "DEL", has_sel and theme.danger or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_delete = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 5, h = 1}
end

-- ========================================
-- Render: Tasks Tab
-- ========================================
local function render_tasks(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local cr = ctx.state.crafting
    local utils = ctx.utils

    local tasks = cr.craft_tasks or {}

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "RECIPE", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 20, y, "PROGRESS", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 40, y, "STATUS", theme.fg_dim, theme.surface2)
    y = y + 1

    local area_h = h - 3
    local max_scroll = math.max(0, #tasks - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.task_max_scroll = max_scroll
    hits.task_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local is_sel = (idx == sel_task)
        local rbg = is_sel and theme.accent or ((vi % 2 == 0) and theme.surface2 or theme.surface)
        local rfg = is_sel and theme.bg or theme.fg
        local rfg_dim = is_sel and theme.bg or theme.fg_dim
        draw.fill(buf, y, x + w, rbg)
        if idx <= #tasks then
            local task = tasks[idx]
            local rule = cr.craft_rules[task.rule_idx]
            local lbl = rule and rule.output and (rule.output.display or "?") or "Orphaned"
            if #lbl > 17 then lbl = lbl:sub(1, 16) .. "." end
            draw.put(buf, x + 1, y, lbl, rfg, rbg)

            local pct = task.target > 0 and (task.crafted / task.target) or 0
            local prog = string.format("%d/%d %d%%", task.crafted, task.target, math.floor(pct * 100))
            draw.put(buf, x + 20, y, prog, rfg_dim, rbg)

            local status_lbl = task.active and "ACTIVE" or "DONE"
            local status_col = is_sel and theme.bg or (task.active and theme.success or theme.fg_dim)
            draw.put(buf, x + 40, y, status_lbl, status_col, rbg)

            table.insert(hits.task_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx,
            })
        end
        y = y + 1
    end

    -- Info
    local active_count = 0
    for _, t in ipairs(tasks) do if t.active then active_count = active_count + 1 end end
    draw.fill(buf, y, x + w, theme.surface2)
    draw.center(buf, string.format("%d tasks (%d active)", #tasks, active_count), y, x + w, theme.fg_dim, theme.surface2)
    y = y + 1

    -- Buttons
    draw.fill(buf, y, x + w, theme.surface)
    local bx = x + 1
    local has_rules = #(cr.craft_rules or {}) > 0
    draw.button(buf, bx, y, 8, 1, "+ NEW", has_rules and theme.accent or theme.surface2,
        has_rules and theme.btn_text or theme.fg_dim, has_rules)
    hits.task_new = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 8, h = 1}
    bx = bx + 9
    local has_sel = sel_task >= 1 and sel_task <= #tasks
    local can_cancel = has_sel and tasks[sel_task] and tasks[sel_task].active
    draw.button(buf, bx, y, 8, 1, "CANCEL", can_cancel and theme.danger or theme.surface2,
        can_cancel and theme.btn_text or theme.fg_dim, can_cancel)
    hits.task_cancel = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 8, h = 1}
    bx = bx + 9
    local has_done = false
    for _, t in ipairs(tasks) do if not t.active then has_done = true; break end end
    draw.button(buf, bx, y, 12, 1, "CLEAR DONE", has_done and theme.warning or theme.surface2,
        has_done and theme.btn_text or theme.fg_dim, has_done)
    hits.task_clear = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 12, h = 1}
end

-- ========================================
-- Tab 4: History
-- ========================================
local function render_history(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local cr = ctx.state.crafting

    local history = cr.craft_history or {}

    -- Build sorted list
    local entries = {}
    local total = 0
    for item_name, count in pairs(history) do
        table.insert(entries, {name = item_name, count = count})
        total = total + count
    end
    table.sort(entries, function(a, b) return a.count > b.count end)

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "CRAFT HISTORY", theme.accent, theme.surface2)
    draw.put(buf, x + w - 20, y,
        string.format("Total: %s", utils.format_number(total)),
        theme.fg_dim, theme.surface2)
    y = y + 1

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "ITEM", theme.fg_dim, theme.surface)
    draw.put(buf, x + w - 12, y, "COUNT", theme.fg_dim, theme.surface)
    y = y + 1

    if #entries == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.center(buf, "No crafts recorded yet", y, x + w, theme.fg_dim, theme.surface)
        hits.hist_max_scroll = 0
        return
    end

    -- Scrollable list
    local visible = h - 2
    hits.hist_max_scroll = math.max(0, #entries - visible)
    scroll = math.min(scroll, hits.hist_max_scroll)

    for row = 0, visible - 1 do
        local idx = row + scroll + 1
        local rbg = (row % 2 == 0) and theme.surface or theme.surface2
        draw.fill(buf, y, x + w, rbg)
        if idx <= #entries then
            local e = entries[idx]
            local lbl = e.name
            if #lbl > w - 16 then lbl = lbl:sub(1, w - 17) .. "." end
            draw.put(buf, x + 1, y, lbl, theme.fg, rbg)
            local cnt_str = utils.format_number(e.count)
            draw.put(buf, x + w - #cnt_str - 1, y, cnt_str, theme.accent, rbg)
        end
        y = y + 1
    end
end

-- ========================================
-- Main Render
-- ========================================
function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils

    hits = {}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Item picker overlay
    if picking then
        render_item_picker(ctx, buf, x, y, w, h, "Output Item")
        return
    end

    -- Recipe editor overlay
    if editing then
        render_editor(ctx, buf, x, y, w, h)
        return
    end

    -- Header (4 rows)
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.crafting
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data and icon_lib then icon_lib.draw(buf, icon_data, x + 2, y) end

    local sx = x + 11
    draw.put(buf, sx, y, "CRAFTING", theme.accent, theme.surface2)

    local cr = ctx.state.crafting
    local stats = cr.get_stats and cr.get_stats() or {}
    draw.put(buf, sx, y + 1,
        string.format("%d turtles | Auto-Craft: %s",
            stats.turtle_count or 0, cr.crafting_enabled and "ON" or "OFF"),
        cr.crafting_enabled and theme.success or theme.fg_dim, theme.surface2)
    draw.put(buf, sx, y + 2,
        string.format("Crafted: %s  Rules: %d",
            utils.format_number(cr.items_crafted or 0),
            stats.rules_count or 0),
        theme.fg_dim, theme.surface2)
    local active_tasks = 0
    for _, t in ipairs(cr.craft_tasks or {}) do if t.active then active_tasks = active_tasks + 1 end end
    draw.put(buf, sx, y + 3,
        string.format("Tasks: %d active", active_tasks),
        theme.fg_dim, theme.surface2)

    y = y + 4

    -- Tab bar
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"OVERVIEW", "RULES", "TASKS", "HISTORY"}
    local tw = math.floor(w / TAB_COUNT)
    hits.tabs = {}
    for ti = 1, TAB_COUNT do
        local tx = x + (ti - 1) * tw
        local sel = (ti == tab)
        local tbg = sel and theme.accent or theme.surface
        local tfg = sel and theme.bg or theme.fg_dim
        buf.setCursorPos(tx, y)
        buf.setBackgroundColor(tbg)
        buf.setTextColor(tfg)
        buf.write(utils.pad_center(tab_labels[ti], tw))
        hits.tabs[ti] = {x = tx - hits.ox + 1, y = y - hits.oy + 1, w = tw, h = 1}
    end
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Content
    local content_h = h - 6
    if tab == 1 then
        render_overview(ctx, buf, x, y, w, content_h)
    elseif tab == 2 then
        render_rules(ctx, buf, x, y, w, content_h)
    elseif tab == 3 then
        render_tasks(ctx, buf, x, y, w, content_h)
    elseif tab == 4 then
        render_history(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Editor Helpers
-- ========================================

local function open_editor(rule_idx)
    editing = true
    if rule_idx and _G._wraith.state.crafting.craft_rules[rule_idx] then
        local rule = _G._wraith.state.crafting.craft_rules[rule_idx]
        editor.edit_idx = rule_idx
        editor.grid = {}
        for i = 1, 9 do editor.grid[i] = rule.grid[i] end
        editor.output = rule.output and {name = rule.output.name, nbt = rule.output.nbt, display = rule.output.display} or nil
        editor.yield = rule.yield or 1
        editor.output_threshold = rule.output_threshold or 0
        editor.ingredients = {}
        for _, ing in ipairs(rule.ingredients or {}) do
            table.insert(editor.ingredients, {
                name = ing.name, nbt = ing.nbt, display = ing.display,
                threshold = ing.threshold or 0,
            })
        end
    else
        editor.edit_idx = nil
        editor.grid = {nil, nil, nil, nil, nil, nil, nil, nil, nil}
        editor.output = nil
        editor.yield = 1
        editor.output_threshold = 0
        editor.ingredients = {}
    end
end

local function save_editor(cr)
    local grid = {}
    for i = 1, 9 do grid[i] = editor.grid[i] end

    if editor.edit_idx and cr.craft_rules[editor.edit_idx] then
        -- Update existing rule
        local rule = cr.craft_rules[editor.edit_idx]
        rule.output = editor.output
        rule.grid = grid
        rule.ingredients = editor.ingredients
        rule.yield = editor.yield
        rule.output_threshold = editor.output_threshold
        cr.update_rule(editor.edit_idx, "grid", grid)
        -- Save all fields
        cr.update_rule(editor.edit_idx, "output", editor.output)
        cr.update_rule(editor.edit_idx, "ingredients", editor.ingredients)
        cr.update_rule(editor.edit_idx, "yield", editor.yield)
        cr.update_rule(editor.edit_idx, "output_threshold", editor.output_threshold)
    else
        -- Add new rule
        cr.add_rule(editor.output, grid, editor.ingredients, editor.yield, editor.output_threshold)
    end

    editing = false
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local cr = ctx.state.crafting
    local draw = ctx.draw
    local utils = ctx.utils

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3], ev[4]

            -- Item picker mode
            if picking then
                if picker_hits.cancel and draw.hit_test(picker_hits.cancel, tx, ty) then
                    picking = nil
                    picker_query = ""
                    picker_scroll = 0
                    picker_selected = nil
                elseif picker_hits.manual and draw.hit_test(picker_hits.manual, tx, ty) then
                    local result = utils.pc_input("ITEM ID", "Enter minecraft item ID (e.g. minecraft:cobblestone):")
                    if result and #result > 0 then
                        local name = result
                        local display = utils.clean_name and utils.clean_name(name) or name
                        picker_selected = {name = name, displayName = display}
                    end
                elseif picker_hits.search_bar and draw.hit_test(picker_hits.search_bar, tx, ty) then
                    local result = utils.pc_input("SEARCH ITEMS", "Type item name to filter:")
                    if result then picker_query = result else picker_query = "" end
                    picker_scroll = 0
                    picker_selected = nil
                elseif picker_hits.confirm and picker_selected and draw.hit_test(picker_hits.confirm, tx, ty) then
                    if picking == "output" then
                        editor.output = {
                            name = picker_selected.name,
                            nbt = picker_selected.nbt,
                            display = picker_selected.displayName,
                        }
                    end
                    picking = nil
                    picker_query = ""
                    picker_scroll = 0
                    picker_selected = nil
                else
                    for _, row in ipairs(picker_hits.rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            picker_selected = {name = row.name, nbt = row.nbt, displayName = row.displayName}
                            break
                        end
                    end
                end
                goto done
            end

            -- Recipe editor mode
            if editing then
                local eh = hits.editor or {}

                -- Cancel buttons
                if (eh.cancel and draw.hit_test(eh.cancel, tx, ty)) or
                   (eh.cancel2 and draw.hit_test(eh.cancel2, tx, ty)) then
                    editing = false
                    goto done
                end

                -- Grid cells — use IM to detect held item, or clear on touch
                if eh.grid_cells then
                    for slot = 1, 9 do
                        local cell = eh.grid_cells[slot]
                        if cell and draw.hit_test(cell, tx, ty) then
                            local held = get_held_item()
                            if held then
                                -- Place/replace item in slot
                                editor.grid[slot] = held.name
                                rebuild_ingredients()
                                -- Set display for this ingredient
                                for _, ing in ipairs(editor.ingredients) do
                                    if ing.name == held.name then
                                        ing.display = held.displayName or held.name
                                        break
                                    end
                                end
                            else
                                -- Empty hand or no IM: clear the slot
                                editor.grid[slot] = nil
                                rebuild_ingredients()
                            end
                            break
                        end
                    end
                end

                -- Pick output button
                if eh.pick_output and draw.hit_test(eh.pick_output, tx, ty) then
                    picking = "output"
                    picker_query = ""
                    picker_scroll = 0
                    picker_hits = {}
                    picker_selected = nil
                    goto done
                end

                -- Yield edit
                if eh.yield and draw.hit_test(eh.yield, tx, ty) then
                    local result = utils.pc_input("YIELD", "Items produced per craft:", tostring(editor.yield))
                    local val = tonumber(result)
                    if val and val > 0 then editor.yield = math.floor(val) end
                end

                -- Output threshold edit
                if eh.out_threshold and draw.hit_test(eh.out_threshold, tx, ty) then
                    local result = utils.pc_input("OUT THRESHOLD", "Auto-craft when stock below (0=manual):", tostring(editor.output_threshold))
                    local val = tonumber(result)
                    if val then editor.output_threshold = math.max(0, math.floor(val)) end
                end

                -- Ingredient threshold edits
                for i, area in ipairs(eh.ing_thresholds or {}) do
                    if draw.hit_test(area, tx, ty) and editor.ingredients[i] then
                        local ing = editor.ingredients[i]
                        local name = utils.clean_name and utils.clean_name(ing.name) or ing.name
                        local result = utils.pc_input("FLOOR: " .. name,
                            "Min stock to keep (0=no limit):", tostring(ing.threshold))
                        local val = tonumber(result)
                        if val then ing.threshold = math.max(0, math.floor(val)) end
                        break
                    end
                end

                -- Clear grid
                if eh.clear_grid and draw.hit_test(eh.clear_grid, tx, ty) then
                    for i = 1, 9 do editor.grid[i] = nil end
                    editor.ingredients = {}
                end

                -- Save
                if eh.save and draw.hit_test(eh.save, tx, ty) then
                    -- Verify we have at least something
                    local has_grid = false
                    for i = 1, 9 do if editor.grid[i] then has_grid = true; break end end
                    if editor.output and has_grid then
                        save_editor(cr)
                    end
                end

                goto done
            end

            -- Tab clicks
            local tab_clicked = false
            for ti, area in ipairs(hits.tabs or {}) do
                if draw.hit_test(area, tx, ty) then
                    if ti ~= tab then
                        tab = ti
                        scroll = 0
                    end
                    tab_clicked = true
                    break
                end
            end

            if not tab_clicked then
                if tab == 1 then
                    if hits.toggle and draw.hit_test(hits.toggle, tx, ty) then
                        if cr.toggle_crafting then cr.toggle_crafting() end
                    end

                elseif tab == 2 then
                    local handled = false

                    -- Row selection
                    for _, row in ipairs(hits.rule_rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            sel_rule = row.idx
                            handled = true
                            break
                        end
                    end

                    -- Add rule (opens editor)
                    if not handled and hits.rule_add and draw.hit_test(hits.rule_add, tx, ty) then
                        open_editor(nil)
                        handled = true
                    end

                    -- Edit rule (opens editor with existing data)
                    if not handled and hits.rule_edit and draw.hit_test(hits.rule_edit, tx, ty) then
                        local rules = cr.craft_rules or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            open_editor(sel_rule)
                        end
                        handled = true
                    end

                    -- Edit output threshold
                    if not handled and hits.rule_edit_thr and draw.hit_test(hits.rule_edit_thr, tx, ty) then
                        local rules = cr.craft_rules or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            local current = tostring(rules[sel_rule].output_threshold or 0)
                            local result = utils.pc_input("OUT THRESHOLD", "Auto-craft when stock below (0=manual):", current)
                            if result then
                                local thr = tonumber(result) or 0
                                if thr < 0 then thr = 0 end
                                cr.update_rule(sel_rule, "output_threshold", thr)
                            end
                        end
                        handled = true
                    end

                    -- Toggle rule
                    if not handled and hits.rule_toggle and draw.hit_test(hits.rule_toggle, tx, ty) then
                        local rules = cr.craft_rules or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            cr.toggle_rule(sel_rule)
                        end
                        handled = true
                    end

                    -- Delete rule
                    if not handled and hits.rule_delete and draw.hit_test(hits.rule_delete, tx, ty) then
                        local rules = cr.craft_rules or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            cr.remove_rule(sel_rule)
                            if sel_rule > #rules - 1 and sel_rule > 1 then
                                sel_rule = sel_rule - 1
                            end
                        end
                        handled = true
                    end

                elseif tab == 3 then
                    local handled = false

                    -- Row selection
                    for _, row in ipairs(hits.task_rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            sel_task = row.idx
                            handled = true
                            break
                        end
                    end

                    -- New task — pick from existing rules
                    if not handled and hits.task_new and draw.hit_test(hits.task_new, tx, ty) then
                        local rules = cr.craft_rules or {}
                        if #rules > 0 then
                            -- Use sel_rule as default rule, or 1
                            local rule_idx = sel_rule
                            if rule_idx < 1 or rule_idx > #rules then rule_idx = 1 end
                            local rule = rules[rule_idx]
                            local name = rule.output and rule.output.display or "Rule " .. rule_idx
                            local qty_str = utils.pc_input("CRAFT TASK: " .. name,
                                "How many to craft? (Rule #" .. rule_idx .. ")", "64")
                            local qty = tonumber(qty_str)
                            if qty and qty > 0 then
                                cr.add_task(rule_idx, math.floor(qty))
                            end
                        end
                        handled = true
                    end

                    -- Cancel task
                    if not handled and hits.task_cancel and draw.hit_test(hits.task_cancel, tx, ty) then
                        local tasks = cr.craft_tasks or {}
                        if sel_task >= 1 and sel_task <= #tasks and tasks[sel_task].active then
                            cr.cancel_task(sel_task)
                        end
                        handled = true
                    end

                    -- Clear done
                    if not handled and hits.task_clear and draw.hit_test(hits.task_clear, tx, ty) then
                        if cr.clear_completed_tasks then
                            cr.clear_completed_tasks()
                            sel_task = 1
                        end
                        handled = true
                    end
                end
            end

            ::done::

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if picking then
                picker_scroll = math.max(0, math.min(picker_hits.max_scroll or 0, picker_scroll + dir))
            elseif not editing then
                if tab == 2 then
                    scroll = math.max(0, math.min(hits.max_scroll or 0, scroll + dir))
                elseif tab == 3 then
                    scroll = math.max(0, math.min(hits.task_max_scroll or 0, scroll + dir))
                elseif tab == 4 then
                    scroll = math.max(0, math.min(hits.hist_max_scroll or 0, scroll + dir))
                end
            end

        elseif ev[1] == "key" then
            if picking or editing then
                -- no key handling in overlays
            elseif ev[2] == keys.tab then
                tab = (tab % TAB_COUNT) + 1
                scroll = 0
            elseif tab == 2 then
                local rules = cr.craft_rules or {}
                if ev[2] == keys.up and sel_rule > 1 then
                    sel_rule = sel_rule - 1
                elseif ev[2] == keys.down and sel_rule < #rules then
                    sel_rule = sel_rule + 1
                end
            elseif tab == 3 then
                local tasks = cr.craft_tasks or {}
                if ev[2] == keys.up and sel_task > 1 then
                    sel_task = sel_task - 1
                elseif ev[2] == keys.down and sel_task < #tasks then
                    sel_task = sel_task + 1
                end
            end
        end
    end
end

return app
