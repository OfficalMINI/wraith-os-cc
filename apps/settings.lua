-- =============================================
-- WRAITH OS - SETTINGS APP
-- =============================================
-- Peripheral setup, smelting config, system info.
-- Card-based UI with icons, scroll buttons, PC search.

local app = {
    id = "settings",
    name = "Settings",
    icon = "settings",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local scroll = 0
local sort_mode = "id"
local search_query = ""
local settings_tab = 1  -- 1=peripherals, 2=mining
local SETTINGS_TAB_COUNT = 2
local mining_scroll = 0

-- Hit areas populated by render, consumed by click handler
local hits = {}

-- ========================================
-- Peripherals tab render
-- ========================================
local function render_peripherals_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage
    local labels = st.labels or {}
    local tab_start_y = y

    -- ========================================
    -- Assignment cards
    -- ========================================
    local assign = st.get_assignments and st.get_assignments() or {}
    local labels = st.labels or {}

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Withdraw chest card
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "\16", theme.accent2, theme.surface)
    draw.put(buf, x + 3, y, "WITHDRAW:", theme.fg_dim, theme.surface)
    local oname = assign.output or "Not set"
    if #oname > w - 20 then oname = oname:sub(1, w - 22) .. ".." end
    draw.put(buf, x + 13, y, oname, assign.output_ok and theme.success or theme.danger, theme.surface)
    y = y + 1

    -- Output-as-depot toggle
    draw.fill(buf, y, x + w, theme.surface)
    local oad = assign.output_as_depot
    local oad_label = oad and "AUTO-IMPORT ON" or "AUTO-IMPORT OFF"
    local oad_col = oad and theme.success or theme.fg_dim
    draw.put(buf, x + 3, y, "\7", oad_col, theme.surface)
    draw.put(buf, x + 5, y, oad_label, oad_col, theme.surface)
    draw.put(buf, x + 5 + #oad_label + 1, y, "(2min cooldown)", theme.fg_dark, theme.surface)
    draw.button(buf, x + w - 10, y, 9, 1, "TOGGLE", oad and theme.success or theme.fg_dim, theme.btn_text, true)
    hits.oad_btn = {x = w - 10 + 1, y = y - hits.oy + 1, w = 9, h = 1}
    y = y + 1

    -- Fuel chest card
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "\7", theme.accent2, theme.surface)
    draw.put(buf, x + 3, y, "FUEL:", theme.fg_dim, theme.surface)
    local fname = assign.fuel or "Not set"
    if #fname > w - 16 then fname = fname:sub(1, w - 18) .. ".." end
    draw.put(buf, x + 9, y, fname, assign.fuel_ok and theme.accent2 or theme.fg_dim, theme.surface)
    y = y + 1

    -- Depots card
    local depots = assign.depots or {}
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "\4", theme.info, theme.surface)
    draw.put(buf, x + 3, y, string.format("DEPOTS: %d input points", #depots), theme.fg_dim, theme.surface)
    y = y + 1

    for di, d in ipairs(depots) do
        if di > 2 then
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 5, y, string.format("...and %d more", #depots - 2), theme.fg_dark, theme.surface)
            y = y + 1
            break
        end
        draw.fill(buf, y, x + w, theme.surface)
        local dlbl = labels[d]
        local dline = d
        if dlbl then dline = dline .. " (" .. dlbl .. ")" end
        if #dline > w - 8 then dline = dline:sub(1, w - 10) .. ".." end
        draw.put(buf, x + 5, y, dline, theme.info, theme.surface)
        y = y + 1
    end

    -- ========================================
    -- Peripheral list separator + search
    -- ========================================
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Search bar
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "\16", theme.accent, theme.surface)
    draw.put(buf, x + 3, y, "[", theme.fg_dim, theme.surface)
    local sq = search_query ~= "" and search_query or "search peripherals..."
    local sq_fg = search_query ~= "" and theme.fg or theme.fg_dim
    local search_w = w - 20
    draw.put(buf, x + 4, y, utils.pad_right(sq, search_w), sq_fg, theme.surface)
    draw.put(buf, x + 4 + search_w, y, "]", theme.fg_dim, theme.surface)
    -- Sort button
    local sort_lbl = sort_mode == "name" and "BY NAME" or "BY ID"
    draw.button(buf, x + w - 10, y, 8, 1, sort_lbl, theme.fg_dim, theme.surface, true)
    hits.sort_btn = {x = w - 10 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    hits.search_bar = {x = 1, y = y - hits.oy + 1, w = w - 12, h = 1}
    y = y + 1

    -- Peripherals header
    local periphs = st.list_peripherals and st.list_peripherals() or {}

    -- Filter by search
    local filtered_periphs = {}
    for _, p in ipairs(periphs) do
        if search_query == "" then
            table.insert(filtered_periphs, p)
        else
            local q = search_query:lower()
            local lbl = labels[p.name] or ""
            if p.name:lower():find(q, 1, true) or
               p.type:lower():find(q, 1, true) or
               lbl:lower():find(q, 1, true) then
                table.insert(filtered_periphs, p)
            end
        end
    end

    -- Sort
    local sorted_periphs = {}
    for _, p in ipairs(filtered_periphs) do table.insert(sorted_periphs, p) end
    if sort_mode == "name" then
        table.sort(sorted_periphs, function(a, b)
            local la = labels[a.name] or a.name
            local lb = labels[b.name] or b.name
            return la:lower() < lb:lower()
        end)
    else
        table.sort(sorted_periphs, function(a, b) return a.name < b.name end)
    end

    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("PERIPHERALS (%d/%d)", #sorted_periphs, #periphs), theme.accent, theme.surface)
    y = y + 1

    if #sorted_periphs == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        local msg = #periphs == 0 and "No storage peripherals found" or "No matches"
        draw.center(buf, msg, y, x + w, theme.fg_dim, theme.surface)
        y = y + 1

        if #periphs == 0 then
            draw.fill(buf, y, x + w, theme.surface)
            local svc_status = st.list_peripherals and "Service loaded" or "SERVICE NOT LOADED"
            local svc_col = st.list_peripherals and theme.success or theme.danger
            draw.put(buf, x + 1, y, "Svc: " .. svc_status, svc_col, theme.surface)
            draw.button(buf, x + w - 10, y, 9, 1, "RESCAN", theme.accent, theme.btn_text, true)
            hits.rescan_btn = {x = w - 10 + 1, y = y - hits.oy + 1, w = 9, h = 1}
            y = y + 1
        end
    else
        local ROWS_PER = 2
        local area_h = h - (y - tab_start_y) - 2
        if area_h < ROWS_PER then area_h = ROWS_PER end
        local visible = math.floor(area_h / ROWS_PER)
        if visible < 1 then visible = 1 end

        local max_scroll = math.max(0, #sorted_periphs - visible)
        if scroll > max_scroll then scroll = max_scroll end
        hits.max_scroll = max_scroll

        local bw2 = 7

        for vi = 1, visible do
            local idx = scroll + vi
            if idx > #sorted_periphs then
                draw.fill(buf, y, x + w, theme.surface)
                y = y + 1
                draw.fill(buf, y, x + w, theme.surface)
                y = y + 1
            else
                local p = sorted_periphs[idx]
                local role = st.names[p.name] or ""
                local tag, tcol
                if role == "output" then tag = "[OUT]"; tcol = theme.success
                elseif role == "fuel" then tag = "[FUEL]"; tcol = theme.accent2
                elseif role == "depot" then tag = "[DEPOT]"; tcol = theme.info
                else tag = "[STORE]"; tcol = theme.fg_dim end

                -- Line 1: name + type + role
                draw.fill(buf, y, x + w, theme.surface)
                local short_type = p.type:gsub(".*:", "")
                local meta = string.format("%s %ds", short_type, p.slots)
                local name_max = w - #meta - #tag - 6
                local dn = p.name
                if #dn > name_max then dn = dn:sub(1, name_max - 2) .. ".." end
                draw.put(buf, x + 1, y, dn, tcol, theme.surface)
                draw.put(buf, x + 1 + name_max + 1, y, meta, theme.fg_dark, theme.surface)
                draw.put(buf, x + w - #tag - 1, y, tag, tcol, theme.surface)
                y = y + 1

                -- Line 2: label + action buttons
                draw.fill(buf, y, x + w, theme.surface)
                local plbl = labels[p.name]
                if plbl then
                    local plbl_d = plbl
                    if #plbl_d > w - 28 then plbl_d = plbl_d:sub(1, w - 30) .. ".." end
                    draw.put(buf, x + 3, y, plbl_d, theme.fg_dim, theme.surface)
                end

                local bx3 = x + w - bw2 - 1
                local bx2 = bx3 - bw2 - 1
                local bx1 = bx2 - bw2 - 1

                local btn_local_y = y - hits.oy + 1
                local periph_hits = {name = p.name, role = role}

                if role == "output" then
                    draw.button(buf, bx1, y, bw2, 1, "CLEAR", theme.danger, theme.btn_text, true)
                    periph_hits.btn1 = {x = bx1 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "clear_output"}
                elseif role == "depot" then
                    draw.button(buf, bx1, y, bw2, 1, "OUT", theme.accent2, theme.surface, true)
                    draw.button(buf, bx2, y, bw2, 1, "UNDPOT", theme.danger, theme.btn_text, true)
                    draw.button(buf, bx3, y, bw2, 1, "FUEL", theme.accent2, theme.surface, true)
                    periph_hits.btn1 = {x = bx1 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "set_output"}
                    periph_hits.btn2 = {x = bx2 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "remove_depot"}
                    periph_hits.btn3 = {x = bx3 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "set_fuel"}
                elseif role == "fuel" then
                    draw.button(buf, bx1, y, bw2, 1, "OUT", theme.accent2, theme.surface, true)
                    draw.button(buf, bx2, y, bw2, 1, "DEPOT", theme.accent, theme.surface, true)
                    draw.button(buf, bx3, y, bw2, 1, "UNFUEL", theme.danger, theme.btn_text, true)
                    periph_hits.btn1 = {x = bx1 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "set_output"}
                    periph_hits.btn2 = {x = bx2 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "add_depot"}
                    periph_hits.btn3 = {x = bx3 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "clear_fuel"}
                else
                    draw.button(buf, bx1, y, bw2, 1, "OUT", theme.accent2, theme.surface, true)
                    draw.button(buf, bx2, y, bw2, 1, "DEPOT", theme.accent, theme.surface, true)
                    draw.button(buf, bx3, y, bw2, 1, "FUEL", theme.accent2, theme.surface, true)
                    periph_hits.btn1 = {x = bx1 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "set_output"}
                    periph_hits.btn2 = {x = bx2 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "add_depot"}
                    periph_hits.btn3 = {x = bx3 - hits.ox + 1, y = btn_local_y, w = bw2, h = 1, action = "set_fuel"}
                end

                -- Label button (rename)
                draw.button(buf, x + w - bw2 * 3 - 4, y, 3, 1, "\16", theme.fg_dim, theme.surface, true)
                periph_hits.label_btn = {x = w - bw2 * 3 - 4 + 1, y = btn_local_y, w = 3, h = 1}

                table.insert(hits.periphs, periph_hits)
                y = y + 1
            end
        end

        -- Scroll bar with clickable arrows
        draw.fill(buf, y, x + w, theme.surface2)
        if #sorted_periphs > visible then
            -- Scroll up button
            draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
            hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}

            local info = string.format("%d-%d of %d", scroll + 1, math.min(scroll + visible, #sorted_periphs), #sorted_periphs)
            draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)

            -- Scroll down button
            draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_scroll)
            hits.scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
        else
            draw.center(buf, string.format("%d peripherals", #sorted_periphs), y, x + w, theme.fg_dim, theme.surface2)
        end
    end
end

-- ========================================
-- Mining tab render
-- ========================================
local function render_mining_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local mm = ctx.state.mastermine
    local tab_start_y = y

    -- Auto mode + Hub ID row
    draw.fill(buf, y, x + w, theme.surface)
    local auto_lbl = mm.auto_mode and "AUTO MODE: ON" or "AUTO MODE: OFF"
    local auto_col = mm.auto_mode and theme.success or theme.fg_dim
    draw.put(buf, x + 1, y, auto_lbl, auto_col, theme.surface)
    draw.button(buf, x + 20, y, 8, 1, "TOGGLE", auto_col, theme.btn_text, true)
    hits.mining_auto_btn = {x = 21, y = y - hits.oy + 1, w = 8, h = 1}

    local hub_lbl = mm.hub_id and string.format("Hub #%d", mm.hub_id) or "Hub: Not set"
    local hub_col = mm.hub_connected and theme.success or theme.danger
    draw.put(buf, x + 30, y, hub_lbl, hub_col, theme.surface)
    draw.button(buf, x + w - 7, y, 6, 1, "SET", theme.accent, theme.btn_text, true)
    hits.mining_hub_btn = {x = w - 7 + 1, y = y - hits.oy + 1, w = 6, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Ore table header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "ORE", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 11, y, "BEST Y", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 19, y, "THRESH", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 27, y, "STOCK", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 35, y, "NEED", theme.fg_dim, theme.surface2)
    draw.put(buf, x + w - 3, y, "ON", theme.fg_dim, theme.surface2)
    y = y + 1

    -- Ore table rows
    local ore_table = mm.ore_table or {}
    local area_h = h - (y - tab_start_y) - 6  -- leave room for preview
    if area_h < 1 then area_h = 1 end
    local max_ore_scroll = math.max(0, #ore_table - area_h)
    if mining_scroll > max_ore_scroll then mining_scroll = max_ore_scroll end
    hits.mining_max_scroll = max_ore_scroll
    hits.ore_rows = {}

    for vi = 1, math.min(area_h, #ore_table - mining_scroll) do
        local idx = mining_scroll + vi
        local ore = ore_table[idx]
        if not ore then break end

        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)

        -- Dim entire row when disabled
        local dim = not ore.enabled

        -- Name
        local name_col = dim and theme.fg_dim or theme.fg
        draw.put(buf, x + 1, y, ore.name:sub(1, 9), name_col, rbg)

        -- Best Y (clickable)
        draw.put(buf, x + 11, y, string.format("%-6d", ore.best_y), dim and theme.fg_dim or theme.accent, rbg)

        -- Threshold (clickable)
        draw.put(buf, x + 19, y, string.format("%-6d", ore.threshold), dim and theme.fg_dim or theme.accent, rbg)

        -- Current stock
        local stock = ore.current_stock or 0
        local stock_col = dim and theme.fg_dim or (stock >= ore.threshold and theme.success or (stock >= ore.threshold * 0.5 and theme.warning or theme.danger))
        draw.put(buf, x + 27, y, string.format("%-6d", stock), stock_col, rbg)

        -- Need %
        local need = ore.need_pct or 0
        local need_col = dim and theme.fg_dim or (need > 0.5 and theme.danger or (need > 0 and theme.warning or theme.success))
        draw.put(buf, x + 35, y, string.format("%3d%%", math.floor(need * 100)), need_col, rbg)

        -- Enabled toggle (right-aligned)
        local en_lbl = ore.enabled and " ON" or "OFF"
        local en_bg = ore.enabled and theme.success or theme.danger
        draw.put(buf, x + w - 3, y, en_lbl, theme.bg, en_bg)

        local ore_hit = {x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx}
        -- Specific clickable areas
        ore_hit.best_y_area = {x = 12, y = y - hits.oy + 1, w = 6, h = 1}
        ore_hit.threshold_area = {x = 20, y = y - hits.oy + 1, w = 6, h = 1}
        ore_hit.toggle_area = {x = w - 2, y = y - hits.oy + 1, w = 4, h = 1}
        ore_hit.name_area = {x = 1, y = y - hits.oy + 1, w = 10, h = 1}
        table.insert(hits.ore_rows, ore_hit)
        y = y + 1
    end

    -- Fill remaining ore area
    for r = y, y + (area_h - math.min(area_h, #ore_table - mining_scroll)) - 1 do
        draw.fill(buf, r, x + w, theme.surface)
    end
    y = y + math.max(0, area_h - math.min(area_h, #ore_table - mining_scroll))

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Mine levels preview
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "GENERATED LEVELS:", theme.accent, theme.surface)
    local sync_lbl = mm.hub_connected and "SYNCED" or "NOT SYNCED"
    draw.put(buf, x + w - #sync_lbl - 1, y, sync_lbl, mm.hub_connected and theme.success or theme.danger, theme.surface)
    y = y + 1

    local levels = mm.mine_levels or {}
    if #levels > 0 then
        for _, lv in ipairs(levels) do
            draw.fill(buf, y, x + w, theme.surface)
            local bar_w = math.floor((w - 20) * lv.chance)
            draw.put(buf, x + 1, y, string.format("Y=%-4d %3d%%", lv.level, math.floor(lv.chance * 100)), theme.fg, theme.surface)
            buf.setCursorPos(x + 15, y)
            buf.setBackgroundColor(theme.accent)
            buf.write(string.rep(" ", math.max(1, bar_w)))
            buf.setBackgroundColor(theme.surface)
            buf.write(string.rep(" ", math.max(0, w - 16 - bar_w)))
            y = y + 1
            if y > tab_start_y + h - 2 then break end
        end
    else
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No levels (all ores stocked)", theme.fg_dim, theme.surface)
        y = y + 1
    end

    -- Sync button
    draw.fill(buf, y, x + w, theme.surface2)
    draw.button(buf, x + 1, y, 12, 1, "FORCE SYNC", theme.accent, theme.btn_text, mm.hub_connected)
    hits.mining_sync_btn = {x = 2, y = y - hits.oy + 1, w = 12, h = 1}
end

-- ========================================
-- Main render
-- ========================================
function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage
    local config = ctx.config

    -- Reset hit areas each frame
    hits = {periphs = {}}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- ========================================
    -- Header card: icon + system info
    -- ========================================
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.settings

    for r = 0, 3 do
        draw.fill(buf, y + r, x + w, theme.surface2)
    end

    if icon_data and icon_lib then
        icon_lib.draw(buf, icon_data, x + 2, y)
    end

    local sx = x + 11
    draw.put(buf, sx, y, "SETTINGS", theme.accent, theme.surface2)
    draw.put(buf, sx, y + 1, string.format("Wraith OS v%s", config.version), theme.fg_dim, theme.surface2)
    draw.put(buf, sx, y + 2, string.format("Computer #%d", os.getComputerID()), theme.fg_dim, theme.surface2)
    draw.put(buf, sx, y + 3, "Up " .. utils.format_uptime(os.clock() - ctx.state.boot_time), theme.fg_dim, theme.surface2)
    y = y + 4

    -- ========================================
    -- Tab bar
    -- ========================================
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"PERIPHERALS", "MINING"}
    local tw = math.floor(w / SETTINGS_TAB_COUNT)
    hits.settings_tabs = {}
    for ti = 1, SETTINGS_TAB_COUNT do
        local tx2 = x + (ti - 1) * tw
        local sel = (ti == settings_tab)
        local tbg = sel and theme.accent or theme.surface
        local tfg = sel and theme.bg or theme.fg_dim
        buf.setCursorPos(tx2, y)
        buf.setBackgroundColor(tbg)
        buf.setTextColor(tfg)
        local lbl = utils.pad_center(tab_labels[ti], tw)
        buf.write(lbl)
        hits.settings_tabs[ti] = {x = tx2 - hits.ox + 1, y = y - hits.oy + 1, w = tw, h = 1}
    end
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- ========================================
    -- Tab content
    -- ========================================
    local content_h = h - (y - ctx.content_y)

    if settings_tab == 1 then
        render_peripherals_tab(ctx, buf, x, y, w, content_h)
    elseif settings_tab == 2 then
        render_mining_tab(ctx, buf, x, y, w, content_h)
    end
end

function app.main(ctx)
    local st = ctx.state.storage
    local mm = ctx.state.mastermine
    local draw = ctx.draw
    local utils = ctx.utils

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3], ev[4]

            -- Tab bar clicks
            local tab_clicked = false
            for ti, area in ipairs(hits.settings_tabs or {}) do
                if draw.hit_test(area, tx, ty) then
                    settings_tab = ti
                    scroll = 0
                    mining_scroll = 0
                    tab_clicked = true
                    break
                end
            end

            if tab_clicked then
                -- Tab switch handled

            elseif settings_tab == 2 then
                -- Mining tab clicks
                if hits.mining_auto_btn and draw.hit_test(hits.mining_auto_btn, tx, ty) then
                    if mm.toggle_auto then mm.toggle_auto() end
                elseif hits.mining_hub_btn and draw.hit_test(hits.mining_hub_btn, tx, ty) then
                    local current = mm.hub_id and tostring(mm.hub_id) or ""
                    local result = utils.pc_input("SET HUB ID", "Enter the MasterMine hub computer ID:", current)
                    if result and mm.set_hub then mm.set_hub(result) end
                elseif hits.mining_sync_btn and draw.hit_test(hits.mining_sync_btn, tx, ty) then
                    if mm.force_sync then mm.force_sync() end
                else
                    -- Ore row clicks
                    for _, row in ipairs(hits.ore_rows or {}) do
                        if row.toggle_area and draw.hit_test(row.toggle_area, tx, ty) then
                            if mm.set_ore_enabled then
                                local ore = (mm.ore_table or {})[row.idx]
                                if ore then mm.set_ore_enabled(row.idx, not ore.enabled) end
                            end
                            break
                        elseif row.name_area and draw.hit_test(row.name_area, tx, ty) then
                            -- Clicking ore name also toggles enabled
                            if mm.set_ore_enabled then
                                local ore = (mm.ore_table or {})[row.idx]
                                if ore then mm.set_ore_enabled(row.idx, not ore.enabled) end
                            end
                            break
                        elseif row.best_y_area and draw.hit_test(row.best_y_area, tx, ty) then
                            local ore = (mm.ore_table or {})[row.idx]
                            if ore then
                                local result = utils.pc_input("EDIT BEST Y", ore.name .. " - best Y level:", tostring(ore.best_y))
                                if result and mm.set_ore_best_y then mm.set_ore_best_y(row.idx, result) end
                            end
                            break
                        elseif row.threshold_area and draw.hit_test(row.threshold_area, tx, ty) then
                            local ore = (mm.ore_table or {})[row.idx]
                            if ore then
                                local result = utils.pc_input("EDIT THRESHOLD", ore.name .. " - stock threshold:", tostring(ore.threshold))
                                if result and mm.set_ore_threshold then mm.set_ore_threshold(row.idx, result) end
                            end
                            break
                        end
                    end
                end

            else
                -- Peripherals tab clicks (tab 1)
                if hits.search_bar and draw.hit_test(hits.search_bar, tx, ty) then
                    local result = utils.pc_input("SEARCH PERIPHERALS", "Type peripheral name or type to filter.")
                    if result then
                        search_query = result
                    else
                        search_query = ""
                    end
                    scroll = 0
                elseif hits.sort_btn and draw.hit_test(hits.sort_btn, tx, ty) then
                    sort_mode = sort_mode == "id" and "name" or "id"
                elseif hits.oad_btn and draw.hit_test(hits.oad_btn, tx, ty) then
                    if st.toggle_output_depot then st.toggle_output_depot() end
                elseif hits.rescan_btn and draw.hit_test(hits.rescan_btn, tx, ty) then
                    if st.rescan then st.rescan() end
                elseif hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                    if scroll > 0 then scroll = scroll - 1 end
                elseif hits.scroll_down and draw.hit_test(hits.scroll_down, tx, ty) then
                    local max_s = hits.max_scroll or 0
                    if scroll < max_s then scroll = scroll + 1 end
                else
                    for _, ph in ipairs(hits.periphs or {}) do
                        if ph.label_btn and draw.hit_test(ph.label_btn, tx, ty) then
                            local current = st.get_label and st.get_label(ph.name) or ""
                            local result = utils.pc_input("RENAME PERIPHERAL", ph.name, current)
                            if result and st.set_label then
                                st.set_label(ph.name, result)
                            end
                            break
                        end
                        if ph.btn1 and draw.hit_test(ph.btn1, tx, ty) then
                            if ph.btn1.action == "clear_output" and st.clear_output then st.clear_output()
                            elseif ph.btn1.action == "set_output" and st.setup_output then st.setup_output(ph.name) end
                            break
                        elseif ph.btn2 and draw.hit_test(ph.btn2, tx, ty) then
                            if ph.btn2.action == "remove_depot" and st.remove_depot then st.remove_depot(ph.name)
                            elseif ph.btn2.action == "add_depot" and st.add_depot then st.add_depot(ph.name) end
                            break
                        elseif ph.btn3 and draw.hit_test(ph.btn3, tx, ty) then
                            if ph.btn3.action == "clear_fuel" and st.clear_fuel then st.clear_fuel()
                            elseif ph.btn3.action == "set_fuel" and st.setup_fuel then st.setup_fuel(ph.name) end
                            break
                        end
                    end
                end
            end

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if settings_tab == 1 then
                local max_s = hits.max_scroll or 0
                scroll = math.max(0, math.min(max_s, scroll + dir))
            elseif settings_tab == 2 then
                local max_s = hits.mining_max_scroll or 0
                mining_scroll = math.max(0, math.min(max_s, mining_scroll + dir))
            end

        elseif ev[1] == "key" then
            if settings_tab == 1 then
                local max_s = hits.max_scroll or 0
                if ev[2] == keys.up and scroll > 0 then scroll = scroll - 1
                elseif ev[2] == keys.down and scroll < max_s then scroll = scroll + 1 end
            elseif settings_tab == 2 then
                local max_s = hits.mining_max_scroll or 0
                if ev[2] == keys.up and mining_scroll > 0 then mining_scroll = mining_scroll - 1
                elseif ev[2] == keys.down and mining_scroll < max_s then mining_scroll = mining_scroll + 1 end
            end
        end
    end
end

return app
