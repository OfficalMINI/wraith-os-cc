-- =============================================
-- WRAITH OS - MASTERMINE APP
-- =============================================
-- Mining operation monitor: dashboard + live mine map.

local app = {
    id = "mastermine",
    name = "MasterMine",
    icon = "mastermine",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1  -- 1=dashboard, 2=map
local TAB_COUNT = 2
local scroll = 0
local hits = {}

-- Map state
local map_view = nil  -- nil=map, "turtle"=turtle viewer, "menu"=menu
local viewer_ids = {}
local viewer_sel = 1

-- ========================================
-- Dashboard rendering
-- ========================================
local function render_dashboard(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local mm = ctx.state.mastermine

    -- Stats row
    draw.fill(buf, y, x + w, theme.surface)
    local total, active, parked, mining = 0, 0, 0, 0
    for _, t in pairs(mm.turtles) do
        total = total + 1
        if t.state == "mine" or t.state == "trip" then mining = mining + 1
        elseif t.state == "park" then parked = parked + 1
        end
        if t.state and t.state ~= "park" and t.state ~= "halt" then active = active + 1 end
    end
    draw.put(buf, x + 1, y, string.format("Turtles: %d", total), theme.fg, theme.surface)
    draw.put(buf, x + 16, y, string.format("Active: %d", active), theme.success, theme.surface)
    draw.put(buf, x + 28, y, string.format("Mining: %d", mining), theme.accent, theme.surface)
    draw.put(buf, x + 40, y, string.format("Idle: %d", parked), theme.fg_dim, theme.surface)
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Controls row
    draw.fill(buf, y, x + w, theme.surface2)
    local on = mm.mining_on
    draw.button(buf, x + 1, y, 8, 1, on and "STOP" or "START", on and theme.danger or theme.success, theme.btn_text, mm.hub_connected)
    hits.start_btn = {x = 2, y = y - hits.oy + 1, w = 8, h = 1}
    draw.button(buf, x + 10, y, 10, 1, "RECALL ALL", theme.warning, theme.btn_text, mm.hub_connected)
    hits.recall_btn = {x = 11, y = y - hits.oy + 1, w = 10, h = 1}
    draw.button(buf, x + 21, y, 7, 1, "SYNC", theme.accent, theme.btn_text, mm.hub_connected)
    hits.sync_btn = {x = 22, y = y - hits.oy + 1, w = 7, h = 1}
    draw.button(buf, x + 29, y, 7, 1, "RESET", theme.info, theme.btn_text, mm.hub_connected)
    hits.reset_btn = {x = 30, y = y - hits.oy + 1, w = 7, h = 1}

    -- Connection status
    local conn_lbl = mm.hub_connected and string.format("Hub #%d", mm.hub_id or 0) or "Disconnected"
    local conn_col = mm.hub_connected and theme.success or theme.danger
    draw.put(buf, x + w - #conn_lbl - 1, y, conn_lbl, conn_col, theme.surface2)
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Mine levels display
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "MINE LEVELS", theme.accent, theme.surface)
    local mode_lbl = mm.auto_mode and "AUTO" or "MANUAL"
    draw.put(buf, x + 14, y, mode_lbl, mm.auto_mode and theme.success or theme.warning, theme.surface)
    y = y + 1

    if #mm.mine_levels > 0 then
        local max_cols = math.floor(w / 12)
        local col = 0
        for _, lv in ipairs(mm.mine_levels) do
            local lx = x + 1 + col * 12
            draw.fill(buf, y, x + w, theme.surface)
            local lbl = string.format("Y=%d %d%%", lv.level, math.floor(lv.chance * 100))
            draw.put(buf, lx, y, lbl, theme.fg, theme.surface)
            col = col + 1
            if col >= max_cols then
                col = 0
                y = y + 1
            end
        end
        if col > 0 then y = y + 1 end
    else
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No levels configured", theme.fg_dim, theme.surface)
        y = y + 1
    end

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Turtle list header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "ID", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 7, y, "TYPE", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 15, y, "STATE", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 24, y, "FUEL", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 33, y, "ITEMS", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 40, y, "LOCATION", theme.fg_dim, theme.surface2)
    y = y + 1

    -- Sort turtles by ID
    local sorted = {}
    for tid, t in pairs(mm.turtles) do
        t._id = tid
        table.insert(sorted, t)
    end
    table.sort(sorted, function(a, b) return (tonumber(a._id) or 0) < (tonumber(b._id) or 0) end)

    local area_h = h - (y - ctx.content_y) - 1
    if area_h < 1 then area_h = 1 end
    local max_scroll = math.max(0, #sorted - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.turtle_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)
        if idx <= #sorted then
            local t = sorted[idx]
            local tid = t._id
            local timeout = mm.hub_config and mm.hub_config.turtle_timeout or 5
            local lost = not t.state

            draw.put(buf, x + 1, y, string.format("#%d", tid), theme.accent, rbg)
            draw.put(buf, x + 7, y, (t.turtle_type or "?"):sub(1, 6), theme.fg_dim, rbg)

            local state_col = theme.fg
            local st = t.state or "?"
            if st == "mine" then state_col = theme.success
            elseif st == "trip" then state_col = theme.info
            elseif st == "halt" then state_col = theme.danger
            elseif st == "idle" then state_col = theme.warning
            elseif st == "park" then state_col = theme.fg_dim
            elseif st == "wait" then state_col = theme.accent
            elseif st == "pair" then state_col = theme.subtle
            end
            draw.put(buf, x + 15, y, st:sub(1, 7), state_col, rbg)

            local fuel = t.fuel_level
            if fuel == "unlimited" then
                draw.put(buf, x + 24, y, "INF", theme.success, rbg)
            elseif type(fuel) == "number" then
                local fc = fuel < 100 and theme.danger or (fuel < 500 and theme.warning or theme.success)
                draw.put(buf, x + 24, y, tostring(fuel), fc, rbg)
            end

            draw.put(buf, x + 33, y, tostring(t.item_count or 0), theme.fg, rbg)

            if t.location then
                local loc = string.format("%d,%d,%d", t.location.x or 0, t.location.y or 0, t.location.z or 0)
                if #loc > w - 41 then loc = loc:sub(1, w - 43) .. ".." end
                draw.put(buf, x + 40, y, loc, theme.fg_dim, rbg)
            end

            table.insert(hits.turtle_rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, id = tid})
        end
        y = y + 1
    end

    -- Scroll bar
    draw.fill(buf, y, x + w, theme.surface2)
    if #sorted > area_h then
        draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
        hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}
        local info = string.format("%d-%d of %d", scroll + 1, math.min(scroll + area_h, #sorted), #sorted)
        draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)
        draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_scroll)
        hits.scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    else
        draw.center(buf, string.format("%d turtles", #sorted), y, x + w, theme.fg_dim, theme.surface2)
    end
end

-- ========================================
-- Map rendering (ported from monitor.lua)
-- ========================================
local function world_to_pixel(wx, wz, center_x, center_z, zoom_level, vw, vh)
    local factor = math.pow(2, zoom_level)
    local px = math.floor((wx - center_x) / factor) + math.floor(vw / 2)
    local pz = math.floor((wz - center_z) / factor) + math.floor(vh / 2)
    return px, pz
end

local function pixel_to_world(px, pz, center_x, center_z, zoom_level, vw, vh)
    local factor = math.pow(2, zoom_level)
    local wx = (px - math.floor(vw / 2)) * factor + center_x
    local wz = (pz - math.floor(vh / 2)) * factor + center_z
    return wx, wz
end

local function render_map(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local mm = ctx.state.mastermine

    if not mm.hub_config or not mm.hub_config.mine_entrance then
        draw.fillRect(buf, x, y, w, h, theme.surface)
        local msg = mm.hub_connected and "Waiting for hub data..." or "Hub not connected"
        draw.center(buf, msg, y + math.floor(h / 2), x + w, theme.fg_dim, theme.surface)
        return
    end

    local hcfg = mm.hub_config
    local mine_enter = hcfg.mine_entrance
    local grid_width = hcfg.grid_width or 8

    -- Map view state
    if not mm.map_location then
        mm.map_location = {x = mine_enter.x, z = mine_enter.z}
    end

    local center_x = mm.map_location.x
    local center_z = mm.map_location.z
    local zoom = mm.map_zoom or 0
    local factor = math.pow(2, zoom)

    -- Available viewport (leave 1 row for controls at bottom)
    local vw = w
    local vh = h - 1

    -- Calculate visible world range
    local min_wx = center_x - math.floor(vw * factor / 2)
    local min_wz = center_z - math.floor(vh * factor / 2)

    -- Clear map area
    draw.fillRect(buf, x, y, w, vh, colors.black)

    -- Get current mine level data
    local level_idx = mm.map_level_idx or 1
    if level_idx < 1 then level_idx = 1 end
    if #mm.mine_levels > 0 and level_idx > #mm.mine_levels then
        level_idx = #mm.mine_levels
    end
    mm.map_level_idx = level_idx

    local current_level = nil
    local level_y = 0
    if #mm.mine_levels > 0 then
        level_y = mm.mine_levels[level_idx].level
        -- mine_data keys might be numbers or strings
        current_level = mm.mine_data[level_y] or mm.mine_data[tostring(level_y)]
    end

    hits.map_turtles = {}

    if current_level then
        local mine_enter_z = mine_enter.z

        -- Draw mining strips
        for strip_key, strip in pairs(current_level) do
            if strip_key ~= "y" and strip_key ~= "main_shaft" then
                local strip_x = tonumber(strip_key)
                if strip_x then
                    -- Draw strip column (vertical line at strip_x)
                    for wz = min_wz, min_wz + vh * factor, factor do
                        local px, pz = world_to_pixel(strip_x, wz, center_x, center_z, zoom, vw, vh)
                        if px >= 1 and px <= vw and pz >= 1 and pz <= vh then
                            local mined = false
                            if wz > mine_enter_z then
                                if strip.south and strip.south.z and strip.south.z > wz then
                                    mined = true
                                end
                            else
                                if strip.north and strip.north.z and strip.north.z < wz then
                                    mined = true
                                end
                            end
                            draw.put(buf, x + px - 1, y + pz - 1, " ", nil, mined and colors.lightGray or colors.gray)
                        end
                    end
                end
            end
        end

        -- Draw main shaft (horizontal line along mine_enter z)
        if current_level.main_shaft then
            local ms = current_level.main_shaft
            local ms_west_x = ms.west and ms.west.x or mine_enter.x
            local ms_east_x = ms.east and ms.east.x or mine_enter.x

            for wx = min_wx, min_wx + vw * factor, factor do
                local px, pz = world_to_pixel(wx, mine_enter_z, center_x, center_z, zoom, vw, vh)
                if px >= 1 and px <= vw and pz >= 1 and pz <= vh then
                    local in_shaft = wx >= ms_west_x and wx <= ms_east_x
                    draw.put(buf, x + px - 1, y + pz - 1, " ", nil, in_shaft and colors.lightGray or colors.gray)
                end
            end
        end

        -- Draw strip endpoints with turtles (green)
        for strip_key, strip in pairs(current_level) do
            if strip_key ~= "y" and strip_key ~= "main_shaft" then
                for _, dir in pairs({"north", "south"}) do
                    if strip[dir] and strip[dir].turtles then
                        local sx, sz = strip[dir].x, strip[dir].z
                        if sx and sz then
                            local px, pz = world_to_pixel(sx, sz, center_x, center_z, zoom, vw, vh)
                            if px >= 1 and px <= vw and pz >= 1 and pz <= vh then
                                draw.put(buf, x + px - 1, y + pz - 1, " ", nil, colors.lime)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Draw mine entrance marker
    if mine_enter then
        local px, pz = world_to_pixel(mine_enter.x, mine_enter.z, center_x, center_z, zoom, vw, vh)
        if px >= 1 and px <= vw and pz >= 1 and pz <= vh then
            draw.put(buf, x + px - 1, y + pz - 1, "E", colors.white, colors.blue)
        end
    end

    -- Draw turtles
    local turtle_pixels = {}
    local timeout = hcfg.turtle_timeout or 5
    for tid, t in pairs(mm.turtles) do
        if t.location and t.location.x then
            local px, pz = world_to_pixel(t.location.x, t.location.z, center_x, center_z, zoom, vw, vh)
            if px >= 1 and px <= vw and pz >= 1 and pz <= vh then
                local pkey = px .. "," .. pz
                local tcol = colors.yellow
                if not turtle_pixels[pkey] then
                    turtle_pixels[pkey] = {tid}
                    draw.put(buf, x + px - 1, y + pz - 1, "-", colors.black, tcol)
                else
                    table.insert(turtle_pixels[pkey], tid)
                    local cnt = #turtle_pixels[pkey]
                    local ch = cnt <= 9 and tostring(cnt) or "+"
                    draw.put(buf, x + px - 1, y + pz - 1, ch, colors.black, tcol)
                end
                hits.map_turtles[pkey] = {x = px, y = pz - 1 + (y - hits.oy), w = 1, h = 1, ids = turtle_pixels[pkey]}
            end
        end
    end

    -- Control bar at bottom of map
    local cy = y + vh
    draw.fill(buf, cy, x + w, theme.surface2)

    -- Level indicator
    local lv_lbl = string.format("Y=%d", level_y)
    draw.put(buf, x + 1, cy, "-", theme.accent, theme.surface2)
    hits.map_level_down = {x = 2, y = cy - hits.oy + 1, w = 1, h = 1}
    draw.put(buf, x + 2, cy, lv_lbl, theme.fg, theme.surface2)
    draw.put(buf, x + 2 + #lv_lbl, cy, "+", theme.accent, theme.surface2)
    hits.map_level_up = {x = 3 + #lv_lbl, y = cy - hits.oy + 1, w = 1, h = 1}

    -- Zoom indicator
    local zm_lbl = string.format("Z:%d", zoom)
    local zx = x + 2 + #lv_lbl + 3
    draw.put(buf, zx, cy, "-", theme.accent, theme.surface2)
    hits.map_zoom_out = {x = zx - x + 1, y = cy - hits.oy + 1, w = 1, h = 1}
    draw.put(buf, zx + 1, cy, zm_lbl, theme.fg, theme.surface2)
    draw.put(buf, zx + 1 + #zm_lbl, cy, "+", theme.accent, theme.surface2)
    hits.map_zoom_in = {x = zx + 1 + #zm_lbl - x + 1, y = cy - hits.oy + 1, w = 1, h = 1}

    -- Pan buttons
    draw.put(buf, x + w - 10, cy, "N", theme.accent, theme.surface2)
    hits.map_n = {x = w - 10 + 1, y = cy - hits.oy + 1, w = 1, h = 1}
    draw.put(buf, x + w - 8, cy, "S", theme.accent, theme.surface2)
    hits.map_s = {x = w - 8 + 1, y = cy - hits.oy + 1, w = 1, h = 1}
    draw.put(buf, x + w - 6, cy, "W", theme.accent, theme.surface2)
    hits.map_w = {x = w - 6 + 1, y = cy - hits.oy + 1, w = 1, h = 1}
    draw.put(buf, x + w - 4, cy, "E", theme.accent, theme.surface2)
    hits.map_e = {x = w - 4 + 1, y = cy - hits.oy + 1, w = 1, h = 1}

    -- Center button
    draw.put(buf, x + w - 2, cy, "C", theme.warning, theme.surface2)
    hits.map_center = {x = w - 2 + 1, y = cy - hits.oy + 1, w = 1, h = 1}

    -- Coords
    local coord_lbl = string.format("X:%d Z:%d", center_x, center_z)
    local coord_x = zx + 2 + #zm_lbl + 2
    draw.put(buf, coord_x, cy, coord_lbl, theme.fg_dim, theme.surface2)
end

-- ========================================
-- Turtle detail popup
-- ========================================
local function render_turtle_viewer(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local mm = ctx.state.mastermine

    draw.fillRect(buf, x, y, w, h, colors.black)

    if #viewer_ids == 0 then
        draw.center(buf, "No turtle selected", y + math.floor(h / 2), x + w, theme.fg_dim, colors.black)
        return
    end

    if viewer_sel < 1 then viewer_sel = 1 end
    if viewer_sel > #viewer_ids then viewer_sel = #viewer_ids end

    local tid = viewer_ids[viewer_sel]
    local t = mm.turtles[tid] or mm.turtles[tostring(tid)]
    if not t then
        draw.center(buf, "Turtle not found", y + math.floor(h / 2), x + w, theme.danger, colors.black)
        return
    end

    local bg = colors.black

    -- Close button
    draw.put(buf, x, y, "X", theme.bg, theme.danger)
    hits.viewer_close = {x = 1, y = y - hits.oy + 1, w = 1, h = 1}

    -- Nav arrows
    if viewer_sel > 1 then
        draw.put(buf, x + 2, y, "<", theme.bg, theme.success)
    else
        draw.put(buf, x + 2, y, "<", theme.fg_dim, colors.gray)
    end
    hits.viewer_prev = {x = 3, y = y - hits.oy + 1, w = 1, h = 1}

    if viewer_sel < #viewer_ids then
        draw.put(buf, x + 4, y, ">", theme.bg, theme.success)
    else
        draw.put(buf, x + 4, y, ">", theme.fg_dim, colors.gray)
    end
    hits.viewer_next = {x = 5, y = y - hits.oy + 1, w = 1, h = 1}

    -- Turtle ID
    draw.put(buf, x + 7, y, string.format("TURTLE #%d", tid), theme.accent, bg)
    draw.put(buf, x + w - 10, y, string.format("%d/%d", viewer_sel, #viewer_ids), theme.fg_dim, bg)

    -- Turtle face (simplified)
    local fy = y + 2
    draw.fillRect(buf, x + 2, fy, 7, 3, colors.yellow)

    -- Peripheral indicators
    local pr = t.peripheral_right
    local pl = t.peripheral_left
    if pr == "modem" then draw.fillRect(buf, x + 1, fy, 1, 3, colors.lightGray)
    elseif pr == "pick" then
        draw.put(buf, x + 1, fy, " ", nil, colors.cyan)
        draw.put(buf, x + 1, fy + 1, " ", nil, colors.cyan)
        draw.put(buf, x + 1, fy + 2, " ", nil, colors.brown)
    elseif pr == "chunky" then
        draw.put(buf, x + 1, fy, " ", nil, colors.white)
        draw.put(buf, x + 1, fy + 1, " ", nil, colors.red)
        draw.put(buf, x + 1, fy + 2, " ", nil, colors.white)
    end
    if pl == "modem" then draw.fillRect(buf, x + 9, fy, 1, 3, colors.lightGray)
    elseif pl == "pick" then
        draw.put(buf, x + 9, fy, " ", nil, colors.cyan)
        draw.put(buf, x + 9, fy + 1, " ", nil, colors.cyan)
        draw.put(buf, x + 9, fy + 2, " ", nil, colors.brown)
    elseif pl == "chunky" then
        draw.put(buf, x + 9, fy, " ", nil, colors.white)
        draw.put(buf, x + 9, fy + 1, " ", nil, colors.red)
        draw.put(buf, x + 9, fy + 2, " ", nil, colors.white)
    end

    -- Data
    local dx = x + 12
    local dy = y + 2
    draw.put(buf, dx, dy, "State: ", theme.fg, bg)
    draw.put(buf, dx + 7, dy, t.state or "?", theme.success, bg)
    dy = dy + 1
    if t.location then
        draw.put(buf, dx, dy, string.format("X: %d", t.location.x or 0), theme.fg, bg)
        dy = dy + 1
        draw.put(buf, dx, dy, string.format("Y: %d", t.location.y or 0), theme.fg, bg)
        dy = dy + 1
        draw.put(buf, dx, dy, string.format("Z: %d", t.location.z or 0), theme.fg, bg)
        dy = dy + 1
    end
    draw.put(buf, dx, dy, "Facing: " .. (t.orientation or "?"), theme.fg, bg)
    dy = dy + 1
    local fuel_str = t.fuel_level == "unlimited" and "INF" or tostring(t.fuel_level or "?")
    draw.put(buf, dx, dy, "Fuel: " .. fuel_str, theme.fg, bg)
    dy = dy + 1
    draw.put(buf, dx, dy, "Items: " .. tostring(t.item_count or 0), theme.fg, bg)

    -- Action buttons
    local by = y + 2
    local bx = x + 30
    if bx + 12 > x + w then bx = x + w - 14 end

    local actions = {
        {label = "RETURN", cmd = "return " .. tid},
        {label = "HALT",   cmd = "halt " .. tid},
        {label = "CLEAR",  cmd = "clear " .. tid},
        {label = "RESET",  cmd = "reset " .. tid},
        {label = "REBOOT", cmd = "reboot " .. tid},
        {label = "UPDATE", cmd = "update " .. tid},
    }
    hits.viewer_actions = {}
    for i, act in ipairs(actions) do
        draw.button(buf, bx, by, 10, 1, act.label, theme.accent, theme.btn_text, mm.hub_connected)
        hits.viewer_actions[i] = {x = bx - x + 1, y = by - hits.oy + 1, w = 10, h = 1, cmd = act.cmd}
        by = by + 1
    end

    -- Movement controls
    local my = y + h - 4
    draw.put(buf, x + 2, my, "^FWD", theme.fg, theme.surface2)
    hits.move_fwd = {x = 3, y = my - hits.oy + 1, w = 4, h = 1, cmd = "turtle " .. tid .. " go forward"}
    draw.put(buf, x + 2, my + 2, "vBCK", theme.fg, theme.surface2)
    hits.move_bck = {x = 3, y = my + 2 - hits.oy + 1, w = 4, h = 1, cmd = "turtle " .. tid .. " go back"}
    draw.put(buf, x + 8, my, "^UP", theme.fg, theme.surface2)
    hits.move_up = {x = 9, y = my - hits.oy + 1, w = 3, h = 1, cmd = "turtle " .. tid .. " go up"}
    draw.put(buf, x + 8, my + 2, "vDN", theme.fg, theme.surface2)
    hits.move_dn = {x = 9, y = my + 2 - hits.oy + 1, w = 3, h = 1, cmd = "turtle " .. tid .. " go down"}
    draw.put(buf, x + 14, my + 1, "<L", theme.fg, theme.surface2)
    hits.move_l = {x = 15, y = my + 1 - hits.oy + 1, w = 2, h = 1, cmd = "turtle " .. tid .. " go left"}
    draw.put(buf, x + 18, my + 1, "R>", theme.fg, theme.surface2)
    hits.move_r = {x = 19, y = my + 1 - hits.oy + 1, w = 2, h = 1, cmd = "turtle " .. tid .. " go right"}

    -- Dig controls (mining only)
    if t.turtle_type == "mining" then
        draw.put(buf, x + 23, my, "^DIG", theme.success, theme.surface2)
        hits.dig_up = {x = 24, y = my - hits.oy + 1, w = 4, h = 1, cmd = "turtle " .. tid .. " digblock up"}
        draw.put(buf, x + 23, my + 1, "*DIG", theme.success, theme.surface2)
        hits.dig_fwd = {x = 24, y = my + 1 - hits.oy + 1, w = 4, h = 1, cmd = "turtle " .. tid .. " digblock forward"}
        draw.put(buf, x + 23, my + 2, "vDIG", theme.success, theme.surface2)
        hits.dig_dn = {x = 24, y = my + 2 - hits.oy + 1, w = 4, h = 1, cmd = "turtle " .. tid .. " digblock down"}
    end

    -- Find button (jump to turtle on map)
    draw.button(buf, x + w - 8, y + h - 2, 7, 1, "FIND", theme.info, theme.btn_text, true)
    hits.viewer_find = {x = w - 8 + 1, y = y + h - 2 - hits.oy + 1, w = 7, h = 1, tid = tid}
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
    local mm = ctx.state.mastermine

    hits = {btns = {}}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- ========================================
    -- Header: Icon + hub status
    -- ========================================
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.mastermine

    for r = 0, 3 do
        draw.fill(buf, y + r, x + w, theme.surface2)
    end

    if icon_data and icon_lib then
        icon_lib.draw(buf, icon_data, x + 2, y)
    end

    local sx = x + 11
    draw.put(buf, sx, y, "MASTERMINE", theme.accent, theme.surface2)

    -- Hub connection status
    local conn = mm.hub_connected
    local conn_str = conn and string.format("Hub #%d Connected", mm.hub_id or 0) or "Hub Disconnected"
    draw.put(buf, sx, y + 1, conn_str, conn and theme.success or theme.danger, theme.surface2)

    -- Mining status
    local on = mm.mining_on
    draw.put(buf, sx, y + 2, "Mining: ", theme.fg_dim, theme.surface2)
    draw.put(buf, sx + 8, y + 2, on and "ON" or "OFF", on and theme.success or theme.danger, theme.surface2)

    -- Turtle count + debug
    local tc = 0
    for _ in pairs(mm.turtles) do tc = tc + 1 end
    local net = ctx.state.network
    local modem_str = net.modem_side or "NO MODEM"
    local hub_str = mm.hub_id and ("#" .. mm.hub_id) or "none"
    local ping_str = tostring(mm.ping_count or "?")
    local ev_str = tostring(mm.last_ev or "?")
    draw.put(buf, sx, y + 3, string.format("mdm:%s hub:%s p:%s ev:%s", modem_str, hub_str, ping_str, ev_str), theme.fg_dim, theme.surface2)

    y = y + 4

    -- ========================================
    -- Tab bar (only if not in viewer mode)
    -- ========================================
    if map_view ~= "turtle" then
        draw.fill(buf, y, x + w, theme.surface)
        local tab_labels = {"DASHBOARD", "MAP"}
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
            local lbl = utils.pad_center(tab_labels[ti], tw)
            buf.write(lbl)
            hits.tabs[ti] = {x = tx - hits.ox + 1, y = y - hits.oy + 1, w = tw, h = 1}
        end
        y = y + 1
        draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
        y = y + 1
    else
        y = y  -- no tab bar in viewer mode
    end

    -- ========================================
    -- Content area
    -- ========================================
    local content_h = h - (y - ctx.content_y)

    if map_view == "turtle" then
        render_turtle_viewer(ctx, buf, x, y, w, content_h)
    elseif tab == 1 then
        render_dashboard(ctx, buf, x, y, w, content_h)
    elseif tab == 2 then
        render_map(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event handler
-- ========================================
function app.main(ctx)
    local mm = ctx.state.mastermine
    local draw = ctx.draw

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            -- ev[3] is win.x-relative (from to_local), but hit areas are
            -- content_x-relative (content_x = win.x + 1 for the border).
            -- Subtract 1 from tx to align coordinate systems.
            local tx, ty = ev[3] - 1, ev[4]

            -- Turtle viewer mode
            if map_view == "turtle" then
                if hits.viewer_close and draw.hit_test(hits.viewer_close, tx, ty) then
                    map_view = nil
                elseif hits.viewer_prev and draw.hit_test(hits.viewer_prev, tx, ty) then
                    if viewer_sel > 1 then viewer_sel = viewer_sel - 1 end
                elseif hits.viewer_next and draw.hit_test(hits.viewer_next, tx, ty) then
                    if viewer_sel < #viewer_ids then viewer_sel = viewer_sel + 1 end
                elseif hits.viewer_find and draw.hit_test(hits.viewer_find, tx, ty) then
                    -- Jump to turtle on map
                    local tid = hits.viewer_find.tid
                    local t = mm.turtles[tid] or mm.turtles[tostring(tid)]
                    if t and t.location then
                        mm.map_location = {x = t.location.x, z = t.location.z}
                        mm.map_zoom = 0
                    end
                    map_view = nil
                    tab = 2
                else
                    -- Check action buttons
                    for _, act in ipairs(hits.viewer_actions or {}) do
                        if draw.hit_test(act, tx, ty) then
                            if mm.send_command then mm.send_command(act.cmd) end
                            break
                        end
                    end
                    -- Check movement buttons
                    for _, key in ipairs({"move_fwd", "move_bck", "move_up", "move_dn", "move_l", "move_r", "dig_up", "dig_fwd", "dig_dn"}) do
                        if hits[key] and draw.hit_test(hits[key], tx, ty) then
                            if mm.send_command then mm.send_command(hits[key].cmd) end
                            break
                        end
                    end
                end

            -- Tab clicks
            elseif hits.tabs then
                local tab_clicked = false
                for ti, area in ipairs(hits.tabs) do
                    if draw.hit_test(area, tx, ty) then
                        tab = ti
                        scroll = 0
                        tab_clicked = true
                        -- Request mine data when switching to map tab
                        if ti == 2 and mm.request_mine_data and mm.hub_connected then
                            mm.request_mine_data(nil)  -- request available levels
                            -- Request data for current level
                            if #mm.mine_levels > 0 then
                                local lvl = mm.mine_levels[mm.map_level_idx or 1]
                                if lvl then mm.request_mine_data(lvl.level) end
                            end
                        end
                        break
                    end
                end

                if not tab_clicked then
                    if tab == 1 then
                        -- Dashboard clicks
                        if hits.start_btn and draw.hit_test(hits.start_btn, tx, ty) then
                            if mm.send_command then
                                mm.send_command(mm.mining_on and "off" or "on")
                            end
                        elseif hits.recall_btn and draw.hit_test(hits.recall_btn, tx, ty) then
                            if mm.send_command then mm.send_command("return *") end
                        elseif hits.sync_btn and draw.hit_test(hits.sync_btn, tx, ty) then
                            if mm.force_sync then mm.force_sync() end
                        elseif hits.reset_btn and draw.hit_test(hits.reset_btn, tx, ty) then
                            if mm.send_command then mm.send_command("reset *") end
                        elseif hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                            if scroll > 0 then scroll = scroll - 1 end
                        elseif hits.scroll_down and draw.hit_test(hits.scroll_down, tx, ty) then
                            if scroll < (hits.max_scroll or 0) then scroll = scroll + 1 end
                        else
                            -- Turtle row click -> open viewer
                            for _, row in ipairs(hits.turtle_rows or {}) do
                                if draw.hit_test(row, tx, ty) then
                                    viewer_ids = {row.id}
                                    viewer_sel = 1
                                    map_view = "turtle"
                                    break
                                end
                            end
                        end

                    elseif tab == 2 then
                        -- Map clicks
                        if hits.map_n and draw.hit_test(hits.map_n, tx, ty) then
                            local f = math.pow(2, mm.map_zoom)
                            mm.map_location.z = mm.map_location.z - f * 4
                        elseif hits.map_s and draw.hit_test(hits.map_s, tx, ty) then
                            local f = math.pow(2, mm.map_zoom)
                            mm.map_location.z = mm.map_location.z + f * 4
                        elseif hits.map_w and draw.hit_test(hits.map_w, tx, ty) then
                            local f = math.pow(2, mm.map_zoom)
                            mm.map_location.x = mm.map_location.x - f * 4
                        elseif hits.map_e and draw.hit_test(hits.map_e, tx, ty) then
                            local f = math.pow(2, mm.map_zoom)
                            mm.map_location.x = mm.map_location.x + f * 4
                        elseif hits.map_zoom_in and draw.hit_test(hits.map_zoom_in, tx, ty) then
                            mm.map_zoom = math.max(0, mm.map_zoom - 1)
                        elseif hits.map_zoom_out and draw.hit_test(hits.map_zoom_out, tx, ty) then
                            mm.map_zoom = math.min(5, mm.map_zoom + 1)
                        elseif hits.map_level_up and draw.hit_test(hits.map_level_up, tx, ty) then
                            mm.map_level_idx = math.min((mm.map_level_idx or 1) + 1, math.max(1, #mm.mine_levels))
                            -- Request data for new level
                            if mm.request_mine_data and mm.hub_connected and #mm.mine_levels > 0 then
                                local lvl = mm.mine_levels[mm.map_level_idx]
                                if lvl then mm.request_mine_data(lvl.level) end
                            end
                        elseif hits.map_level_down and draw.hit_test(hits.map_level_down, tx, ty) then
                            mm.map_level_idx = math.max(1, (mm.map_level_idx or 1) - 1)
                            -- Request data for new level
                            if mm.request_mine_data and mm.hub_connected and #mm.mine_levels > 0 then
                                local lvl = mm.mine_levels[mm.map_level_idx]
                                if lvl then mm.request_mine_data(lvl.level) end
                            end
                        elseif hits.map_center and draw.hit_test(hits.map_center, tx, ty) then
                            if mm.hub_config and mm.hub_config.mine_entrance then
                                mm.map_location = {x = mm.hub_config.mine_entrance.x, z = mm.hub_config.mine_entrance.z}
                            end
                        else
                            -- Click on turtle pixel
                            for _, tp in pairs(hits.map_turtles or {}) do
                                if draw.hit_test(tp, tx, ty) then
                                    viewer_ids = tp.ids
                                    viewer_sel = 1
                                    map_view = "turtle"
                                    break
                                end
                            end
                        end
                    end
                end
            end

        elseif ev[1] == "mouse_scroll" then
            if tab == 1 and map_view ~= "turtle" then
                local dir = ev[2]
                local max_s = hits.max_scroll or 0
                scroll = math.max(0, math.min(max_s, scroll + dir))
            elseif tab == 2 and map_view ~= "turtle" then
                -- Scroll to zoom on map
                local dir = ev[2]
                if dir > 0 then
                    mm.map_zoom = math.min(5, mm.map_zoom + 1)
                else
                    mm.map_zoom = math.max(0, mm.map_zoom - 1)
                end
            end

        elseif ev[1] == "key" then
            if map_view == "turtle" then
                if ev[2] == keys.left and viewer_sel > 1 then
                    viewer_sel = viewer_sel - 1
                elseif ev[2] == keys.right and viewer_sel < #viewer_ids then
                    viewer_sel = viewer_sel + 1
                elseif ev[2] == keys.backspace or ev[2] == keys.x then
                    map_view = nil
                end
            elseif tab == 1 then
                local max_s = hits.max_scroll or 0
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
