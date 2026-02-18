-- =============================================
-- WRAITH OS - SMELTING APP
-- =============================================
-- Configure smelt rules, thresholds, and bulk tasks.

local app = {
    id = "smelting",
    name = "Smelting",
    icon = "smelting",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1       -- 1=Overview, 2=Rules, 3=Tasks
local TAB_COUNT = 3
local scroll = 0
local sel_rule = 1
local sel_task = 1
local hits = {}

-- Item picker state: only ever picks ONE item, returns to caller
local picking = nil         -- nil | "rule_input" | "rule_output" | "task_input"
local picker_query = ""
local picker_scroll = 0
local picker_hits = {}
local picker_selected = nil -- {name, displayName} - selected but not confirmed yet

-- Pending rule: after picking input, this holds partial data until output is picked
local pending_rule = nil    -- nil | {input, input_display}

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

    -- Reserve 1 row for confirm bar when something is selected
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
                displayName = item.displayName,
            })
        end
        y = y + 1
    end

    -- Confirm bar (only when an item is selected)
    if has_sel then
        draw.fill(buf, y, x + w, theme.success)
        local sel_lbl = (picker_selected.displayName or "?"):sub(1, 25)
        draw.put(buf, x + 1, y, "\16 " .. sel_lbl, theme.bg, theme.success)
        draw.button(buf, x + w - 10, y, 9, 1, "CONFIRM", theme.accent, theme.btn_text, true)
        picker_hits.confirm = {x = w - 10 + 1, y = y - hits.oy + 1, w = 9, h = 1}
    end
end

-- ========================================
-- Render: Overview Tab
-- ========================================
local function render_overview(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local st = ctx.state.storage
    local utils = ctx.utils

    local sm = st.get_smelting_stats and st.get_smelting_stats() or {}
    local on = sm.enabled

    -- Toggle
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("Furnaces: %d", sm.furnace_count or 0), theme.fg, theme.surface)
    local sl = on and "SMELT ON" or "SMELT OFF"
    draw.button(buf, x + w - 11, y, 10, 1, sl, on and theme.success or theme.danger, theme.btn_text, true)
    hits.toggle = {x = w - 11 + 1, y = y - hits.oy + 1, w = 10, h = 1}
    y = y + 1

    -- Stats
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("Fuel: %s  Smeltable: %s",
        utils.format_number(st.cached_fuel_total or 0),
        utils.format_number(st.cached_smeltable_total or 0)), theme.fg_dim, theme.surface)
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("IN: %s  OUT: %s",
        utils.format_number(sm.items_smelted or 0),
        utils.format_number(sm.items_pulled or 0)), theme.fg_dim, theme.surface)
    y = y + 2

    -- Active Rules summary
    local rules = st.get_smelt_rules and st.get_smelt_rules() or {}
    local active_rules = 0
    for _, r in ipairs(rules) do if r.enabled then active_rules = active_rules + 1 end end

    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, string.format("RULES: %d active / %d total", active_rules, #rules), theme.accent, theme.surface2)
    y = y + 1

    for i, rule in ipairs(rules) do
        if i > h - 10 then break end
        draw.fill(buf, y, x + w, theme.surface)
        local status_col = rule.enabled and theme.success or theme.fg_dark
        draw.put(buf, x + 1, y, rule.enabled and "\7" or "\7", status_col, theme.surface)
        local lbl = (rule.input_display or "?"):sub(1, 16)
        draw.put(buf, x + 3, y, lbl, theme.fg, theme.surface)
        if rule.output ~= "" then
            draw.put(buf, x + 20, y, "-> ", theme.fg_dim, theme.surface)
            draw.put(buf, x + 23, y, (rule.output_display or "?"):sub(1, 12), theme.fg, theme.surface)
        end
        if rule.threshold > 0 then
            local thr = string.format("< %d", rule.threshold)
            draw.put(buf, x + 37, y, thr, theme.warning, theme.surface)
            -- Show current stock of output
            local cur = (st.output_stock or {})[rule.output] or 0
            local met = cur >= rule.threshold
            draw.put(buf, x + 44, y, met and "MET" or "", met and theme.fg_dim or theme.success, theme.surface)
        else
            draw.put(buf, x + 37, y, "always", theme.fg_dim, theme.surface)
        end
        y = y + 1
    end
    y = y + 1

    -- Active Tasks summary
    local tasks = st.get_smelt_tasks and st.get_smelt_tasks() or {}
    local active_tasks = 0
    for _, t in ipairs(tasks) do if t.active then active_tasks = active_tasks + 1 end end

    if y < ctx.content_y + h - 2 then
        draw.fill(buf, y, x + w, theme.surface2)
        draw.put(buf, x + 1, y, string.format("TASKS: %d active", active_tasks), theme.accent, theme.surface2)
        y = y + 1

        for _, task in ipairs(tasks) do
            if not task.active then goto cont_task end
            if y >= ctx.content_y + h - 1 then break end
            draw.fill(buf, y, x + w, theme.surface)
            local lbl = (task.input_display or "?"):sub(1, 18)
            draw.put(buf, x + 1, y, lbl, theme.fg, theme.surface)
            local pct = task.target > 0 and (task.smelted / task.target) or 0
            local bar_w = 12
            local filled = math.floor(pct * bar_w)
            buf.setCursorPos(x + 22, y)
            buf.setBackgroundColor(theme.success)
            buf.write(string.rep(" ", filled))
            buf.setBackgroundColor(theme.border)
            buf.write(string.rep(" ", bar_w - filled))
            draw.put(buf, x + 35, y,
                string.format("%d/%d %d%%", task.smelted, task.target, math.floor(pct * 100)),
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
    local st = ctx.state.storage

    local rules = st.get_smelt_rules and st.get_smelt_rules() or {}

    -- Pending rule banner: user picked input, now needs to pick output
    if pending_rule then
        draw.fill(buf, y, x + w, theme.warning)
        draw.put(buf, x + 1, y, "Input: " .. (pending_rule.input_display or "?"):sub(1, 20), theme.bg, theme.warning)
        draw.button(buf, x + w - 14, y, 13, 1, "PICK OUTPUT", theme.accent, theme.btn_text, true)
        hits.pick_output = {x = w - 14 + 1, y = y - hits.oy + 1, w = 13, h = 1}
        draw.button(buf, x + w - 23, y, 8, 1, "CANCEL", theme.danger, theme.btn_text, true)
        hits.cancel_pending = {x = w - 23 + 1, y = y - hits.oy + 1, w = 8, h = 1}
        y = y + 1
        h = h - 1
    end

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "INPUT", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 19, y, "OUTPUT", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 35, y, "THRS", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 42, y, "ON", theme.fg_dim, theme.surface2)
    y = y + 1

    local area_h = h - 3  -- headers + buttons
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
            local inp = (rule.input_display or "?"):sub(1, 16)
            draw.put(buf, x + 1, y, inp, rfg, rbg)
            if rule.output ~= "" then
                local outp = (rule.output_display or "?"):sub(1, 14)
                draw.put(buf, x + 19, y, outp, rfg, rbg)
            else
                draw.put(buf, x + 19, y, "---", rfg_dim, rbg)
            end
            if rule.threshold > 0 then
                draw.put(buf, x + 35, y, tostring(rule.threshold), rfg, rbg)
            else
                draw.put(buf, x + 35, y, "0", rfg_dim, rbg)
            end
            local on_col = is_sel and theme.bg or (rule.enabled and theme.success or theme.danger)
            draw.put(buf, x + 42, y, rule.enabled and "YES" or "NO", on_col, rbg)

            table.insert(hits.rule_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx,
            })
        end
        y = y + 1
    end

    -- Info line
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
    draw.button(buf, bx, y, 10, 1, "EDIT THR", has_sel and theme.accent or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_edit = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 10, h = 1}
    bx = bx + 11
    draw.button(buf, bx, y, 8, 1, "TOGGLE", has_sel and theme.warning or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_toggle = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 8, h = 1}
    bx = bx + 9
    draw.button(buf, bx, y, 8, 1, "DELETE", has_sel and theme.danger or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.rule_delete = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 8, h = 1}
end

-- ========================================
-- Render: Tasks Tab
-- ========================================
local function render_tasks(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local st = ctx.state.storage
    local utils = ctx.utils

    local tasks = st.get_smelt_tasks and st.get_smelt_tasks() or {}

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "ITEM", theme.fg_dim, theme.surface2)
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
            local lbl = (task.input_display or "?"):sub(1, 17)
            draw.put(buf, x + 1, y, lbl, rfg, rbg)

            local pct = task.target > 0 and (task.smelted / task.target) or 0
            local prog = string.format("%d/%d %d%%", task.smelted, task.target, math.floor(pct * 100))
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
    draw.button(buf, bx, y, 8, 1, "+ NEW", theme.accent, theme.btn_text, true)
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

    -- If item picker is active, render it full-screen
    if picking then
        local purpose = picking == "rule_input" and "Input Item"
            or picking == "rule_output" and "Output Item"
            or "Item to Smelt"
        render_item_picker(ctx, buf, x, y, w, h, purpose)
        return
    end

    -- Header (4 rows)
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.smelting
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data and icon_lib then icon_lib.draw(buf, icon_data, x + 2, y) end

    local sx = x + 11
    draw.put(buf, sx, y, "SMELTING", theme.accent, theme.surface2)

    local st = ctx.state.storage
    local sm = st.get_smelting_stats and st.get_smelting_stats() or {}
    draw.put(buf, sx, y + 1,
        string.format("%d furnaces | Auto-Smelt: %s",
            sm.furnace_count or 0, sm.enabled and "ON" or "OFF"),
        sm.enabled and theme.success or theme.fg_dim, theme.surface2)
    draw.put(buf, sx, y + 2,
        string.format("Fuel: %s  Smeltable: %s",
            utils.format_number(st.cached_fuel_total or 0),
            utils.format_number(st.cached_smeltable_total or 0)),
        theme.fg_dim, theme.surface2)
    local rules = st.get_smelt_rules and st.get_smelt_rules() or {}
    local tasks = st.get_smelt_tasks and st.get_smelt_tasks() or {}
    local active_tasks = 0
    for _, t in ipairs(tasks) do if t.active then active_tasks = active_tasks + 1 end end
    draw.put(buf, sx, y + 3,
        string.format("%d rules | %d tasks", #rules, active_tasks),
        theme.fg_dim, theme.surface2)

    y = y + 4

    -- Tab bar
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"OVERVIEW", "RULES", "TASKS"}
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
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local st = ctx.state.storage
    local draw = ctx.draw
    local utils = ctx.utils

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3], ev[4]

            -- Item picker mode: row click = select, CONFIRM = use
            if picking then
                -- Cancel
                if picker_hits.cancel and draw.hit_test(picker_hits.cancel, tx, ty) then
                    if picking == "rule_output" then
                        pending_rule = nil
                    end
                    picking = nil
                    picker_query = ""
                    picker_scroll = 0
                    picker_selected = nil
                -- Manual ID entry
                elseif picker_hits.manual and draw.hit_test(picker_hits.manual, tx, ty) then
                    local result = utils.pc_input("ITEM ID", "Enter minecraft item ID (e.g. minecraft:cobblestone):")
                    if result and #result > 0 then
                        local name = result
                        local display = utils.clean_name and utils.clean_name(name) or name
                        picker_selected = {name = name, displayName = display}
                    end
                -- Search bar click
                elseif picker_hits.search_bar and draw.hit_test(picker_hits.search_bar, tx, ty) then
                    local result = utils.pc_input("SEARCH ITEMS", "Type item name to filter:")
                    if result then
                        picker_query = result
                    else
                        picker_query = ""
                    end
                    picker_scroll = 0
                    picker_selected = nil
                -- CONFIRM button
                elseif picker_hits.confirm and picker_selected and draw.hit_test(picker_hits.confirm, tx, ty) then
                    local sel = picker_selected
                    if picking == "rule_input" then
                        pending_rule = {input = sel.name, input_display = sel.displayName}
                    elseif picking == "rule_output" then
                        if pending_rule then
                            st.add_smelt_rule(pending_rule.input, sel.name, 0, true,
                                pending_rule.input_display, sel.displayName)
                            pending_rule = nil
                        end
                    elseif picking == "task_input" then
                        local qty_str = utils.pc_input("QUANTITY", "How many to smelt?", "64")
                        local qty = tonumber(qty_str)
                        if qty and qty > 0 then
                            st.add_smelt_task(sel.name, math.floor(qty), sel.displayName)
                        end
                    end
                    picking = nil
                    picker_query = ""
                    picker_scroll = 0
                    picker_selected = nil
                -- Item row click = select (highlight), not confirm
                else
                    for _, row in ipairs(picker_hits.rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            picker_selected = {name = row.name, displayName = row.displayName}
                            break
                        end
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
                    -- Overview: toggle button
                    if hits.toggle and draw.hit_test(hits.toggle, tx, ty) then
                        if st.toggle_smelting then st.toggle_smelting() end
                    end

                elseif tab == 2 then
                    -- Rules tab
                    local handled = false

                    -- Pending rule banner buttons
                    if pending_rule then
                        if hits.pick_output and draw.hit_test(hits.pick_output, tx, ty) then
                            picking = "rule_output"
                            picker_query = ""
                            picker_scroll = 0
                            picker_hits = {}
                            picker_selected = nil
                            handled = true
                        elseif hits.cancel_pending and draw.hit_test(hits.cancel_pending, tx, ty) then
                            pending_rule = nil
                            handled = true
                        end
                    end

                    -- Row selection
                    if not handled then
                        for _, row in ipairs(hits.rule_rows or {}) do
                            if draw.hit_test(row, tx, ty) then
                                sel_rule = row.idx
                                handled = true
                                break
                            end
                        end
                    end

                    -- Add rule
                    if not handled and hits.rule_add and draw.hit_test(hits.rule_add, tx, ty) then
                        picking = "rule_input"
                        pending_rule = nil
                        picker_query = ""
                        picker_scroll = 0
                        picker_hits = {}
                        picker_selected = nil
                        handled = true
                    end

                    -- Edit threshold
                    if not handled and hits.rule_edit and draw.hit_test(hits.rule_edit, tx, ty) then
                        local rules = st.get_smelt_rules and st.get_smelt_rules() or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            local current = tostring(rules[sel_rule].threshold or 0)
                            local result = utils.pc_input("THRESHOLD", "Min output stock (0=always):", current)
                            if result then
                                local thr = tonumber(result) or 0
                                if thr < 0 then thr = 0 end
                                st.update_smelt_rule(sel_rule, "threshold", thr)
                            end
                        end
                        handled = true
                    end

                    -- Toggle rule
                    if not handled and hits.rule_toggle and draw.hit_test(hits.rule_toggle, tx, ty) then
                        local rules = st.get_smelt_rules and st.get_smelt_rules() or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            st.update_smelt_rule(sel_rule, "enabled", not rules[sel_rule].enabled)
                        end
                        handled = true
                    end

                    -- Delete rule
                    if not handled and hits.rule_delete and draw.hit_test(hits.rule_delete, tx, ty) then
                        local rules = st.get_smelt_rules and st.get_smelt_rules() or {}
                        if sel_rule >= 1 and sel_rule <= #rules then
                            st.remove_smelt_rule(sel_rule)
                            if sel_rule > #rules - 1 and sel_rule > 1 then
                                sel_rule = sel_rule - 1
                            end
                        end
                        handled = true
                    end

                elseif tab == 3 then
                    -- Tasks tab
                    local handled = false

                    -- Row selection
                    for _, row in ipairs(hits.task_rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            sel_task = row.idx
                            handled = true
                            break
                        end
                    end

                    -- New task
                    if not handled and hits.task_new and draw.hit_test(hits.task_new, tx, ty) then
                        picking = "task_input"
                        picker_query = ""
                        picker_scroll = 0
                        picker_hits = {}
                        picker_selected = nil
                        handled = true
                    end

                    -- Cancel task
                    if not handled and hits.task_cancel and draw.hit_test(hits.task_cancel, tx, ty) then
                        local tasks = st.get_smelt_tasks and st.get_smelt_tasks() or {}
                        if sel_task >= 1 and sel_task <= #tasks and tasks[sel_task].active then
                            st.cancel_smelt_task(sel_task)
                        end
                        handled = true
                    end

                    -- Clear done
                    if not handled and hits.task_clear and draw.hit_test(hits.task_clear, tx, ty) then
                        if st.clear_completed_tasks then
                            st.clear_completed_tasks()
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
            elseif tab == 2 then
                scroll = math.max(0, math.min(hits.max_scroll or 0, scroll + dir))
            elseif tab == 3 then
                scroll = math.max(0, math.min(hits.task_max_scroll or 0, scroll + dir))
            end

        elseif ev[1] == "key" then
            if picking then
                -- no key handling in picker
            elseif ev[2] == keys.tab then
                tab = (tab % TAB_COUNT) + 1
                scroll = 0
            elseif tab == 2 then
                local rules = st.get_smelt_rules and st.get_smelt_rules() or {}
                if ev[2] == keys.up and sel_rule > 1 then
                    sel_rule = sel_rule - 1
                elseif ev[2] == keys.down and sel_rule < #rules then
                    sel_rule = sel_rule + 1
                end
            elseif tab == 3 then
                local tasks = st.get_smelt_tasks and st.get_smelt_tasks() or {}
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
