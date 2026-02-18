-- =============================================
-- WRAITH OS - TRANSPORT APP
-- =============================================
-- Rail transport logistics: buffer chest config,
-- item allow list, per-station delivery/collection
-- schedules, station management.

local app = {
    id = "transport",
    name = "Transport",
    icon = "transport",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1
local TAB_COUNT = 4
local scroll = 0
local hits = {}

-- Sub-views
local detail_station = nil   -- station id for detail
local detail_scroll = 0
local edit_schedule_idx = nil -- schedule being edited
local edit_station_id = nil

-- Item picker
local picker_mode = nil      -- nil | "allow_item" | "schedule_item"
local picker_query = ""
local picker_scroll = 0
local picker_selected = nil
local picker_hits = {}

-- Period picker
local period_mode = false
local period_target_idx = nil

-- Buffer picker
local buffer_mode = false
local buffer_list = {}

-- Min-keep editor
local edit_minkeep_idx = nil

-- ========================================
-- Helpers
-- ========================================
local function format_period(seconds)
    if not seconds or seconds <= 0 then return "Manual" end
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

local function format_time_ago(epoch_ms)
    if not epoch_ms or epoch_ms == 0 then return "never" end
    local now = os.epoch("utc") / 1000
    local ago = now - epoch_ms
    if ago < 60 then return math.floor(ago) .. "s ago" end
    if ago < 3600 then return math.floor(ago / 60) .. "m ago" end
    return math.floor(ago / 3600) .. "h ago"
end

-- ========================================
-- Tab: Dashboard
-- ========================================
local function render_dashboard(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local tr = ctx.state.transport

    -- Stats
    local station_count, online_count = 0, 0
    for _, s in pairs(tr.stations) do
        station_count = station_count + 1
        if s.online then online_count = online_count + 1 end
    end

    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, string.format("Stations: %d/%d", online_count, station_count), theme.fg, theme.surface2)

    -- Buffer status
    local buf_lbl = tr.buffer_chest and tr.buffer_chest:sub(1, 20) or "NOT SET"
    local buf_col = tr.buffer_chest and theme.success or theme.danger
    draw.put(buf, x + 22, y, "Buffer: ", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 30, y, buf_lbl, buf_col, theme.surface2)
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Hub
    draw.fill(buf, y, x + w, theme.surface)
    if tr.hub_id and tr.stations[tr.hub_id] then
        local hub = tr.stations[tr.hub_id]
        draw.put(buf, x + 1, y, "\4 Hub: " .. hub.label, theme.accent, theme.surface)
        local st_lbl = hub.online and "ONLINE" or "OFFLINE"
        draw.put(buf, x + w - #st_lbl - 1, y, st_lbl, hub.online and theme.success or theme.danger, theme.surface)
    else
        draw.put(buf, x + 1, y, "No hub configured", theme.warning, theme.surface)
    end
    y = y + 1

    -- Fuel config
    draw.fill(buf, y, x + w, theme.surface)
    local fuel = tr.fuel_item or ctx.config.transport.fuel_item or "?"
    local fuel_ct = tr.fuel_per_trip or ctx.config.transport.fuel_per_trip or 8
    draw.put(buf, x + 1, y, string.format("Fuel: %dx %s", fuel_ct, utils.clean_name(fuel):sub(1, 20)),
        theme.fg_dim, theme.surface)
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Allow list summary
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("ALLOWED ITEMS: %d", #tr.allowed_items), theme.accent, theme.surface)
    y = y + 1

    for i, ai in ipairs(tr.allowed_items) do
        if y >= ctx.content_y + h - 6 then break end
        local bg = (i % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, bg)
        local stock = 0
        if ctx.state.storage.output_stock then
            stock = ctx.state.storage.output_stock[ai.item] or 0
        end
        local stock_col = stock > ai.min_keep and theme.success or (stock > 0 and theme.warning or theme.danger)
        draw.put(buf, x + 1, y, (ai.display_name or "?"):sub(1, 20), theme.fg, bg)
        draw.put(buf, x + 22, y, string.format("stock:%s keep:%s",
            utils.format_number(stock), utils.format_number(ai.min_keep)),
            stock_col, bg)
        y = y + 1
    end

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Recent trips
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "RECENT TRIPS", theme.accent, theme.surface)
    y = y + 1

    if #tr.last_trip_log > 0 then
        for i, trip in ipairs(tr.last_trip_log) do
            if y >= ctx.content_y + h then break end
            local bg = (i % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, bg)
            local icon = trip.type == "delivery" and "\26" or "\27"
            local col = trip.type == "delivery" and theme.success or theme.accent
            local info = string.format("%s %s %s  %s",
                icon, trip.type:sub(1,3):upper(), trip.station:sub(1, 16),
                format_time_ago(trip.time))
            draw.put(buf, x + 1, y, info:sub(1, w - 2), col, bg)
            y = y + 1
        end
    else
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No trips yet", theme.fg_dim, theme.surface)
        y = y + 1
    end

    while y < ctx.content_y + h do
        draw.fill(buf, y, x + w, theme.surface)
        y = y + 1
    end
end

-- ========================================
-- Tab: Items (Allow List)
-- ========================================
local function render_items(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local tr = ctx.state.transport

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "ITEM ALLOW LIST", theme.accent, theme.surface2)
    draw.button(buf, x + w - 6, y, 5, 1, " + ", theme.success, theme.btn_text, true)
    hits.add_item_btn = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "ITEM", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 22, y, "STOCK", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 32, y, "KEEP", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 42, y, "AVAIL", theme.fg_dim, theme.surface2)
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    local area_h = h - 4
    local max_scroll = math.max(0, #tr.allowed_items - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.item_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local bg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, bg)

        if idx <= #tr.allowed_items then
            local ai = tr.allowed_items[idx]
            local stock = 0
            if ctx.state.storage.output_stock then
                stock = ctx.state.storage.output_stock[ai.item] or 0
            end
            local avail = math.max(0, stock - ai.min_keep)
            local stock_col = stock > ai.min_keep and theme.success or (stock > 0 and theme.warning or theme.danger)

            draw.put(buf, x + 1, y, (ai.display_name or "?"):sub(1, 20), theme.fg, bg)
            draw.put(buf, x + 22, y, utils.format_number(stock), stock_col, bg)
            draw.put(buf, x + 32, y, utils.format_number(ai.min_keep), theme.fg_dim, bg)
            draw.put(buf, x + 42, y, utils.format_number(avail), avail > 0 and theme.success or theme.fg_dim, bg)

            -- Remove button
            draw.put(buf, x + w - 2, y, "X", theme.danger, bg)
            table.insert(hits.item_rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, idx = idx})
        end
        y = y + 1
    end

    -- Footer
    draw.fill(buf, y, x + w, theme.surface2)
    draw.center(buf, string.format("%d items", #tr.allowed_items), y, x + w, theme.fg_dim, theme.surface2)
end

-- ========================================
-- Tab: Stations (list + detail)
-- ========================================
local function render_station_detail(ctx, buf, x, y, w, h, station_id)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local tr = ctx.state.transport
    local s = tr.stations[station_id]

    if not s then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "Station not found", theme.danger, theme.surface)
        return
    end

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "X", theme.bg, theme.danger)
    hits.detail_close = {x = 2, y = y - hits.oy + 1, w = 1, h = 1}
    local prefix = s.is_hub and "\4 HUB: " or "  "
    draw.put(buf, x + 3, y, prefix .. s.label, theme.accent, theme.surface2)
    local st_lbl = s.online and "ONLINE" or "OFFLINE"
    draw.put(buf, x + w - #st_lbl - 1, y, st_lbl, s.online and theme.success or theme.danger, theme.surface2)
    y = y + 1

    -- Info
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("ID: #%d  Train: %s",
        station_id, s.has_train and "YES" or "NO"),
        theme.fg, theme.surface)
    y = y + 1

    -- Action buttons
    draw.fill(buf, y, x + w, theme.surface2)
    if not s.is_hub then
        draw.button(buf, x + 1, y, 10, 1, "SET AS HUB", theme.accent, theme.btn_text, true)
        hits.set_hub_btn = {x = 2, y = y - hits.oy + 1, w = 10, h = 1, id = station_id}
    else
        draw.put(buf, x + 1, y, "\4 MAIN HUB", theme.accent, theme.surface2)
    end
    draw.button(buf, x + 13, y, 8, 1, "REMOVE", theme.danger, theme.btn_text, true)
    hits.remove_station_btn = {x = 14, y = y - hits.oy + 1, w = 8, h = 1, id = station_id}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Switches
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "SWITCHES", theme.accent, theme.surface)
    y = y + 1

    if s.switches and #s.switches > 0 then
        hits.switch_toggles = {}
        for si, sw in ipairs(s.switches) do
            if y >= ctx.content_y + h - 8 then break end
            local bg = (si % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, bg)
            local state_lbl = sw.state and "ON" or "OFF"
            local state_col = sw.state and theme.success or theme.fg_dim
            local desc = sw.description or sw.peripheral_name or "Switch"
            if sw.parking then desc = desc .. " [P]" end
            draw.put(buf, x + 1, y, string.format("%d. %s", si, desc):sub(1, w - 6), theme.fg, bg)
            draw.put(buf, x + w - 5, y, state_lbl, state_col, bg)
            hits.switch_toggles[si] = {x = w - 5 + 1, y = y - hits.oy + 1, w = 3, h = 1, station_id = station_id, idx = si}
            y = y + 1
        end
    else
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No switches", theme.fg_dim, theme.surface)
        y = y + 1
    end

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Schedules for this station
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "SCHEDULES", theme.accent, theme.surface)
    if not s.is_hub then
        draw.button(buf, x + w - 6, y, 5, 1, " + ", theme.success, theme.btn_text, true)
        hits.add_sched_btn = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1, id = station_id}
    end
    y = y + 1

    local scheds = tr.station_schedules[station_id] or {}
    hits.sched_rows = {}
    hits.sched_toggle = {}
    hits.sched_remove = {}
    hits.sched_run = {}

    if #scheds > 0 then
        for si, sched in ipairs(scheds) do
            if y >= ctx.content_y + h - 2 then break end
            local bg = (si % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, bg)
            local icon = sched.type == "delivery" and "\26" or "\27"
            local type_col = sched.type == "delivery" and theme.success or theme.accent
            local en_lbl = sched.enabled and "ON" or "OFF"
            local en_col = sched.enabled and theme.success or theme.fg_dim
            draw.put(buf, x + 1, y, string.format("%s %s", icon, sched.type:sub(1, 7):upper()), type_col, bg)
            draw.put(buf, x + 12, y, format_period(sched.period), theme.fg_dim, bg)

            -- Items count for delivery
            if sched.type == "delivery" then
                local ic = sched.items and #sched.items or 0
                draw.put(buf, x + 20, y, ic .. " items", theme.fg_dim, bg)
            end

            -- Last run
            draw.put(buf, x + 30, y, format_time_ago(sched.last_run), theme.fg_dim, bg)

            -- Toggle
            draw.put(buf, x + w - 12, y, en_lbl, en_col, bg)
            hits.sched_toggle[si] = {x = w - 12 + 1, y = y - hits.oy + 1, w = 3, h = 1, station_id = station_id}

            -- Run now
            draw.put(buf, x + w - 8, y, "RUN", theme.accent, bg)
            hits.sched_run[si] = {x = w - 8 + 1, y = y - hits.oy + 1, w = 3, h = 1, station_id = station_id}

            -- Remove
            draw.put(buf, x + w - 2, y, "X", theme.danger, bg)
            hits.sched_remove[si] = {x = w - 2 + 1, y = y - hits.oy + 1, w = 1, h = 1, station_id = station_id}

            table.insert(hits.sched_rows, {x = 1, y = y - hits.oy + 1, w = w - 14, h = 1, idx = si, station_id = station_id})
            y = y + 1
        end
    else
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No schedules", theme.fg_dim, theme.surface)
        y = y + 1
    end

    while y < ctx.content_y + h do
        draw.fill(buf, y, x + w, theme.surface)
        y = y + 1
    end
end

local function render_stations(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local tr = ctx.state.transport

    if detail_station then
        render_station_detail(ctx, buf, x, y, w, h, detail_station)
        return
    end

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "NAME", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 20, y, "STATUS", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 30, y, "TRAIN", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 38, y, "SCHED", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 46, y, "SW", theme.fg_dim, theme.surface2)
    y = y + 1

    local sorted = {}
    for id, s in pairs(tr.stations) do
        table.insert(sorted, s)
    end
    table.sort(sorted, function(a, b)
        if a.is_hub ~= b.is_hub then return a.is_hub end
        return (a.label or "") < (b.label or "")
    end)

    local area_h = h - 2
    local max_scroll = math.max(0, #sorted - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.station_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)
        if idx <= #sorted then
            local s = sorted[idx]
            local prefix = s.is_hub and "\4" or " "
            draw.put(buf, x + 1, y, prefix .. (s.label or "?"):sub(1, 17), s.is_hub and theme.accent or theme.fg, rbg)
            draw.put(buf, x + 20, y, s.online and "ONLINE" or "OFFLINE", s.online and theme.success or theme.danger, rbg)
            draw.put(buf, x + 30, y, s.has_train and "YES" or "---", s.has_train and theme.success or theme.fg_dim, rbg)
            local sched_ct = tr.station_schedules[s.id] and #tr.station_schedules[s.id] or 0
            draw.put(buf, x + 38, y, tostring(sched_ct), sched_ct > 0 and theme.fg or theme.fg_dim, rbg)
            draw.put(buf, x + 46, y, tostring(#(s.switches or {})), theme.fg_dim, rbg)
            table.insert(hits.station_rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, id = s.id})
        end
        y = y + 1
    end

    draw.fill(buf, y, x + w, theme.surface2)
    draw.center(buf, string.format("%d stations", #sorted), y, x + w, theme.fg_dim, theme.surface2)
end

-- ========================================
-- Tab: Config (buffer chest, fuel)
-- ========================================
local function render_config(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local tr = ctx.state.transport

    -- Buffer chest
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "BUFFER CHEST (Trapped Chest)", theme.accent, theme.surface2)
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    if tr.buffer_chest then
        draw.put(buf, x + 1, y, tr.buffer_chest:sub(1, 30), theme.success, theme.surface)
        draw.button(buf, x + w - 8, y, 7, 1, "CLEAR", theme.danger, theme.btn_text, true)
        hits.clear_buffer = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    else
        draw.put(buf, x + 1, y, "Not configured", theme.warning, theme.surface)
    end
    draw.button(buf, x + w - 18, y, 9, 1, "SELECT", theme.accent, theme.btn_text, true)
    hits.select_buffer = {x = w - 18 + 1, y = y - hits.oy + 1, w = 9, h = 1}
    y = y + 1

    -- Buffer contents
    if tr.buffer_chest and tr.buffer_periph then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "Buffer Contents:", theme.fg_dim, theme.surface)
        y = y + 1
        local contents = tr.get_buffer_contents and tr.get_buffer_contents() or {}
        local item_count = 0
        for _, item in pairs(contents) do
            if y >= ctx.content_y + h - 8 then break end
            local bg = (item_count % 2 == 0) and theme.surface or theme.surface2
            draw.fill(buf, y, x + w, bg)
            draw.put(buf, x + 2, y, string.format("%dx %s", item.count, utils.clean_name(item.name)):sub(1, w - 4),
                theme.fg, bg)
            item_count = item_count + 1
            y = y + 1
        end
        if item_count == 0 then
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 2, y, "Empty", theme.fg_dim, theme.surface)
            y = y + 1
        end
    end

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Fuel configuration
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "FUEL PER TRIP", theme.accent, theme.surface2)
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    local fuel = tr.fuel_item or ctx.config.transport.fuel_item
    local fuel_ct = tr.fuel_per_trip or ctx.config.transport.fuel_per_trip
    draw.put(buf, x + 1, y, string.format("Item: %s", utils.clean_name(fuel or "none")):sub(1, 30), theme.fg, theme.surface)
    y = y + 1
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("Count: %d per trip", fuel_ct or 8), theme.fg, theme.surface)
    -- +/- buttons for fuel count
    draw.put(buf, x + 24, y, "[-]", theme.danger, theme.surface)
    hits.fuel_dec = {x = 25, y = y - hits.oy + 1, w = 3, h = 1}
    draw.put(buf, x + 28, y, "[+]", theme.success, theme.surface)
    hits.fuel_inc = {x = 29, y = y - hits.oy + 1, w = 3, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Hub station info
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "HUB STATION", theme.accent, theme.surface2)
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    if tr.hub_id and tr.stations[tr.hub_id] then
        local hub = tr.stations[tr.hub_id]
        draw.put(buf, x + 1, y, string.format("\4 %s (#%d) %s",
            hub.label, tr.hub_id, hub.online and "ONLINE" or "OFFLINE"),
            hub.online and theme.success or theme.danger, theme.surface)
    else
        draw.put(buf, x + 1, y, "No hub set - assign in Stations tab", theme.warning, theme.surface)
    end
    y = y + 1

    while y < ctx.content_y + h do
        draw.fill(buf, y, x + w, theme.surface)
        y = y + 1
    end
end

-- ========================================
-- Item Picker Overlay
-- ========================================
local function render_item_picker(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local items = ctx.state.storage.items or {}

    picker_hits = {}

    -- Title
    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Pick Item to Allow", theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    picker_hits.cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    -- Search bar
    draw.fill(buf, y, x + w, theme.surface2)
    local search_text_w = w - 4
    draw.put(buf, x + 1, y, "\16 [", theme.fg_dim, theme.surface2)
    local sq = picker_query ~= "" and picker_query or "search..."
    local sq_fg = picker_query ~= "" and theme.fg or theme.fg_dim
    draw.put(buf, x + 4, y, sq:sub(1, search_text_w - 2), sq_fg, theme.surface2)
    draw.put(buf, x + 4 + search_text_w - 2, y, "]", theme.fg_dim, theme.surface2)
    picker_hits.search_bar = {x = 1, y = y - hits.oy + 1, w = search_text_w + 3, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Filter
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
            draw.put(buf, x + 1, y, item.displayName:sub(1, 24), rfg, rbg)
            draw.put(buf, x + 26, y, ctx.utils.format_number(item.count), rfg_dim, rbg)
            table.insert(picker_hits.rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, item = item})
        end
        y = y + 1
    end

    -- Confirm bar
    if has_sel then
        draw.fill(buf, y, x + w, theme.surface2)
        draw.put(buf, x + 1, y, picker_selected.displayName:sub(1, 24), theme.fg, theme.surface2)
        draw.button(buf, x + w - 10, y, 9, 1, "CONFIRM", theme.success, theme.btn_text, true)
        picker_hits.confirm = {x = w - 10 + 1, y = y - hits.oy + 1, w = 9, h = 1}
    end
end

-- ========================================
-- Buffer Chest Picker Overlay
-- ========================================
local function render_buffer_picker(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local tr = ctx.state.transport

    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Select Trapped Chest", theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    hits.buffer_cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    hits.buffer_rows = {}

    if #buffer_list == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "No trapped chests found on network", theme.warning, theme.surface)
        y = y + 1
    else
        for i, name in ipairs(buffer_list) do
            if y >= ctx.content_y + h then break end
            local is_current = (name == tr.buffer_chest)
            local bg = is_current and theme.accent or ((i % 2 == 0) and theme.surface2 or theme.surface)
            local fg = is_current and theme.bg or theme.fg
            draw.fill(buf, y, x + w, bg)
            draw.put(buf, x + 1, y, name:sub(1, w - 4), fg, bg)
            if is_current then
                draw.put(buf, x + w - 10, y, "[CURRENT]", theme.bg, bg)
            end
            table.insert(hits.buffer_rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, name = name})
            y = y + 1
        end
    end

    while y < ctx.content_y + h do
        draw.fill(buf, y, x + w, theme.surface)
        y = y + 1
    end
end

-- ========================================
-- Period Picker Overlay
-- ========================================
local function render_period_picker(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local presets = ctx.config.transport.period_presets

    draw.fill(buf, y, x + w, theme.accent)
    draw.put(buf, x + 1, y, "Select Period", theme.bg, theme.accent)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    hits.period_cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    hits.period_rows = {}

    -- Manual option
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "Manual (no auto-schedule)", theme.fg, theme.surface)
    table.insert(hits.period_rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, seconds = 0})
    y = y + 1

    for i, p in ipairs(presets) do
        if y >= ctx.content_y + h then break end
        local bg = (i % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, bg)
        draw.put(buf, x + 1, y, p.label .. " (" .. p.seconds .. "s)", theme.fg, bg)
        table.insert(hits.period_rows, {x = 1, y = y - hits.oy + 1, w = w, h = 1, seconds = p.seconds})
        y = y + 1
    end

    while y < ctx.content_y + h do
        draw.fill(buf, y, x + w, theme.surface)
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
    local tr = ctx.state.transport

    hits = {btns = {}}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Header
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.transport

    for r = 0, 3 do
        draw.fill(buf, y + r, x + w, theme.surface2)
    end

    if icon_data and icon_lib then
        icon_lib.draw(buf, icon_data, x + 2, y)
    end

    local sx = x + 11
    draw.put(buf, sx, y, "TRANSPORT", theme.accent, theme.surface2)

    if tr.hub_id and tr.stations[tr.hub_id] then
        local hub = tr.stations[tr.hub_id]
        draw.put(buf, sx, y + 1, "Hub: " .. hub.label, hub.online and theme.success or theme.danger, theme.surface2)
    else
        draw.put(buf, sx, y + 1, "No hub set", theme.warning, theme.surface2)
    end

    local st_count = 0
    for _ in pairs(tr.stations) do st_count = st_count + 1 end
    local buf_lbl = tr.buffer_chest and "OK" or "NONE"
    local buf_col = tr.buffer_chest and theme.success or theme.danger
    draw.put(buf, sx, y + 2, string.format("Stations: %d  Buffer: ", st_count), theme.fg_dim, theme.surface2)
    draw.put(buf, sx + 20 + #tostring(st_count), y + 2, buf_lbl, buf_col, theme.surface2)
    draw.put(buf, sx, y + 3, string.format("Allow list: %d items  Dispatches: %d", #tr.allowed_items, #tr.dispatches), theme.fg_dim, theme.surface2)

    y = y + 4

    -- Tab bar
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"DASH", "ITEMS", "STATIONS", "CONFIG"}
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

    -- Content area
    local content_h = h - (y - ctx.content_y)

    -- Overlays first
    if picker_mode then
        render_item_picker(ctx, buf, x, y, w, content_h)
    elseif buffer_mode then
        render_buffer_picker(ctx, buf, x, y, w, content_h)
    elseif period_mode then
        render_period_picker(ctx, buf, x, y, w, content_h)
    elseif tab == 1 then
        render_dashboard(ctx, buf, x, y, w, content_h)
    elseif tab == 2 then
        render_items(ctx, buf, x, y, w, content_h)
    elseif tab == 3 then
        render_stations(ctx, buf, x, y, w, content_h)
    elseif tab == 4 then
        render_config(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local tr = ctx.state.transport
    local draw = ctx.draw

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3] - 1, ev[4]

            -- Overlay: Item picker
            if picker_mode then
                if picker_hits.cancel and draw.hit_test(picker_hits.cancel, tx, ty) then
                    picker_mode = nil
                    picker_selected = nil
                    picker_query = ""
                    picker_scroll = 0
                elseif picker_hits.search_bar and draw.hit_test(picker_hits.search_bar, tx, ty) then
                    local input = ctx.prompt("Search item:", picker_query)
                    if input then
                        picker_query = input
                        picker_scroll = 0
                    end
                elseif picker_hits.confirm and draw.hit_test(picker_hits.confirm, tx, ty) then
                    if picker_selected and picker_mode == "allow_item" then
                        if tr.add_allowed_item then
                            tr.add_allowed_item(picker_selected.name, picker_selected.displayName, 64)
                        end
                    elseif picker_selected and picker_mode == "schedule_item" then
                        -- Add item to current schedule
                        if edit_station_id and edit_schedule_idx then
                            local scheds = tr.station_schedules[edit_station_id]
                            if scheds and scheds[edit_schedule_idx] then
                                if not scheds[edit_schedule_idx].items then
                                    scheds[edit_schedule_idx].items = {}
                                end
                                -- Don't add duplicates
                                local found = false
                                for _, n in ipairs(scheds[edit_schedule_idx].items) do
                                    if n == picker_selected.name then found = true; break end
                                end
                                if not found then
                                    table.insert(scheds[edit_schedule_idx].items, picker_selected.name)
                                    if tr.update_schedule then
                                        tr.update_schedule(edit_station_id, edit_schedule_idx,
                                            "items", scheds[edit_schedule_idx].items)
                                    end
                                end
                            end
                        end
                    end
                    picker_mode = nil
                    picker_selected = nil
                    picker_query = ""
                    picker_scroll = 0
                elseif picker_hits.rows then
                    for _, row in ipairs(picker_hits.rows) do
                        if draw.hit_test(row, tx, ty) then
                            picker_selected = row.item
                            break
                        end
                    end
                end
                goto continue
            end

            -- Overlay: Buffer picker
            if buffer_mode then
                if hits.buffer_cancel and draw.hit_test(hits.buffer_cancel, tx, ty) then
                    buffer_mode = false
                elseif hits.buffer_rows then
                    for _, row in ipairs(hits.buffer_rows) do
                        if draw.hit_test(row, tx, ty) then
                            if tr.set_buffer_chest then
                                tr.set_buffer_chest(row.name)
                            end
                            buffer_mode = false
                            break
                        end
                    end
                end
                goto continue
            end

            -- Overlay: Period picker
            if period_mode then
                if hits.period_cancel and draw.hit_test(hits.period_cancel, tx, ty) then
                    period_mode = false
                elseif hits.period_rows then
                    for _, row in ipairs(hits.period_rows) do
                        if draw.hit_test(row, tx, ty) then
                            if edit_station_id and period_target_idx and tr.update_schedule then
                                tr.update_schedule(edit_station_id, period_target_idx, "period", row.seconds)
                            end
                            period_mode = false
                            break
                        end
                    end
                end
                goto continue
            end

            -- Tab clicks
            if hits.tabs then
                for ti, area in ipairs(hits.tabs) do
                    if draw.hit_test(area, tx, ty) then
                        tab = ti
                        scroll = 0
                        detail_station = nil
                        break
                    end
                end
            end

            -- Tab 2: Items
            if tab == 2 then
                if hits.add_item_btn and draw.hit_test(hits.add_item_btn, tx, ty) then
                    picker_mode = "allow_item"
                    picker_query = ""
                    picker_scroll = 0
                    picker_selected = nil
                elseif hits.item_rows then
                    for _, row in ipairs(hits.item_rows) do
                        if draw.hit_test(row, tx, ty) then
                            -- Check if X button area (last 2 chars)
                            if tx >= row.x + row.w - 3 then
                                if tr.remove_allowed_item then
                                    tr.remove_allowed_item(row.idx)
                                end
                            else
                                -- Click on min_keep column to edit
                                if tx >= 31 and tx <= 40 then
                                    local ai = tr.allowed_items[row.idx]
                                    if ai then
                                        local input = ctx.prompt("Min keep for " .. ai.display_name .. ":", tostring(ai.min_keep))
                                        if input then
                                            local val = tonumber(input)
                                            if val and val >= 0 then
                                                tr.update_allowed_item(row.idx, "min_keep", val)
                                            end
                                        end
                                    end
                                end
                            end
                            break
                        end
                    end
                end
            end

            -- Tab 3: Stations
            if tab == 3 then
                if detail_station then
                    -- Detail view handlers
                    if hits.detail_close and draw.hit_test(hits.detail_close, tx, ty) then
                        detail_station = nil
                    elseif hits.set_hub_btn and draw.hit_test(hits.set_hub_btn, tx, ty) then
                        if tr.set_hub then tr.set_hub(hits.set_hub_btn.id) end
                    elseif hits.remove_station_btn and draw.hit_test(hits.remove_station_btn, tx, ty) then
                        if tr.remove_station then
                            tr.remove_station(hits.remove_station_btn.id)
                            detail_station = nil
                        end
                    elseif hits.switch_toggles then
                        for si, area in pairs(hits.switch_toggles) do
                            if draw.hit_test(area, tx, ty) then
                                if tr.set_switch then
                                    local station = tr.stations[area.station_id]
                                    if station and station.switches[area.idx] then
                                        tr.set_switch(area.station_id, area.idx, not station.switches[area.idx].state)
                                    end
                                end
                                break
                            end
                        end
                    elseif hits.add_sched_btn and draw.hit_test(hits.add_sched_btn, tx, ty) then
                        -- Add new delivery schedule
                        if tr.add_schedule then
                            tr.add_schedule(hits.add_sched_btn.id, {
                                type = "delivery",
                                period = 3600,
                                items = {},
                            })
                        end
                    else
                        -- Schedule interactions
                        if hits.sched_toggle then
                            for si, area in pairs(hits.sched_toggle) do
                                if draw.hit_test(area, tx, ty) then
                                    if tr.toggle_schedule then
                                        tr.toggle_schedule(area.station_id, si)
                                    end
                                    goto continue
                                end
                            end
                        end
                        if hits.sched_run then
                            for si, area in pairs(hits.sched_run) do
                                if draw.hit_test(area, tx, ty) then
                                    local scheds = tr.station_schedules[area.station_id]
                                    if scheds and scheds[si] and tr.execute_trip then
                                        local sched = scheds[si]
                                        local reqs = {}
                                        if sched.type == "delivery" then
                                            for _, item_name in ipairs(sched.items or {}) do
                                                local amt = (sched.amounts and sched.amounts[item_name]) or 64
                                                table.insert(reqs, {item = item_name, amount = amt})
                                            end
                                        end
                                        tr.execute_trip(area.station_id, sched.type, reqs)
                                    end
                                    goto continue
                                end
                            end
                        end
                        if hits.sched_remove then
                            for si, area in pairs(hits.sched_remove) do
                                if draw.hit_test(area, tx, ty) then
                                    if tr.remove_schedule then
                                        tr.remove_schedule(area.station_id, si)
                                    end
                                    goto continue
                                end
                            end
                        end
                        -- Click on schedule row to edit (period, items, type)
                        if hits.sched_rows then
                            for _, row in ipairs(hits.sched_rows) do
                                if draw.hit_test(row, tx, ty) then
                                    -- Open period picker or type toggle based on click position
                                    local rel_x = tx - row.x
                                    if rel_x < 10 then
                                        -- Toggle type between delivery/collection
                                        local scheds = tr.station_schedules[row.station_id]
                                        if scheds and scheds[row.idx] then
                                            local new_type = scheds[row.idx].type == "delivery" and "collection" or "delivery"
                                            if tr.update_schedule then
                                                tr.update_schedule(row.station_id, row.idx, "type", new_type)
                                            end
                                        end
                                    elseif rel_x < 20 then
                                        -- Period picker
                                        period_mode = true
                                        edit_station_id = row.station_id
                                        period_target_idx = row.idx
                                    else
                                        -- Add items to schedule (delivery only)
                                        local scheds = tr.station_schedules[row.station_id]
                                        if scheds and scheds[row.idx] and scheds[row.idx].type == "delivery" then
                                            picker_mode = "schedule_item"
                                            edit_station_id = row.station_id
                                            edit_schedule_idx = row.idx
                                            picker_query = ""
                                            picker_scroll = 0
                                            picker_selected = nil
                                        end
                                    end
                                    break
                                end
                            end
                        end
                    end
                else
                    -- Station list clicks
                    if hits.station_rows then
                        for _, row in ipairs(hits.station_rows) do
                            if draw.hit_test(row, tx, ty) then
                                detail_station = row.id
                                detail_scroll = 0
                                break
                            end
                        end
                    end
                end
            end

            -- Tab 4: Config
            if tab == 4 then
                if hits.select_buffer and draw.hit_test(hits.select_buffer, tx, ty) then
                    buffer_mode = true
                    if tr.list_trapped_chests then
                        buffer_list = tr.list_trapped_chests()
                    end
                elseif hits.clear_buffer and draw.hit_test(hits.clear_buffer, tx, ty) then
                    if tr.clear_buffer_chest then
                        tr.clear_buffer_chest()
                    end
                elseif hits.fuel_dec and draw.hit_test(hits.fuel_dec, tx, ty) then
                    local cur = tr.fuel_per_trip or ctx.config.transport.fuel_per_trip or 8
                    tr.fuel_per_trip = math.max(0, cur - 1)
                elseif hits.fuel_inc and draw.hit_test(hits.fuel_inc, tx, ty) then
                    local cur = tr.fuel_per_trip or ctx.config.transport.fuel_per_trip or 8
                    tr.fuel_per_trip = math.min(64, cur + 1)
                end
            end

            ::continue::

        elseif ev[1] == "mouse_scroll" then
            if picker_mode and picker_hits.max_scroll then
                picker_scroll = math.max(0, math.min(picker_hits.max_scroll, picker_scroll + ev[2]))
            elseif tab == 2 or (tab == 3 and not detail_station) then
                scroll = math.max(0, scroll + ev[2])
            end

        elseif ev[1] == "char" and picker_mode then
            picker_query = picker_query .. ev[2]
            picker_scroll = 0

        elseif ev[1] == "key" then
            if picker_mode then
                if ev[2] == keys.backspace and #picker_query > 0 then
                    picker_query = picker_query:sub(1, -2)
                    picker_scroll = 0
                elseif ev[2] == keys.escape then
                    picker_mode = nil
                    picker_selected = nil
                    picker_query = ""
                    picker_scroll = 0
                end
            elseif buffer_mode and ev[2] == keys.escape then
                buffer_mode = false
            elseif period_mode and ev[2] == keys.escape then
                period_mode = false
            end
        end
    end
end

return app
