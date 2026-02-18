-- =============================================
-- WRAITH OS - AR GOGGLES APP
-- =============================================
-- Configure HUD, world markers, and view alerts.

local app = {
    id = "ar",
    name = "AR Goggles",
    icon = "ar",
    default_w = 42,
    default_h = 24,
    singleton = true,
}

local tab = 1       -- 1=HUD, 2=WORLD, 3=ALERTS
local scroll = 0
local hits = {}

-- ========================================
-- Helpers
-- ========================================
local function time_ago(t)
    local diff = os.clock() - t
    if diff < 60 then return math.floor(diff) .. "s" end
    if diff < 3600 then return math.floor(diff / 60) .. "m" end
    return math.floor(diff / 3600) .. "h"
end

-- ========================================
-- Render: Tab bar
-- ========================================
local function draw_tabs(buf, x, y, w, draw, theme)
    draw.fill(buf, y, x + w, theme.surface2)
    local tabs = {"HUD", "WORLD", "ALERTS"}
    local tx = x + 1
    for i, label in ipairs(tabs) do
        local active = (tab == i)
        local fg = active and theme.accent or theme.fg_dim
        local bg = active and theme.surface or theme.surface2
        draw.put(buf, tx, y, " " .. label .. " ", fg, bg)
        local tw = #label + 2
        hits["tab_" .. i] = {x = tx - hits.ox, y = y - hits.oy, w = tw, h = 1}
        tx = tx + tw + 1
    end

    -- Alert badge on alerts tab
    local ar = _G._wraith and _G._wraith.state and _G._wraith.state.ar
    if ar and ar.alert_count > 0 then
        draw.put(buf, tx, y, tostring(ar.alert_count), theme.danger, theme.surface2)
    end
end

-- ========================================
-- Render: HUD Config (Tab 1)
-- ========================================
local function render_hud_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ar = ctx.state.ar

    -- Master toggle
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "AR Overlay:", theme.fg, theme.surface2)
    local on = ar.enabled
    draw.button(buf, x + w - 8, y, 7, 1, on and "ON" or "OFF", on and theme.success or theme.danger, theme.btn_text, true)
    hits.master_toggle = {x = (x + w - 8) - hits.ox, y = y - hits.oy, w = 7, h = 1}
    y = y + 1

    -- Controller status
    local status = ar.connected and ("Connected: " .. ar.controller_name) or "No controller found"
    local sc = ar.connected and theme.success or theme.danger
    draw.put(buf, x + 1, y, status, sc, theme.surface)
    y = y + 2

    draw.put(buf, x + 1, y, "HUD SECTIONS", theme.fg_dim, theme.surface)
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Checkboxes
    local hud_items = {
        {key = "show_clock",    label = "Clock (day + time)"},
        {key = "show_storage",  label = "Storage capacity"},
        {key = "show_fuel",     label = "Fuel level"},
        {key = "show_smelting", label = "Smelting status"},
        {key = "show_mining",   label = "Mining status"},
        {key = "show_projects", label = "Active project"},
        {key = "show_alerts",   label = "Recent alerts"},
    }

    hits.hud_toggles = {}
    for _, item in ipairs(hud_items) do
        local on = ar.hud[item.key]
        local check = on and "[\4]" or "[ ]"
        local check_col = on and theme.success or theme.fg_dim
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, check, check_col, theme.surface)
        draw.put(buf, x + 5, y, item.label, theme.fg, theme.surface)
        table.insert(hits.hud_toggles, {
            x = (x + 1) - hits.ox, y = y - hits.oy, w = w - 2, h = 1,
            key = item.key,
        })
        y = y + 1
    end
end

-- ========================================
-- Render: World Config (Tab 2)
-- ========================================
local function render_world_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ar = ctx.state.ar

    draw.put(buf, x + 1, y, "3D WORLD MARKERS", theme.fg_dim, theme.surface)
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    local world_items = {
        {key = "show_mine_entrance", label = "Mine entrance marker"},
        {key = "show_turtles",       label = "Turtle locations"},
        {key = "show_pois",          label = "Points of interest"},
        {key = "show_project_blocks", label = "Project blocks (experimental)"},
    }

    hits.world_toggles = {}
    for _, item in ipairs(world_items) do
        local on = ar.world[item.key]
        local check = on and "[\4]" or "[ ]"
        local check_col = on and theme.success or theme.fg_dim
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, check, check_col, theme.surface)
        draw.put(buf, x + 5, y, item.label, theme.fg, theme.surface)
        table.insert(hits.world_toggles, {
            x = (x + 1) - hits.ox, y = y - hits.oy, w = w - 2, h = 1,
            key = item.key,
        })
        y = y + 1
    end

    -- POI section
    y = y + 1
    draw.put(buf, x + 1, y, "POINTS OF INTEREST", theme.fg_dim, theme.surface)
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    hits.poi_dels = {}
    if #ar.pois == 0 then
        draw.put(buf, x + 1, y, "No POIs defined", theme.fg_dim, theme.surface)
        y = y + 1
    else
        for i, poi in ipairs(ar.pois) do
            draw.fill(buf, y, x + w, theme.surface)
            local coords = string.format("(%d,%d,%d)", poi.x, poi.y, poi.z)
            local name = poi.name
            if #name > w - #coords - 10 then
                name = name:sub(1, w - #coords - 13) .. "..."
            end
            draw.put(buf, x + 1, y, name, theme.fg, theme.surface)
            draw.put(buf, x + w - #coords - 7, y, coords, theme.fg_dim, theme.surface)
            draw.button(buf, x + w - 5, y, 5, 1, "DEL", theme.danger, theme.btn_text, true)
            table.insert(hits.poi_dels, {
                x = (x + w - 5) - hits.ox, y = y - hits.oy, w = 5, h = 1, idx = i,
            })
            y = y + 1
        end
    end

    -- Add button
    draw.button(buf, x + 1, y + 1, 9, 1, "ADD POI", theme.success, theme.btn_text, true)
    hits.btn_add_poi = {x = (x + 1) - hits.ox, y = (y + 1) - hits.oy, w = 9, h = 1}
end

-- ========================================
-- Render: Alerts (Tab 3)
-- ========================================
local function render_alerts_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ar = ctx.state.ar

    -- Header row
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, string.format("Unread: %d  Total: %d", ar.alert_count, #ar.alerts),
        theme.fg, theme.surface2)
    draw.button(buf, x + w - 11, y, 10, 1, "CLEAR ALL", theme.accent, theme.btn_text, ar.alert_count > 0)
    hits.btn_clear = {x = (x + w - 11) - hits.ox, y = y - hits.oy, w = 10, h = 1}
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Scrollable alert list
    local list_h = h - 3
    local max_scroll = math.max(0, #ar.alerts - list_h)
    hits.max_scroll = max_scroll

    if #ar.alerts == 0 then
        draw.put(buf, x + 1, y + 2, "No alerts yet", theme.fg_dim, theme.surface)
        return
    end

    for i = 1 + scroll, math.min(#ar.alerts, scroll + list_h) do
        local alert = ar.alerts[i]
        local bg = alert.read and theme.surface or theme.surface2
        draw.fill(buf, y, x + w, bg)

        -- Level indicator
        local lvl_col = alert.level == "critical" and theme.danger
            or alert.level == "warning" and theme.warning
            or theme.accent
        local lvl_icon = alert.level == "critical" and "!!"
            or alert.level == "warning" and " !" or " >"
        draw.put(buf, x + 1, y, lvl_icon, lvl_col, bg)

        -- Message (truncated)
        local msg = alert.msg
        local max_msg = w - 16
        if #msg > max_msg then msg = msg:sub(1, max_msg - 3) .. "..." end
        draw.put(buf, x + 4, y, msg, theme.fg, bg)

        -- Time ago
        draw.put(buf, x + w - 6, y, time_ago(alert.time), theme.fg_dim, bg)

        y = y + 1
    end

    -- Scroll indicators
    if scroll > 0 then
        hits.scroll_up = {x = (x + w - 2) - hits.ox, y = (ctx.content_y + 8) - hits.oy, w = 1, h = 1}
    end
    if scroll < max_scroll then
        hits.scroll_down = {x = (x + w - 2) - hits.ox, y = (ctx.content_y + 7 + list_h) - hits.oy, w = 1, h = 1}
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

    hits = {}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Header
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.ar
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data then icon_lib.draw(buf, icon_data, x + 1, y) end
    draw.put(buf, x + 9, y, "AR GOGGLES", theme.fg, theme.surface2)
    draw.put(buf, x + 9, y + 1, "Augmented reality HUD", theme.fg_dim, theme.surface2)

    -- Connection indicator in header
    local ar = ctx.state.ar
    local conn_lbl = ar.connected and "Connected" or "Disconnected"
    local conn_col = ar.connected and theme.success or theme.danger
    draw.put(buf, x + w - #conn_lbl - 1, y, conn_lbl, conn_col, theme.surface2)
    y = y + 4

    -- Tab bar
    draw_tabs(buf, x, y, w, draw, theme)
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    local content_h = h - 6
    if tab == 1 then
        render_hud_tab(ctx, buf, x, y, w, content_h)
    elseif tab == 2 then
        render_world_tab(ctx, buf, x, y, w, content_h)
    elseif tab == 3 then
        render_alerts_tab(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local ar = ctx.state.ar
    local utils = ctx.utils
    local draw = ctx.draw

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3] - 1, ev[4]

            -- Tab clicks
            for i = 1, 3 do
                if hits["tab_" .. i] and draw.hit_test(hits["tab_" .. i], tx, ty) then
                    tab = i
                    scroll = 0
                end
            end

            -- Scroll
            if hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                if scroll > 0 then scroll = scroll - 1 end
            elseif hits.scroll_down and draw.hit_test(hits.scroll_down, tx, ty) then
                if scroll < (hits.max_scroll or 0) then scroll = scroll + 1 end
            end

            if tab == 1 then
                -- Master toggle
                if hits.master_toggle and draw.hit_test(hits.master_toggle, tx, ty) then
                    if ar.set_enabled then ar.set_enabled(not ar.enabled) end
                end

                -- HUD section toggles
                for _, toggle in ipairs(hits.hud_toggles or {}) do
                    if draw.hit_test(toggle, tx, ty) then
                        if ar.toggle_hud then ar.toggle_hud(toggle.key) end
                    end
                end

            elseif tab == 2 then
                -- World toggles
                for _, toggle in ipairs(hits.world_toggles or {}) do
                    if draw.hit_test(toggle, tx, ty) then
                        if ar.toggle_world then ar.toggle_world(toggle.key) end
                    end
                end

                -- POI delete buttons
                for _, del in ipairs(hits.poi_dels or {}) do
                    if draw.hit_test(del, tx, ty) then
                        if ar.remove_poi then ar.remove_poi(del.idx) end
                    end
                end

                -- Add POI button
                if hits.btn_add_poi and draw.hit_test(hits.btn_add_poi, tx, ty) then
                    local name = utils.pc_input("ADD POI", "Point of interest name:")
                    if name and #name > 0 then
                        local xs = utils.pc_input("POI X", "X coordinate:", "0")
                        local ys = utils.pc_input("POI Y", "Y coordinate:", "64")
                        local zs = utils.pc_input("POI Z", "Z coordinate:", "0")
                        local px, py, pz = tonumber(xs), tonumber(ys), tonumber(zs)
                        if px and py and pz and ar.add_poi then
                            ar.add_poi(name, px, py, pz)
                        end
                    end
                end

            elseif tab == 3 then
                -- Clear all button
                if hits.btn_clear and draw.hit_test(hits.btn_clear, tx, ty) then
                    if ar.clear_alerts then ar.clear_alerts() end
                end
            end

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if dir == 1 and scroll < (hits.max_scroll or 0) then
                scroll = scroll + 1
            elseif dir == -1 and scroll > 0 then
                scroll = scroll - 1
            end

        elseif ev[1] == "key" then
            if ev[2] == keys.tab then
                tab = (tab % 3) + 1
                scroll = 0
            end
        end
    end
end

return app
