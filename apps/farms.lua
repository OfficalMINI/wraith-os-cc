-- =============================================
-- WRAITH OS - FARMS APP
-- =============================================
-- Configure automated farms: assign input/output chests,
-- supply rules with thresholds, and monitor harvest stats.

local app = {
    id = "farms",
    name = "Farms",
    icon = "farms",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1       -- 1=Overview, 2=Setup
local TAB_COUNT = 2
local scroll = 0
local sel_farm = 1
local sel_rule = 1
local hits = {}

-- Item picker state
local picking = nil         -- nil | "supply_item"
local picker_query = ""
local picker_scroll = 0
local picker_hits = {}
local picker_selected = nil

-- Chest picker state
local chest_picking = nil   -- nil | "input" | "output"
local picker_cooldown_until = 0
local delete_cooldown_until = 0

-- Turtle picker state
local turtle_picking = false

-- ========================================
-- Render: Item Picker overlay
-- ========================================
local function render_item_picker(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local st = ctx.state.storage

    picker_hits = {}

    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Pick Supply Item", theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    picker_hits.cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

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
-- Render: Chest Picker overlay
-- ========================================
local function render_chest_picker(ctx, buf, x, y, w, h, purpose)
    local draw = ctx.draw
    local theme = ctx.theme
    local fm = ctx.state.farms

    picker_hits = {}

    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Pick " .. purpose .. " Chest", theme.bg, theme.accent)

    -- Scroll buttons + cancel
    local on_cooldown = os.clock() < picker_cooldown_until
    local can_up = picker_scroll > 0 and not on_cooldown
    local can_dn = not on_cooldown
    draw.button(buf, x + w - 18, y, 3, 1, "\24",
        can_up and theme.surface2 or theme.surface, can_up and theme.fg or theme.fg_dim, can_up)
    picker_hits.scroll_up = {x = w - 18 + 1, y = y - hits.oy + 1, w = 3, h = 1}

    draw.button(buf, x + w - 14, y, 3, 1, "\25",
        can_dn and theme.surface2 or theme.surface, can_dn and theme.fg or theme.fg_dim, can_dn)
    picker_hits.scroll_dn = {x = w - 14 + 1, y = y - hits.oy + 1, w = 3, h = 1}

    draw.button(buf, x + w - 11, y, 3, 1, "END",
        can_dn and theme.surface2 or theme.surface, can_dn and theme.fg or theme.fg_dim, can_dn)
    picker_hits.scroll_end = {x = w - 11 + 1, y = y - hits.oy + 1, w = 3, h = 1}

    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    picker_hits.cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    local available = fm.list_available_chests and fm.list_available_chests() or {}
    local area_h = h - 2
    local max_scroll = math.max(0, #available - area_h)
    if picker_scroll > max_scroll then picker_scroll = max_scroll end
    picker_hits.max_scroll = max_scroll
    picker_hits.rows = {}

    if #available == 0 then
        draw.fillR(buf, y, y + area_h - 1, x + w, theme.surface)
        draw.center(buf, "No chests found on network", y + math.floor(area_h / 2), x + w, theme.fg_dim, theme.surface)
    else
        for vi = 1, area_h do
            local idx = picker_scroll + vi
            local chest = idx <= #available and available[idx] or nil
            local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, rbg)
            if chest then
                draw.put(buf, x + 1, y, chest.name, theme.fg, rbg)
                -- Show role tag if assigned elsewhere
                local tag = chest.role or chest.type
                draw.put(buf, x + w - #tag - 1, y, tag, theme.fg_dim, rbg)
                table.insert(picker_hits.rows, {
                    x = 1, y = y - hits.oy + 1, w = w, h = 1,
                    name = chest.name,
                })
            end
            y = y + 1
        end
    end
end

-- ========================================
-- Render: Turtle Picker overlay
-- ========================================
local function render_turtle_picker(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local fm = ctx.state.farms

    picker_hits = {}

    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Pick Tree Turtle", theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    picker_hits.cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Collect available tree clients (all are available — multiple farms can share turtles,
    -- but we show which farm(s) each turtle is already linked to)
    local turtle_farms = {}  -- {[id] = farm_name}
    for _, plot in ipairs(fm.plots or {}) do
        if plot.type == "tree" then
            for _, tid in ipairs(plot.tree_client_ids or {}) do
                turtle_farms[tid] = plot.name
            end
        end
    end

    local clients = {}
    for id, c in pairs(fm.tree_clients or {}) do
        local entry = {id = c.id, label = c.label, state = c.state, linked_to = turtle_farms[id]}
        table.insert(clients, entry)
    end
    table.sort(clients, function(a, b) return (a.label or "") < (b.label or "") end)

    local area_h = h - 2
    picker_hits.rows = {}

    if #clients == 0 then
        draw.fillR(buf, y, y + area_h - 1, x + w, theme.surface)
        draw.center(buf, "No tree turtles found", y + math.floor(area_h / 2), x + w, theme.fg_dim, theme.surface)
    else
        for vi = 1, area_h do
            local idx = vi
            local client = idx <= #clients and clients[idx] or nil
            local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, rbg)
            if client then
                local lbl = (client.label or "Tree " .. client.id):sub(1, 24)
                draw.put(buf, x + 1, y, lbl, theme.fg, rbg)
                local st_str = client.state or "?"
                local st_col = theme.fg_dim
                if st_str == "farming" then st_col = theme.success
                elseif st_str == "offline" then st_col = theme.danger
                elseif st_str == "idle" then st_col = theme.warning
                end
                draw.put(buf, x + 26, y, st_str, st_col, rbg)
                -- Show which farm this turtle is already linked to (if any)
                if client.linked_to then
                    local link_str = "\16" .. client.linked_to:sub(1, 8)
                    draw.put(buf, x + 35, y, link_str, theme.fg_dim, rbg)
                end
                local id_str = "#" .. client.id
                draw.put(buf, x + w - #id_str - 1, y, id_str, theme.fg_dim, rbg)
                table.insert(picker_hits.rows, {
                    x = 1, y = y - hits.oy + 1, w = w, h = 1,
                    id = client.id,
                })
            end
            y = y + 1
        end
    end
end

-- ========================================
-- Render: Overview Tab
-- ========================================
local function render_overview(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local fm = ctx.state.farms
    local plots = fm.plots or {}

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "FARM", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 22, y, "IN", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 27, y, "OUT", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 32, y, "STATUS", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 46, y, "ON", theme.fg_dim, theme.surface2)
    y = y + 1

    local area_h = h - 3
    local max_scroll = math.max(0, #plots - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.farm_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local is_sel = (idx == sel_farm)
        local rbg = is_sel and theme.accent or ((vi % 2 == 0) and theme.surface2 or theme.surface)
        local rfg = is_sel and theme.bg or theme.fg
        local rfg_dim = is_sel and theme.bg or theme.fg_dim
        draw.fill(buf, y, x + w, rbg)
        if idx <= #plots then
            local plot = plots[idx]
            local is_tree = plot.type == "tree"
            local name = (plot.name or "?"):sub(1, 16)
            draw.put(buf, x + 1, y, name, rfg, rbg)

            -- Type badge
            local type_lbl = is_tree and "TRE" or "CUS"
            local type_col = is_sel and theme.bg or (is_tree and theme.accent2 or theme.fg_dim)
            draw.put(buf, x + 18, y, type_lbl, type_col, rbg)

            if is_tree then
                -- Tree: show aggregate turtle status
                local ids = plot.tree_client_ids or {}
                local ts, ts_col
                if #ids == 0 then
                    ts = "unlinked"
                    ts_col = is_sel and theme.bg or theme.fg_dim
                else
                    local online, total = 0, #ids
                    local total_rounds = 0
                    for _, tid in ipairs(ids) do
                        local c = (fm.tree_clients or {})[tid]
                        if c and c.state ~= "offline" then
                            online = online + 1
                            total_rounds = total_rounds + (c.rounds or 0)
                        end
                    end
                    if online > 0 then
                        ts = online .. "/" .. total .. " on"
                        ts_col = is_sel and theme.bg or theme.success
                        if total_rounds > 0 then ts = ts .. " R:" .. total_rounds end
                        -- Show average progress of farming turtles
                        local prog_sum, prog_n = 0, 0
                        for _, tid2 in ipairs(ids) do
                            local c2 = (fm.tree_clients or {})[tid2]
                            if c2 and c2.state == "farming" and c2.progress then
                                prog_sum = prog_sum + c2.progress
                                prog_n = prog_n + 1
                            end
                        end
                        if prog_n > 0 then
                            ts = ts .. " " .. math.floor(prog_sum / prog_n) .. "%"
                        end
                    else
                        ts = "0/" .. total .. " offline"
                        ts_col = is_sel and theme.bg or theme.danger
                    end
                end
                draw.put(buf, x + 22, y, ts:sub(1, 22), ts_col, rbg)
            else
                -- Custom: IN/OUT dots + status
                local in_set = plot.input and plot.input ~= ""
                if in_set then
                    local in_ok = peripheral.isPresent(plot.input)
                    draw.put(buf, x + 22, y, "\7", is_sel and theme.bg or (in_ok and theme.success or theme.danger), rbg)
                else
                    draw.put(buf, x + 22, y, "-", is_sel and theme.bg or theme.fg_dim, rbg)
                end

                local out_set = plot.output and plot.output ~= ""
                if out_set then
                    local out_ok = peripheral.isPresent(plot.output)
                    draw.put(buf, x + 27, y, "\7", is_sel and theme.bg or (out_ok and theme.success or theme.danger), rbg)
                else
                    draw.put(buf, x + 27, y, "-", is_sel and theme.bg or theme.fg_dim, rbg)
                end

                local ds = plot.delivery_status or "..."
                local ds_col = theme.fg_dim
                if not is_sel then
                    if ds == "sending" or ds == "partial" then ds_col = theme.accent
                    elseif ds == "targets met" or ds == "idle" then ds_col = theme.success
                    elseif ds == "blocked" or ds == "input offline" or ds == "read error" then ds_col = theme.danger
                    elseif ds == "no input" or ds == "no rules" or ds == "disabled" then ds_col = theme.fg_dim
                    end
                else
                    ds_col = theme.bg
                end
                draw.put(buf, x + 32, y, ds:sub(1, 12), ds_col, rbg)
            end

            -- Enabled
            local on_col = is_sel and theme.bg or (plot.enabled and theme.success or theme.danger)
            draw.put(buf, x + 46, y, plot.enabled and "YES" or "NO", on_col, rbg)

            table.insert(hits.farm_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx,
            })
        end
        y = y + 1
    end

    -- Info line
    draw.fill(buf, y, x + w, theme.surface2)
    draw.center(buf, string.format("%d farms", #plots), y, x + w, theme.fg_dim, theme.surface2)
    y = y + 1

    -- Buttons
    draw.fill(buf, y, x + w, theme.surface)
    local bx = x + 1
    draw.button(buf, bx, y, 10, 1, "+ NEW", theme.accent, theme.btn_text, true)
    hits.farm_new = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 10, h = 1}
    bx = bx + 11
    local has_sel = sel_farm >= 1 and sel_farm <= #plots
    draw.button(buf, bx, y, 10, 1, "TOGGLE", has_sel and theme.warning or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.farm_toggle = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 10, h = 1}
    bx = bx + 11
    draw.button(buf, bx, y, 10, 1, "DELETE", has_sel and theme.danger or theme.surface2,
        has_sel and theme.btn_text or theme.fg_dim, has_sel)
    hits.farm_delete = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 10, h = 1}
end

-- ========================================
-- Render: Setup Tab (selected farm detail)
-- ========================================
local function render_setup(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local fm = ctx.state.farms
    local plots = fm.plots or {}

    if sel_farm < 1 or sel_farm > #plots then
        draw.fillR(buf, y, y + h - 1, x + w, theme.surface)
        draw.center(buf, "Select a farm in Overview first", y + math.floor(h / 2), x + w, theme.fg_dim, theme.surface)
        return
    end

    local plot = plots[sel_farm]

    -- Farm name row
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "Name:", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 7, y, (plot.name or "?"):sub(1, 25), theme.fg, theme.surface2)
    draw.button(buf, x + w - 8, y, 7, 1, "RENAME", theme.accent, theme.btn_text, true)
    hits.rename_btn = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    -- Type toggle row
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "Type:", theme.fg_dim, theme.surface2)
    local is_tree = plot.type == "tree"
    local cus_bg = (not is_tree) and theme.accent or theme.surface
    local cus_fg = (not is_tree) and theme.bg or theme.fg_dim
    local tre_bg = is_tree and theme.accent2 or theme.surface
    local tre_fg = is_tree and theme.bg or theme.fg_dim
    draw.button(buf, x + 7, y, 8, 1, "CUSTOM", cus_bg, cus_fg, true)
    hits.type_custom = {x = 7 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    draw.button(buf, x + 16, y, 6, 1, "TREE", tre_bg, tre_fg, true)
    hits.type_tree = {x = 16 + 1, y = y - hits.oy + 1, w = 6, h = 1}
    y = y + 1

    if is_tree then
        -- ---- Tree farm setup UI ----
        local ids = plot.tree_client_ids or {}

        -- Turtles header + add button
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "Turtles: " .. #ids, theme.fg_dim, theme.surface)
        draw.button(buf, x + w - 8, y, 7, 1, "+ ADD", theme.accent, theme.btn_text, true)
        hits.tree_pick = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
        y = y + 1

        -- Column headers for turtle list
        draw.fill(buf, y, x + w, theme.surface2)
        draw.put(buf, x + 1, y, "TURTLE", theme.fg_dim, theme.surface2)
        draw.put(buf, x + 15, y, "STATE", theme.fg_dim, theme.surface2)
        draw.put(buf, x + 24, y, "RND", theme.fg_dim, theme.surface2)
        draw.put(buf, x + 28, y, "FUEL", theme.fg_dim, theme.surface2)
        draw.put(buf, x + 33, y, "SAP", theme.fg_dim, theme.surface2)
        draw.put(buf, x + 37, y, "PROG", theme.fg_dim, theme.surface2)
        draw.put(buf, x + 42, y, "SEEN", theme.fg_dim, theme.surface2)
        y = y + 1

        -- List each linked turtle with status
        hits.tree_unlink_rows = {}
        for ti, tid in ipairs(ids) do
            local tc = (fm.tree_clients or {})[tid]
            local rbg = (ti % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, rbg)
            local tl = tc and tc.label or ("ID " .. tid)
            local ts, ts_col = "en route", theme.warning
            if tc then
                ts = tc.state or "unknown"
                if ts == "farming" then ts_col = theme.success
                elseif ts == "idle" then ts_col = theme.warning
                elseif ts == "offline" then
                    ts = "offline"
                    ts_col = theme.danger
                elseif ts == "stuck" then ts_col = theme.danger
                end
            end
            draw.put(buf, x + 1, y, tl:sub(1, 13), theme.fg, rbg)
            draw.put(buf, x + 15, y, ts:sub(1, 8), ts_col, rbg)
            -- Rounds
            if tc and tc.rounds then
                draw.put(buf, x + 24, y, tostring(tc.rounds), theme.fg_dim, rbg)
            end
            -- Fuel mini-display
            if tc and tc.fuel then
                local fp = tc.fuel_limit and tc.fuel_limit > 0
                    and math.floor(tc.fuel / tc.fuel_limit * 100) or 0
                local fc = fp < 10 and theme.danger or (fp < 25 and theme.warning or theme.success)
                draw.put(buf, x + 28, y, fp .. "%", fc, rbg)
            end
            -- Saplings
            if tc and tc.saplings then
                draw.put(buf, x + 33, y, tostring(tc.saplings), theme.fg_dim, rbg)
            end
            -- Round progress
            if tc and tc.progress and tc.state == "farming" then
                local pc = tc.progress
                local pc_col = pc < 33 and theme.fg_dim or (pc < 66 and theme.warning or theme.success)
                draw.put(buf, x + 37, y, pc .. "%", pc_col, rbg)
            end
            -- Last seen
            if tc and tc.last_seen then
                local ago = math.floor(os.clock() - tc.last_seen)
                local seen_str, seen_col
                if tc.last_seen == 0 then
                    seen_str = "never"
                    seen_col = theme.fg_dim
                elseif ago < 60 then
                    seen_str = ago .. "s"
                    seen_col = ago < 15 and theme.success or theme.warning
                elseif ago < 3600 then
                    seen_str = math.floor(ago / 60) .. "m"
                    seen_col = theme.danger
                else
                    seen_str = math.floor(ago / 3600) .. "h"
                    seen_col = theme.danger
                end
                draw.put(buf, x + 42, y, seen_str, seen_col, rbg)
            end
            -- Unlink button per turtle
            draw.button(buf, x + w - 4, y, 3, 1, "X", theme.danger, theme.btn_text, true)
            table.insert(hits.tree_unlink_rows, {
                x = w - 4 + 1, y = y - hits.oy + 1, w = 3, h = 1,
                turtle_id = tid,
            })
            y = y + 1
        end

        if #ids == 0 then
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 1, y, "No turtles linked", theme.fg_dim, theme.surface)
            y = y + 1
        end

        draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
        y = y + 1

        -- START ALL / STOP ALL buttons
        draw.fill(buf, y, x + w, theme.surface)
        local any_online = false
        for _, tid in ipairs(ids) do
            local c = (fm.tree_clients or {})[tid]
            if c and c.state ~= "offline" then any_online = true; break end
        end
        local bx = x + 1
        draw.button(buf, bx, y, 11, 1, "START ALL", any_online and theme.success or theme.surface2,
            any_online and theme.btn_text or theme.fg_dim, any_online)
        hits.tree_start = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 11, h = 1}
        bx = bx + 12
        draw.button(buf, bx, y, 10, 1, "STOP ALL", any_online and theme.warning or theme.surface2,
            any_online and theme.btn_text or theme.fg_dim, any_online)
        hits.tree_stop = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 10, h = 1}
        y = y + 1

        -- Output chest row (turtle drops here, Wraith harvests into storage)
        draw.fill(buf, y, x + w, theme.surface2)
        draw.put(buf, x + 1, y, "Output:", theme.fg_dim, theme.surface2)
        local out_set = plot.output and plot.output ~= ""
        local out_name = out_set and plot.output or "(not set)"
        local out_ok = out_set and peripheral.isPresent(plot.output)
        draw.put(buf, x + 9, y, out_name:sub(1, 23), out_set and (out_ok and theme.success or theme.danger) or theme.fg_dim, theme.surface2)
        if out_set then
            draw.button(buf, x + w - 16, y, 7, 1, "CLEAR", theme.danger, theme.btn_text, true)
            hits.clear_output = {x = w - 16 + 1, y = y - hits.oy + 1, w = 7, h = 1}
        end
        draw.button(buf, x + w - 8, y, 7, 1, "SET", theme.accent, theme.btn_text, true)
        hits.set_output = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    else

    -- Input chest row
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "Input:", theme.fg_dim, theme.surface)
    local in_set = plot.input and plot.input ~= ""
    local in_name = in_set and plot.input or "(optional)"
    local in_ok = in_set and peripheral.isPresent(plot.input)
    draw.put(buf, x + 8, y, in_name:sub(1, 24), in_set and (in_ok and theme.success or theme.danger) or theme.fg_dim, theme.surface)
    if in_set then
        draw.button(buf, x + w - 16, y, 7, 1, "CLEAR", theme.danger, theme.btn_text, true)
        hits.clear_input = {x = w - 16 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    end
    draw.button(buf, x + w - 8, y, 7, 1, "SET", theme.accent, theme.btn_text, true)
    hits.set_input = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    -- Output chest row
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "Output:", theme.fg_dim, theme.surface)
    local out_set = plot.output and plot.output ~= ""
    local out_name = out_set and plot.output or "(optional)"
    local out_ok = out_set and peripheral.isPresent(plot.output)
    draw.put(buf, x + 9, y, out_name:sub(1, 23), out_set and (out_ok and theme.success or theme.danger) or theme.fg_dim, theme.surface)
    if out_set then
        draw.button(buf, x + w - 16, y, 7, 1, "CLEAR", theme.danger, theme.btn_text, true)
        hits.clear_output = {x = w - 16 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    end
    draw.button(buf, x + w - 8, y, 7, 1, "SET", theme.accent, theme.btn_text, true)
    hits.set_output = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    -- Stats & status row
    draw.fill(buf, y, x + w, theme.surface2)
    local supplied = plot.stats and plot.stats.items_supplied or 0
    local harvested = plot.stats and plot.stats.items_harvested or 0
    draw.put(buf, x + 1, y, string.format("S:%s H:%s",
        utils.format_number(supplied), utils.format_number(harvested)),
        theme.fg_dim, theme.surface2)
    -- Show live delivery/harvest status
    local ds = plot.delivery_status
    local hs = plot.harvest_status
    local status_parts = {}
    if ds and ds ~= "idle" then table.insert(status_parts, ds) end
    if hs and hs ~= "empty" then table.insert(status_parts, hs) end
    if #status_parts > 0 then
        local status_str = table.concat(status_parts, " | ")
        local sc = theme.fg_dim
        if ds == "sending" or ds == "partial" then sc = theme.accent
        elseif ds == "blocked" or ds == "input offline" then sc = theme.danger
        elseif ds == "targets met" then sc = theme.success
        end
        draw.put(buf, x + 20, y, status_str:sub(1, w - 21), sc, theme.surface2)
    end
    y = y + 1

    -- Separator
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Supply rules header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "SUPPLY RULES", theme.accent, theme.surface2)
    draw.put(buf, x + 18, y, "TGT", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 24, y, "THR", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 30, y, "STATUS", theme.fg_dim, theme.surface2)
    y = y + 1

    local supplies = plot.supplies or {}
    local area_h = h - 9  -- header rows taken above (incl type toggle)
    local max_scroll = math.max(0, #supplies - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.supply_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local is_sel = (idx == sel_rule)
        local rbg = is_sel and theme.accent or ((vi % 2 == 0) and theme.surface2 or theme.surface)
        local rfg = is_sel and theme.bg or theme.fg
        local rfg_dim = is_sel and theme.bg or theme.fg_dim
        draw.fill(buf, y, x + w, rbg)
        if idx <= #supplies then
            local rule = supplies[idx]
            local dn = (rule.display or rule.item or "?"):sub(1, 15)
            draw.put(buf, x + 1, y, dn, rfg, rbg)
            draw.put(buf, x + 18, y, tostring(rule.target or 0), rfg, rbg)
            local thr = rule.threshold or 0
            draw.put(buf, x + 24, y, thr > 0 and tostring(thr) or "-", rfg_dim, rbg)

            -- Per-rule delivery status
            local rs = rule.status or "..."
            local rs_col = rfg_dim
            if not is_sel then
                if rs:find("sent") then rs_col = theme.accent
                elseif rs == "target met" then rs_col = theme.success
                elseif rs:find("low") or rs == "not in storage" or rs == "transfer failed" then rs_col = theme.danger
                elseif rs == "chest offline" or rs == "read error" then rs_col = theme.danger
                end
            else
                rs_col = theme.bg
            end
            draw.put(buf, x + 30, y, rs:sub(1, w - 31), rs_col, rbg)

            table.insert(hits.supply_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx,
            })
        end
        y = y + 1
    end

    -- Bottom buttons
    draw.fill(buf, y, x + w, theme.surface)
    local bx = x + 1
    draw.button(buf, bx, y, 9, 1, "+ ADD", theme.accent, theme.btn_text, true)
    hits.supply_add = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 9, h = 1}
    bx = bx + 10
    local has_rule = sel_rule >= 1 and sel_rule <= #supplies
    draw.button(buf, bx, y, 8, 1, "EDIT", has_rule and theme.accent or theme.surface2,
        has_rule and theme.btn_text or theme.fg_dim, has_rule)
    hits.supply_edit = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 8, h = 1}
    bx = bx + 9
    draw.button(buf, bx, y, 8, 1, "DELETE", has_rule and theme.danger or theme.surface2,
        has_rule and theme.btn_text or theme.fg_dim, has_rule)
    hits.supply_delete = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = 8, h = 1}

    end -- if is_tree else custom
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
        render_item_picker(ctx, buf, x, y, w, h)
        return
    end

    -- Turtle picker overlay
    if turtle_picking then
        render_turtle_picker(ctx, buf, x, y, w, h)
        return
    end

    -- Chest picker overlay
    if chest_picking then
        local purpose = chest_picking == "input" and "Input" or "Output"
        render_chest_picker(ctx, buf, x, y, w, h, purpose)
        return
    end

    -- Header (4 rows)
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.farms
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data and icon_lib then icon_lib.draw(buf, icon_data, x + 2, y) end

    local sx = x + 11
    draw.put(buf, sx, y, "FARMS", theme.accent, theme.surface2)

    local fm = ctx.state.farms
    local plots = fm.plots or {}
    local enabled_count = 0
    local total_harvested = 0
    local total_supplied = 0
    for _, p in ipairs(plots) do
        if p.enabled then enabled_count = enabled_count + 1 end
        if p.stats then
            total_harvested = total_harvested + (p.stats.items_harvested or 0)
            total_supplied = total_supplied + (p.stats.items_supplied or 0)
        end
    end
    draw.put(buf, sx, y + 1,
        string.format("%d farms | %d active", #plots, enabled_count),
        enabled_count > 0 and theme.success or theme.fg_dim, theme.surface2)
    draw.put(buf, sx, y + 2,
        string.format("Supplied: %s  Harvested: %s",
            utils.format_number(total_supplied), utils.format_number(total_harvested)),
        theme.fg_dim, theme.surface2)

    -- Selected farm preview
    if sel_farm >= 1 and sel_farm <= #plots then
        local p = plots[sel_farm]
        local rules_str = string.format("%d supply rules", #(p.supplies or {}))
        draw.put(buf, sx, y + 3, (p.name or "?"):sub(1, 18) .. "  " .. rules_str, theme.fg_dim, theme.surface2)
    end

    y = y + 4

    -- Tab bar
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"OVERVIEW", "SETUP"}
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
        render_setup(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local fm = ctx.state.farms
    local st = ctx.state.storage
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
                    local result = utils.pc_input("ITEM ID", "Enter minecraft item ID:")
                    if result and #result > 0 then
                        picker_selected = {name = result, displayName = utils.clean_name and utils.clean_name(result) or result}
                    end
                elseif picker_hits.search_bar and draw.hit_test(picker_hits.search_bar, tx, ty) then
                    local result = utils.pc_input("SEARCH ITEMS", "Type item name to filter:")
                    if result then picker_query = result else picker_query = "" end
                    picker_scroll = 0
                    picker_selected = nil
                elseif picker_hits.confirm and picker_selected and draw.hit_test(picker_hits.confirm, tx, ty) then
                    local sel = picker_selected
                    local target_str = utils.pc_input("TARGET QTY", "How many to keep in input chest?", "64")
                    local target = tonumber(target_str)
                    if target and target > 0 then
                        local thr_str = utils.pc_input("THRESHOLD", "Min in storage before sending (0=always):", "0")
                        local threshold = tonumber(thr_str) or 0
                        fm.add_supply(sel_farm, sel.name, sel.displayName, math.floor(target), math.floor(threshold))
                    end
                    picking = nil
                    picker_query = ""
                    picker_scroll = 0
                    picker_selected = nil
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

            -- Chest picker mode
            if chest_picking then
                if picker_hits.cancel and draw.hit_test(picker_hits.cancel, tx, ty) then
                    chest_picking = nil
                    picker_scroll = 0
                elseif picker_hits.scroll_up and draw.hit_test(picker_hits.scroll_up, tx, ty) then
                    if os.clock() >= picker_cooldown_until then
                        picker_scroll = math.max(0, picker_scroll - 5)
                        picker_cooldown_until = os.clock() + 0.5
                    end
                elseif picker_hits.scroll_dn and draw.hit_test(picker_hits.scroll_dn, tx, ty) then
                    if os.clock() >= picker_cooldown_until then
                        picker_scroll = math.min(picker_hits.max_scroll or 0, picker_scroll + 5)
                        picker_cooldown_until = os.clock() + 0.5
                    end
                elseif picker_hits.scroll_end and draw.hit_test(picker_hits.scroll_end, tx, ty) then
                    if os.clock() >= picker_cooldown_until then
                        picker_scroll = picker_hits.max_scroll or 0
                        picker_cooldown_until = os.clock() + 0.5
                    end
                else
                    for _, row in ipairs(picker_hits.rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            if fm.update_farm then
                                fm.update_farm(sel_farm, chest_picking, row.name)
                            end
                            chest_picking = nil
                            picker_scroll = 0
                            break
                        end
                    end
                end
                goto done
            end

            -- Turtle picker mode
            if turtle_picking then
                if picker_hits.cancel and draw.hit_test(picker_hits.cancel, tx, ty) then
                    turtle_picking = false
                else
                    for _, row in ipairs(picker_hits.rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            if fm.link_tree_turtle then
                                fm.link_tree_turtle(sel_farm, row.id)
                            end
                            turtle_picking = false
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
                    -- Overview tab
                    local handled = false

                    -- Row selection
                    for _, row in ipairs(hits.farm_rows or {}) do
                        if draw.hit_test(row, tx, ty) then
                            sel_farm = row.idx
                            handled = true
                            break
                        end
                    end

                    -- New farm
                    if not handled and hits.farm_new and draw.hit_test(hits.farm_new, tx, ty) then
                        local name = utils.pc_input("FARM NAME", "Enter a name for the new farm:")
                        if name and #name > 0 then
                            fm.add_farm(name)
                            sel_farm = #(fm.plots or {})
                        end
                        handled = true
                    end

                    -- Toggle
                    if not handled and hits.farm_toggle and draw.hit_test(hits.farm_toggle, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            fm.toggle_farm(sel_farm)
                        end
                        handled = true
                    end

                    -- Delete (with cooldown to prevent accidental double-delete)
                    if not handled and hits.farm_delete and draw.hit_test(hits.farm_delete, tx, ty) then
                        if os.clock() >= delete_cooldown_until then
                            local plots = fm.plots or {}
                            if sel_farm >= 1 and sel_farm <= #plots then
                                fm.remove_farm(sel_farm)
                                if sel_farm > #(fm.plots or {}) and sel_farm > 1 then
                                    sel_farm = sel_farm - 1
                                end
                                delete_cooldown_until = os.clock() + 1
                            end
                        end
                        handled = true
                    end

                elseif tab == 2 then
                    -- Setup tab
                    local handled = false

                    -- Rename
                    if hits.rename_btn and draw.hit_test(hits.rename_btn, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            local current = plots[sel_farm].name or ""
                            local result = utils.pc_input("RENAME FARM", "New name:", current)
                            if result and #result > 0 then
                                fm.update_farm(sel_farm, "name", result)
                            end
                        end
                        handled = true
                    end

                    -- Type toggle
                    if not handled and hits.type_custom and draw.hit_test(hits.type_custom, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            fm.update_farm(sel_farm, "type", "custom")
                        end
                        handled = true
                    end
                    if not handled and hits.type_tree and draw.hit_test(hits.type_tree, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            fm.update_farm(sel_farm, "type", "tree")
                        end
                        handled = true
                    end

                    -- Tree-specific buttons
                    if not handled and hits.tree_pick and draw.hit_test(hits.tree_pick, tx, ty) then
                        turtle_picking = true
                        picker_hits = {}
                        handled = true
                    end
                    if not handled then
                        for _, row in ipairs(hits.tree_unlink_rows or {}) do
                            if draw.hit_test(row, tx, ty) then
                                if fm.unlink_tree_turtle then
                                    fm.unlink_tree_turtle(sel_farm, row.turtle_id)
                                end
                                handled = true
                                break
                            end
                        end
                    end
                    if not handled and hits.tree_start and draw.hit_test(hits.tree_start, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            local ids = plots[sel_farm].tree_client_ids or {}
                            for _, cid in ipairs(ids) do
                                if fm.send_tree_command then
                                    fm.send_tree_command(cid, {action = "start"})
                                end
                            end
                        end
                        handled = true
                    end
                    if not handled and hits.tree_stop and draw.hit_test(hits.tree_stop, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            local ids = plots[sel_farm].tree_client_ids or {}
                            for _, cid in ipairs(ids) do
                                if fm.send_tree_command then
                                    fm.send_tree_command(cid, {action = "stop"})
                                end
                            end
                        end
                        handled = true
                    end
                    -- Set input chest
                    if not handled and hits.set_input and draw.hit_test(hits.set_input, tx, ty) then
                        chest_picking = "input"
                        picker_scroll = 0
                        handled = true
                    end

                    -- Clear input chest
                    if not handled and hits.clear_input and draw.hit_test(hits.clear_input, tx, ty) then
                        fm.update_farm(sel_farm, "input", "")
                        handled = true
                    end

                    -- Set output chest
                    if not handled and hits.set_output and draw.hit_test(hits.set_output, tx, ty) then
                        chest_picking = "output"
                        picker_scroll = 0
                        handled = true
                    end

                    -- Clear output chest
                    if not handled and hits.clear_output and draw.hit_test(hits.clear_output, tx, ty) then
                        fm.update_farm(sel_farm, "output", "")
                        handled = true
                    end

                    -- Supply row selection
                    if not handled then
                        for _, row in ipairs(hits.supply_rows or {}) do
                            if draw.hit_test(row, tx, ty) then
                                sel_rule = row.idx
                                handled = true
                                break
                            end
                        end
                    end

                    -- Add supply
                    if not handled and hits.supply_add and draw.hit_test(hits.supply_add, tx, ty) then
                        picking = "supply_item"
                        picker_query = ""
                        picker_scroll = 0
                        picker_hits = {}
                        picker_selected = nil
                        handled = true
                    end

                    -- Edit supply
                    if not handled and hits.supply_edit and draw.hit_test(hits.supply_edit, tx, ty) then
                        local plots = fm.plots or {}
                        if sel_farm >= 1 and sel_farm <= #plots then
                            local supplies = plots[sel_farm].supplies or {}
                            if sel_rule >= 1 and sel_rule <= #supplies then
                                local rule = supplies[sel_rule]
                                local t_str = utils.pc_input("TARGET", "Target qty in input chest:", tostring(rule.target or 64))
                                local t = tonumber(t_str)
                                if t and t > 0 then
                                    fm.update_supply(sel_farm, sel_rule, "target", math.floor(t))
                                end
                                local thr_str = utils.pc_input("THRESHOLD", "Min in storage (0=always):", tostring(rule.threshold or 0))
                                local thr = tonumber(thr_str)
                                if thr then
                                    fm.update_supply(sel_farm, sel_rule, "threshold", math.floor(math.max(0, thr)))
                                end
                            end
                        end
                        handled = true
                    end

                    -- Delete supply (with cooldown to prevent accidental double-delete)
                    if not handled and hits.supply_delete and draw.hit_test(hits.supply_delete, tx, ty) then
                        if os.clock() >= delete_cooldown_until then
                            local plots = fm.plots or {}
                            if sel_farm >= 1 and sel_farm <= #plots then
                                local supplies = plots[sel_farm].supplies or {}
                                if sel_rule >= 1 and sel_rule <= #supplies then
                                    fm.remove_supply(sel_farm, sel_rule)
                                    if sel_rule > #(plots[sel_farm].supplies or {}) and sel_rule > 1 then
                                        sel_rule = sel_rule - 1
                                    end
                                    delete_cooldown_until = os.clock() + 1
                                end
                            end
                        end
                        handled = true
                    end
                end
            end

            ::done::

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if picking or chest_picking or turtle_picking then
                picker_scroll = math.max(0, math.min(picker_hits.max_scroll or 0, picker_scroll + dir))
            else
                scroll = math.max(0, math.min(hits.max_scroll or 0, scroll + dir))
            end

        elseif ev[1] == "key" then
            if picking or chest_picking or turtle_picking then
                -- no key handling in pickers
            elseif ev[2] == keys.tab then
                tab = (tab % TAB_COUNT) + 1
                scroll = 0
            elseif tab == 1 then
                local plots = fm.plots or {}
                if ev[2] == keys.up and sel_farm > 1 then
                    sel_farm = sel_farm - 1
                elseif ev[2] == keys.down and sel_farm < #plots then
                    sel_farm = sel_farm + 1
                end
            elseif tab == 2 then
                local plots = fm.plots or {}
                if sel_farm >= 1 and sel_farm <= #plots then
                    local supplies = plots[sel_farm].supplies or {}
                    if ev[2] == keys.up and sel_rule > 1 then
                        sel_rule = sel_rule - 1
                    elseif ev[2] == keys.down and sel_rule < #supplies then
                        sel_rule = sel_rule + 1
                    end
                end
            end
        end
    end
end

return app
