-- =============================================
-- WRAITH OS - LIGHTING APP
-- =============================================
-- Configure player light themes and manage
-- Rainbow Lamp controllers.

local app = {
    id = "lighting",
    name = "Lighting",
    icon = "lighting",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1       -- 1=Players, 2=Theme, 3=Controllers
local TAB_COUNT = 3
local scroll = 0
local hits = {}

-- Theme editor state
local selected_player = nil
local editing_colors = {}
local editing_pattern = "solid"

-- Signal-to-CC color mapping for preview on monitor
local SIGNAL_TO_CC = {
    [0]  = colors.black,      [1]  = colors.gray,
    [2]  = colors.lightGray,  [3]  = colors.brown,
    [4]  = colors.green,      [5]  = colors.lime,
    [6]  = colors.cyan,       [7]  = colors.lightBlue,
    [8]  = colors.blue,       [9]  = colors.purple,
    [10] = colors.magenta,    [11] = colors.pink,
    [12] = colors.red,        [13] = colors.orange,
    [14] = colors.yellow,     [15] = colors.white,
}

local COLOR_NAMES = {
    [0]  = "Off",       [1]  = "Gray",      [2]  = "Lt.Gray",  [3]  = "Brown",
    [4]  = "Green",     [5]  = "Lime",      [6]  = "Cyan",     [7]  = "Lt.Blue",
    [8]  = "Blue",      [9]  = "Purple",    [10] = "Magenta",  [11] = "Pink",
    [12] = "Red",       [13] = "Orange",    [14] = "Yellow",   [15] = "White",
}

-- ========================================
-- Render: Players Tab
-- ========================================
local function render_players_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local lt = ctx.state.lighting

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "PLAYER", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 22, y, "POSITION", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 38, y, "THEME", theme.fg_dim, theme.surface2)
    y = y + 1

    local players = {}
    if lt.get_nearby_players then
        players = lt.get_nearby_players()
    end

    local area_h = h - 2
    local max_scroll = math.max(0, #players - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.player_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)
        if idx <= #players then
            local p = players[idx]
            -- Name
            local name_display = p.name
            if #name_display > 19 then name_display = name_display:sub(1, 17) .. ".." end
            draw.put(buf, x + 1, y, name_display, theme.fg, rbg)
            -- Position
            draw.put(buf, x + 22, y,
                string.format("%d,%d,%d", math.floor(p.x), math.floor(p.y), math.floor(p.z)),
                theme.fg_dim, rbg)
            -- Theme indicator
            if p.has_theme then
                local th = lt.player_themes[p.name]
                if th then
                    local cx = x + 38
                    for _, c in ipairs(th.colors) do
                        buf.setCursorPos(cx, y)
                        buf.setBackgroundColor(SIGNAL_TO_CC[c] or colors.black)
                        buf.write("  ")
                        cx = cx + 2
                    end
                    buf.setBackgroundColor(rbg)
                    draw.put(buf, cx + 1, y, th.pattern:sub(1, 4), theme.fg_dim, rbg)
                end
            else
                draw.put(buf, x + 38, y, "---", theme.fg_dim, rbg)
            end
            -- Edit button
            draw.button(buf, x + w - 6, y, 5, 1, "EDIT", theme.accent, theme.btn_text, true)
            table.insert(hits.player_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1,
                name = p.name,
                edit_btn = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1},
            })
        end
        y = y + 1
    end

    -- Empty state
    if #players == 0 then
        local msg_y = ctx.content_y + 8
        draw.fill(buf, msg_y, x + w, theme.surface)
        draw.center(buf, "No players detected nearby", msg_y, x + w, theme.fg_dim, theme.surface)
        draw.fill(buf, msg_y + 1, x + w, theme.surface)
        draw.center(buf, "Ensure a Player Detector is connected", msg_y + 1, x + w, theme.fg_dim, theme.surface)
    end

    -- Scroll bar
    draw.fill(buf, y, x + w, theme.surface2)
    if #players > area_h then
        draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
        hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}
        local info = string.format("%d-%d of %d", scroll + 1, math.min(scroll + area_h, #players), #players)
        draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)
        draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_scroll)
        hits.scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    else
        local count_lbl = string.format("%d players", #players)
        draw.center(buf, count_lbl, y, x + w, theme.fg_dim, theme.surface2)
    end
end

-- ========================================
-- Render: Theme Editor Tab
-- ========================================
local function render_theme_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local lt = ctx.state.lighting
    local cfg = ctx.config.lighting

    if not selected_player then
        local msg_y = y + 4
        draw.fill(buf, msg_y, x + w, theme.surface)
        draw.center(buf, "Select a player from the Players tab", msg_y, x + w, theme.fg_dim, theme.surface)
        draw.fill(buf, msg_y + 1, x + w, theme.surface)
        draw.center(buf, "to configure their lighting theme", msg_y + 1, x + w, theme.fg_dim, theme.surface)
        return
    end

    -- Header
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "Theme for: ", theme.fg_dim, theme.surface)
    draw.put(buf, x + 12, y, selected_player, theme.accent, theme.surface)
    draw.button(buf, x + w - 7, y, 6, 1, "CLEAR", theme.danger, theme.btn_text, true)
    hits.theme_clear = {x = w - 7 + 1, y = y - hits.oy + 1, w = 6, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Color reference grid (read-only, shows signal numbers)
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "COLOR REFERENCE", theme.fg_dim, theme.surface)
    y = y + 1

    local CELL_W = 10
    local CELL_GAP = 1
    for row = 0, 3 do
        draw.fill(buf, y, x + w, theme.surface)
        for col = 0, 3 do
            local sig = row * 4 + col
            local cx = x + 2 + col * (CELL_W + CELL_GAP)
            buf.setCursorPos(cx, y)
            buf.setBackgroundColor(SIGNAL_TO_CC[sig])
            local text_fg = (sig <= 1 or sig == 8) and colors.white or colors.black
            buf.setTextColor(text_fg)
            local label = string.format("%2d %-6s", sig, (COLOR_NAMES[sig] or "?"):sub(1, 6))
            buf.write(label:sub(1, CELL_W))
        end
        y = y + 1
    end
    y = y + 1

    -- Selected colors + ADD button
    draw.fill(buf, y, x + w, theme.surface)
    local can_add = #editing_colors < cfg.max_colors_per_theme
    draw.put(buf, x + 1, y, string.format("COLORS (%d/%d):", #editing_colors, cfg.max_colors_per_theme), theme.fg_dim, theme.surface)
    draw.button(buf, x + w - 7, y, 6, 1, "+ ADD", can_add and theme.accent or theme.surface2,
        can_add and theme.btn_text or theme.fg_dim, can_add)
    hits.color_add = {x = w - 7 + 1, y = y - hits.oy + 1, w = 6, h = 1}
    y = y + 1

    -- Selected color blocks (click to remove)
    draw.fill(buf, y, x + w, theme.surface)
    hits.selected_colors = {}
    if #editing_colors == 0 then
        draw.put(buf, x + 2, y, "(none - click ADD to pick colors)", theme.fg_dim, theme.surface)
    else
        local scx = x + 2
        for i, sig in ipairs(editing_colors) do
            local name = COLOR_NAMES[sig] or "?"
            local block_w = math.min(#name + 4, 10)
            buf.setCursorPos(scx, y)
            buf.setBackgroundColor(SIGNAL_TO_CC[sig])
            local text_fg = (sig <= 1 or sig == 8) and colors.white or colors.black
            buf.setTextColor(text_fg)
            buf.write((" " .. name:sub(1, block_w - 3) .. " "):sub(1, block_w - 1))
            buf.setTextColor(theme.danger)
            buf.write("x")
            table.insert(hits.selected_colors, {
                x = scx - hits.ox + 1, y = y - hits.oy + 1, w = block_w, h = 1,
                idx = i,
            })
            scx = scx + block_w + 1
        end
        buf.setBackgroundColor(theme.surface)
    end
    y = y + 1

    -- Separator
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Pattern picker
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "PATTERN:", theme.fg_dim, theme.surface)
    y = y + 1

    local patterns = {"solid", "pulse", "strobe", "fade"}
    local pattern_labels = {"SOLID", "PULSE", "STROBE", "FADE"}
    local pw = 9
    local px = x + 2
    hits.pattern_btns = {}
    draw.fill(buf, y, x + w, theme.surface)
    for i, pat in ipairs(patterns) do
        local is_sel = (editing_pattern == pat)
        local pbg = is_sel and theme.accent or theme.surface2
        local pfg = is_sel and theme.bg or theme.fg
        draw.button(buf, px, y, pw, 1, pattern_labels[i], pbg, pfg, true)
        hits.pattern_btns[i] = {x = px - hits.ox + 1, y = y - hits.oy + 1, w = pw, h = 1, pattern = pat}
        px = px + pw + 1
    end
    y = y + 2

    -- Pattern description
    draw.fill(buf, y, x + w, theme.surface)
    local desc = ""
    if editing_pattern == "solid" then desc = "Holds a steady color"
    elseif editing_pattern == "pulse" then desc = "Ramps brightness up and down"
    elseif editing_pattern == "strobe" then desc = "Rapidly flashes between colors"
    elseif editing_pattern == "fade" then desc = "Smoothly transitions between colors"
    end
    draw.put(buf, x + 2, y, desc, theme.fg_dim, theme.surface)
    y = y + 2

    -- Save / Cancel buttons
    draw.fill(buf, y, x + w, theme.surface)
    local can_save = #editing_colors > 0
    draw.button(buf, x + 2, y, 12, 1, "SAVE THEME", can_save and theme.success or theme.surface2,
        can_save and theme.btn_text or theme.fg_dim, can_save)
    hits.theme_save = {x = 3, y = y - hits.oy + 1, w = 12, h = 1}
    draw.button(buf, x + 16, y, 10, 1, "CANCEL", theme.danger, theme.btn_text, true)
    hits.theme_cancel = {x = 17, y = y - hits.oy + 1, w = 10, h = 1}
end

-- ========================================
-- Render: Controllers Tab
-- ========================================
local function render_controllers_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local lt = ctx.state.lighting

    -- Column headers
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "ID", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 7, y, "POSITION", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 22, y, "STATUS", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 31, y, "COLOR", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 39, y, "PLAYER", theme.fg_dim, theme.surface2)
    y = y + 1

    local controllers = {}
    if lt.get_controllers then
        controllers = lt.get_controllers()
    end

    local area_h = h - 2
    local max_scroll = math.max(0, #controllers - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.ctrl_max_scroll = max_scroll
    hits.ctrl_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)
        if idx <= #controllers then
            local c = controllers[idx]
            -- ID
            draw.put(buf, x + 1, y, string.format("#%d", c.id), theme.accent, rbg)
            -- Position
            draw.put(buf, x + 7, y, string.format("%d,%d,%d", c.x, c.y, c.z), theme.fg_dim, rbg)
            -- Status
            local status_col = c.online and theme.success or theme.danger
            local status_lbl = c.online and "ONLINE" or "OFFLINE"
            draw.put(buf, x + 22, y, status_lbl, status_col, rbg)
            -- Current color
            if c.current_color and c.current_color > 0 then
                buf.setCursorPos(x + 31, y)
                buf.setBackgroundColor(SIGNAL_TO_CC[c.current_color] or colors.black)
                buf.write("   ")
                buf.setBackgroundColor(rbg)
                draw.put(buf, x + 35, y, (c.current_pattern or ""):sub(1, 4), theme.fg_dim, rbg)
            else
                draw.put(buf, x + 31, y, "OFF", theme.fg_dim, rbg)
            end
            -- Assigned player
            if c.assigned_player then
                local pname = c.assigned_player
                if #pname > w - 40 then pname = pname:sub(1, w - 43) .. ".." end
                draw.put(buf, x + 39, y, pname, theme.fg, rbg)
            end
            -- Remove button
            draw.button(buf, x + w - 4, y, 3, 1, "X", theme.danger, theme.btn_text, true)
            table.insert(hits.ctrl_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1,
                id = c.id,
                remove_btn = {x = w - 4 + 1, y = y - hits.oy + 1, w = 3, h = 1},
            })
        end
        y = y + 1
    end

    -- Empty state
    if #controllers == 0 then
        local msg_y = ctx.content_y + 8
        draw.fill(buf, msg_y, x + w, theme.surface)
        draw.center(buf, "No controllers registered", msg_y, x + w, theme.fg_dim, theme.surface)
        draw.fill(buf, msg_y + 1, x + w, theme.surface)
        draw.center(buf, "Run lighting_client on lamp PCs", msg_y + 1, x + w, theme.fg_dim, theme.surface)
    end

    -- Scroll bar
    draw.fill(buf, y, x + w, theme.surface2)
    if #controllers > area_h then
        draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
        hits.ctrl_scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}
        local info = string.format("%d-%d of %d", scroll + 1, math.min(scroll + area_h, #controllers), #controllers)
        draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)
        draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_scroll)
        hits.ctrl_scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    else
        draw.center(buf, string.format("%d controllers", #controllers), y, x + w, theme.fg_dim, theme.surface2)
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
    local lt = ctx.state.lighting

    hits = {}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Header (4 rows)
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.lighting
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data and icon_lib then icon_lib.draw(buf, icon_data, x + 2, y) end

    local sx = x + 11
    draw.put(buf, sx, y, "LIGHTING", theme.accent, theme.surface2)

    -- Detector status
    local det_lbl = lt.detector and ("Detector: " .. lt.detector_name) or "No detector"
    local det_col = lt.detector and theme.success or theme.danger
    draw.put(buf, sx, y + 1, det_lbl, det_col, theme.surface2)

    -- Controller count
    local ctrl_count = 0
    local ctrl_online = 0
    for _, c in pairs(lt.controllers) do
        ctrl_count = ctrl_count + 1
        if c.online then ctrl_online = ctrl_online + 1 end
    end
    draw.put(buf, sx, y + 2,
        string.format("Controllers: %d online / %d total", ctrl_online, ctrl_count),
        theme.fg_dim, theme.surface2)

    -- Player count
    local player_count = 0
    for _ in pairs(lt.nearby_players) do player_count = player_count + 1 end
    draw.put(buf, sx, y + 3,
        string.format("Players nearby: %d", player_count),
        theme.fg_dim, theme.surface2)

    y = y + 4

    -- Tab bar (3 content tabs + always-on toggle)
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"PLAYERS", "THEME", "CTRLS"}
    local ao_lbl = lt.always_on and "ON" or "OFF"
    local ao_w = 10
    local tabs_w = w - ao_w
    local tw = math.floor(tabs_w / TAB_COUNT)
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
    -- Always-on toggle as rightmost button on tab row
    local ao_x = x + TAB_COUNT * tw
    local ao_bg = lt.always_on and theme.success or theme.danger
    buf.setCursorPos(ao_x, y)
    buf.setBackgroundColor(ao_bg)
    buf.setTextColor(theme.btn_text)
    local ao_actual_w = w - TAB_COUNT * tw
    buf.write(utils.pad_center(ao_lbl, ao_actual_w))
    hits.ao_btn = {x = ao_x - hits.ox + 1, y = y - hits.oy + 1, w = ao_actual_w, h = 1}
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Content
    local content_h = h - (y - ctx.content_y)
    if tab == 1 then
        render_players_tab(ctx, buf, x, y, w, content_h)
    elseif tab == 2 then
        render_theme_tab(ctx, buf, x, y, w, content_h)
    elseif tab == 3 then
        render_controllers_tab(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local lt = ctx.state.lighting
    local draw = ctx.draw
    local cfg = ctx.config.lighting
    local utils = ctx.utils

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3] - 1, ev[4]

            -- Always-on toggle (checked first, separate from tabs)
            local tab_clicked = false
            if hits.ao_btn and draw.hit_test(hits.ao_btn, tx, ty) then
                if lt.toggle_always_on then
                    lt.toggle_always_on()
                end
                tab_clicked = true
            end

            -- Tab clicks (tabs 1-3 = content tabs)
            if not tab_clicked then
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
            end

            if not tab_clicked then
                if tab == 1 then
                    -- Players tab
                    for _, row in ipairs(hits.player_rows or {}) do
                        if row.edit_btn and draw.hit_test(row.edit_btn, tx, ty) then
                            selected_player = row.name
                            local existing = lt.player_themes[row.name]
                            if existing then
                                editing_colors = {}
                                for _, c in ipairs(existing.colors) do
                                    table.insert(editing_colors, c)
                                end
                                editing_pattern = existing.pattern
                            else
                                editing_colors = {}
                                editing_pattern = "solid"
                            end
                            tab = 2
                            break
                        end
                    end
                    -- Scroll
                    if hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                        if scroll > 0 then scroll = scroll - 1 end
                    elseif hits.scroll_down and draw.hit_test(hits.scroll_down, tx, ty) then
                        if scroll < (hits.max_scroll or 0) then scroll = scroll + 1 end
                    end

                elseif tab == 2 then
                    local handled = false

                    -- ADD color button -> pc_input
                    if not handled and hits.color_add and draw.hit_test(hits.color_add, tx, ty) then
                        if #editing_colors < cfg.max_colors_per_theme then
                            local result = ctx.utils.pc_input(
                                "ADD COLOR",
                                "Enter signal number (0-15). See monitor for reference."
                            )
                            if result then
                                local sig = tonumber(result)
                                if sig and sig >= 0 and sig <= 15 then
                                    sig = math.floor(sig)
                                    local already = false
                                    for _, ec in ipairs(editing_colors) do
                                        if ec == sig then already = true; break end
                                    end
                                    if not already then
                                        table.insert(editing_colors, sig)
                                    end
                                end
                            end
                        end
                        handled = true
                    end

                    -- Selected color clicks (remove)
                    if not handled then
                        for _, sc in ipairs(hits.selected_colors or {}) do
                            if draw.hit_test(sc, tx, ty) then
                                table.remove(editing_colors, sc.idx)
                                handled = true
                                break
                            end
                        end
                    end

                    -- Pattern buttons
                    if not handled then
                        for _, pb in ipairs(hits.pattern_btns or {}) do
                            if draw.hit_test(pb, tx, ty) then
                                editing_pattern = pb.pattern
                                handled = true
                                break
                            end
                        end
                    end

                    -- Save
                    if not handled and hits.theme_save and draw.hit_test(hits.theme_save, tx, ty) then
                        if #editing_colors > 0 and lt.set_theme and selected_player then
                            local cols = {}
                            for _, c in ipairs(editing_colors) do table.insert(cols, c) end
                            lt.set_theme(selected_player, cols, editing_pattern)
                            utils.set_status(ctx.state, "Theme saved for " .. selected_player, colors.lime, 3)
                        end
                        handled = true
                    end

                    -- Cancel
                    if not handled and hits.theme_cancel and draw.hit_test(hits.theme_cancel, tx, ty) then
                        selected_player = nil
                        editing_colors = {}
                        editing_pattern = "solid"
                        tab = 1
                    end

                    -- Clear
                    if not handled and hits.theme_clear and draw.hit_test(hits.theme_clear, tx, ty) then
                        if lt.remove_theme and selected_player then
                            lt.remove_theme(selected_player)
                            utils.set_status(ctx.state, "Theme cleared for " .. selected_player, colors.orange, 3)
                        end
                        editing_colors = {}
                        editing_pattern = "solid"
                    end

                elseif tab == 3 then
                    -- Controllers tab
                    for _, row in ipairs(hits.ctrl_rows or {}) do
                        if row.remove_btn and draw.hit_test(row.remove_btn, tx, ty) then
                            if lt.remove_controller then
                                lt.remove_controller(row.id)
                            end
                            break
                        end
                    end
                    -- Scroll
                    if hits.ctrl_scroll_up and draw.hit_test(hits.ctrl_scroll_up, tx, ty) then
                        if scroll > 0 then scroll = scroll - 1 end
                    elseif hits.ctrl_scroll_down and draw.hit_test(hits.ctrl_scroll_down, tx, ty) then
                        if scroll < (hits.ctrl_max_scroll or 0) then scroll = scroll + 1 end
                    end
                end
            end

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if tab == 1 then
                scroll = math.max(0, math.min(hits.max_scroll or 0, scroll + dir))
            elseif tab == 3 then
                scroll = math.max(0, math.min(hits.ctrl_max_scroll or 0, scroll + dir))
            end

        elseif ev[1] == "key" then
            if ev[2] == keys.tab then
                tab = (tab % TAB_COUNT) + 1
                scroll = 0
            elseif tab == 1 or tab == 3 then
                local max_s = (tab == 1 and hits.max_scroll or hits.ctrl_max_scroll) or 0
                if ev[2] == keys.up and scroll > 0 then
                    scroll = scroll - 1
                elseif ev[2] == keys.down and scroll < max_s then
                    scroll = scroll + 1
                end
            end
        end
    end
end

return app
