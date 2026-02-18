-- =============================================
-- WRAITH OS - DESKTOP
-- =============================================
-- Renders wallpaper, app icon grid, quick action dock, status bar

local desktop = {}

local state, config, theme, draw, icon_lib

function desktop.init(s, c, t, d, i)
    state = s
    config = c
    theme = t
    draw = d
    icon_lib = i
end

-- Watermark text: "WRAITH" in 5x5 pixel font (each letter 5 wide, 1 gap)
local wm_font = {
    "10001 1110  1111  1111 11111 1   1",
    "10001 1   1 1   1  1    1   1   1",
    "10101 1110  1111   1    1   11111",
    "11011 1  1  1   1  1    1   1   1",
    "10001 1   1 1   1 1111  1   1   1",
}

-- Draw wallpaper pattern with centered watermark
function desktop.draw_wallpaper(buf, W, H)
    local usable_h = H - 2  -- leave room for taskbar

    local wm_w = #wm_font[1]
    local wm_h = #wm_font
    local wm_x = math.floor((W - wm_w) / 2) + 1
    local wm_y = math.floor((usable_h - wm_h) / 2) + 1

    for y = 1, usable_h do
        buf.setCursorPos(1, y)
        local line_text = ""
        local line_fg = ""
        local line_bg = ""
        for x = 1, W do
            local wm_col = x - wm_x + 1
            local wm_row = y - wm_y + 1
            local in_wm = wm_row >= 1 and wm_row <= wm_h and wm_col >= 1 and wm_col <= wm_w
            local wm_pixel = false
            if in_wm then
                local ch = wm_font[wm_row]:sub(wm_col, wm_col)
                wm_pixel = (ch == "1")
            end

            if wm_pixel then
                line_text = line_text .. "\7"
                line_fg = line_fg .. "c"
                line_bg = line_bg .. "f"
            elseif (x + y) % 8 == 0 then
                line_text = line_text .. "\7"
                line_fg = line_fg .. "c"
                line_bg = line_bg .. "f"
            elseif (x * 3 + y * 7) % 17 == 0 then
                line_text = line_text .. "\7"
                line_fg = line_fg .. "b"
                line_bg = line_bg .. "f"
            else
                line_text = line_text .. " "
                line_fg = line_fg .. "f"
                line_bg = line_bg .. "f"
            end
        end
        buf.blit(line_text, line_fg, line_bg)
    end
end

-- =============================================
-- APP ICON GRID (top portion of desktop)
-- =============================================

function desktop.get_icon_positions(W, H)
    local apps = state.app_order
    local n = #apps
    if n == 0 then return {} end

    local cell_w = config.desktop.icon_cell_w
    local cell_h = config.desktop.icon_cell_h

    -- App icons occupy the top portion, leaving bottom 10 rows for dock area
    local dock_reserve = 10
    local usable_h = H - 2 - dock_reserve  -- -2 for taskbar, -dock for dock

    local cols = math.min(n, math.floor(W / cell_w))
    local rows = math.ceil(n / cols)

    local grid_w = cols * cell_w
    local grid_h = rows * cell_h
    local start_x = math.floor((W - grid_w) / 2) + 1
    local start_y = math.max(2, math.floor((usable_h - grid_h) / 2) + 1)

    local positions = {}
    for i, app_id in ipairs(apps) do
        local col = ((i - 1) % cols)
        local row = math.floor((i - 1) / cols)
        local cx = start_x + col * cell_w
        local cy = start_y + row * cell_h

        positions[i] = {
            app_id = app_id,
            x = cx, y = cy,
            w = cell_w, h = cell_h,
        }
    end
    return positions
end

function desktop.draw_icons(buf, W, H)
    local positions = desktop.get_icon_positions(W, H)

    for _, pos in ipairs(positions) do
        local app_def = state.app_registry[pos.app_id]
        if app_def then
            local pad = 1
            for cy = pos.y + pad, pos.y + pos.h - 2 do
                buf.setCursorPos(pos.x + pad, cy)
                buf.setBackgroundColor(theme.surface2)
                buf.write(string.rep(" ", pos.w - pad * 2))
            end

            local icon_data = icon_lib.icons[pos.app_id]
            if icon_data then
                local iw, ih = icon_lib.size(icon_data)
                local icon_x = pos.x + math.floor((pos.w - iw) / 2)
                local icon_y = pos.y + 1
                icon_lib.draw(buf, icon_data, icon_x, icon_y)
            end

            local label = app_def.name or pos.app_id
            if #label > pos.w - 2 then label = label:sub(1, pos.w - 4) .. ".." end
            local label_x = pos.x + math.floor((pos.w - #label) / 2)
            local label_y = pos.y + pos.h - 1
            draw.put(buf, label_x, label_y, label, theme.icon_label, theme.desktop_bg)
        end
    end
end

-- =============================================
-- DOCK AREA (bottom of desktop, above taskbar)
-- =============================================
-- Layout: | DEPOT | ---QUICK WITHDRAW--- | LOADOUT |
-- Sits in a styled dock bar spanning the bottom

desktop.quick_withdraw_areas = {}
desktop.depot_card_areas = {}
desktop.loadout_card_areas = {}

-- Draw the entire dock area as a unified strip
function desktop.draw_dock(buf, W, H)
    desktop.quick_withdraw_areas = {}
    desktop.depot_card_areas = {}
    desktop.loadout_card_areas = {}

    local dock_h = 7
    local dock_y = H - 2 - dock_h  -- above taskbar
    local dock_x = 1

    -- Dock background: subtle gradient bar
    for r = 0, dock_h - 1 do
        buf.setCursorPos(1, dock_y + r)
        buf.setBackgroundColor(r == 0 and theme.border or theme.surface)
        buf.write(string.rep(" ", W))
    end
    -- Top border accent line
    buf.setCursorPos(1, dock_y)
    buf.setBackgroundColor(theme.border)
    buf.write(string.rep(" ", W))

    -- ===== LEFT: Depot cards =====
    local left_x = 2
    local card_y = dock_y + 1

    local ld = state.loadouts
    local depot_ready = ld and ld.ready and ld.has_depot_ready and ld.has_depot_ready()

    -- Quick Depot card (3 rows)
    do
        local cw = 16
        local cy = card_y

        -- Icon row: chest pixel art + label
        buf.setCursorPos(left_x, cy)
        buf.setBackgroundColor(theme.surface2)
        -- Mini chest icon (3 chars)
        buf.blit("\131\131\131", "111", "ccc")
        buf.setBackgroundColor(theme.surface2)
        buf.setTextColor(depot_ready and theme.warning or theme.fg_dim)
        buf.write(" Quick Depot" .. string.rep(" ", math.max(0, cw - 15)))

        -- Description row
        buf.setCursorPos(left_x, cy + 1)
        buf.setBackgroundColor(theme.surface2)
        buf.setTextColor(theme.fg_dark)
        buf.write(" Keep equipped  ")

        -- Action button
        buf.setCursorPos(left_x, cy + 2)
        if depot_ready then
            buf.setBackgroundColor(theme.success)
            buf.setTextColor(theme.bg)
            buf.write(" \16 DEPOSIT     ")
        else
            buf.setBackgroundColor(theme.surface)
            buf.setTextColor(theme.fg_dark)
            buf.write("   \7 \7 \7       ")
        end

        table.insert(desktop.depot_card_areas, {
            x = left_x, y = cy, w = cw, h = 3,
            id = "quick", enabled = depot_ready,
        })
    end

    -- Full Depot card (3 rows)
    do
        local cw = 16
        local cy = card_y + 3

        buf.setCursorPos(left_x, cy)
        buf.setBackgroundColor(theme.surface2)
        -- Mini crate icon
        buf.blit("\131\131\131", "888", "777")
        buf.setBackgroundColor(theme.surface2)
        buf.setTextColor(depot_ready and theme.danger or theme.fg_dim)
        buf.write(" Full Depot " .. string.rep(" ", math.max(0, cw - 15)))

        buf.setCursorPos(left_x, cy + 1)
        buf.setBackgroundColor(theme.surface2)
        buf.setTextColor(theme.fg_dark)
        buf.write(" Strip all gear ")

        buf.setCursorPos(left_x, cy + 2)
        if depot_ready then
            buf.setBackgroundColor(theme.danger)
            buf.setTextColor(theme.bg)
            buf.write(" \16 STRIP ALL   ")
        else
            buf.setBackgroundColor(theme.surface)
            buf.setTextColor(theme.fg_dark)
            buf.write("   \7 \7 \7       ")
        end

        table.insert(desktop.depot_card_areas, {
            x = left_x, y = cy, w = cw, h = 3,
            id = "full", enabled = depot_ready,
        })
    end

    -- ===== CENTER: Quick Withdraw cards =====
    local center_start = 20
    local center_end = W - 19
    local center_w = center_end - center_start

    local analytics = state.analytics
    local st = state.storage
    local has_analytics = analytics and analytics.top_extracted and st and st.items

    -- Food detection: check Minecraft item tags first, fallback to name patterns
    local function is_food_item(item)
        if not item then return false end
        -- Check item tags (works with modded foods automatically)
        local tags = item.tags
        if tags then
            if tags["minecraft:foods"] or tags["c:foods"] then return true end
        end
        -- Fallback: name-based for items without tag data
        local n = (item.name or ""):lower()
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

    if has_analytics then
        -- Find highest-stock food item in storage
        local best_food = nil
        for _, item in ipairs(st.items) do
            if is_food_item(item) and item.count > 0 then
                if not best_food or item.count > best_food.count then
                    best_food = item
                end
            end
        end

        -- Sort top_extracted by count descending
        local sorted = {}
        for display_name, count in pairs(analytics.top_extracted) do
            table.insert(sorted, {displayName = display_name, withdraw_count = count})
        end
        table.sort(sorted, function(a, b) return a.withdraw_count > b.withdraw_count end)

        -- Build top list: food slot first, then top extracted (up to 3 total)
        local top = {}
        local used_names = {}

        -- Slot 1: best food item
        if best_food then
            table.insert(top, {
                displayName = best_food.displayName or best_food.name,
                name = best_food.name, nbt = best_food.nbt,
                stock = best_food.count,
                is_food = true,
            })
            used_names[best_food.displayName or best_food.name] = true
        end

        -- Remaining slots: top extracted items (skip the food if already shown)
        for i = 1, #sorted do
            if #top >= 3 then break end
            local entry = sorted[i]
            if not used_names[entry.displayName] then
                local found = nil
                for _, item in ipairs(st.items) do
                    if item.displayName == entry.displayName then
                        found = item
                        break
                    end
                end
                if found then
                    table.insert(top, {
                        displayName = entry.displayName,
                        name = found.name, nbt = found.nbt,
                        stock = found.count,
                    })
                    used_names[entry.displayName] = true
                end
            end
        end

        if #top > 0 then
            -- Section label
            draw.put(buf, center_start, dock_y + 1, " \4 QUICK GET", theme.accent, theme.surface)

            local CARD_W = math.min(math.floor((center_w - 2) / 3), 14)
            local gap = 1
            local total_cw = #top * CARD_W + (#top - 1) * gap
            local cx_start = center_start + math.floor((center_w - total_cw) / 2)

            for i, item in ipairs(top) do
                local cx = cx_start + (i - 1) * (CARD_W + gap)
                local cy = dock_y + 2

                -- Card background
                for r = 0, 3 do
                    buf.setCursorPos(cx, cy + r)
                    buf.setBackgroundColor(theme.surface2)
                    buf.write(string.rep(" ", CARD_W))
                end

                -- Row 1: Item name
                local label = item.displayName
                if #label > CARD_W - 2 then label = label:sub(1, CARD_W - 4) .. ".." end
                draw.put(buf, cx + 1, cy, label, theme.fg, theme.surface2)

                -- Row 2: Stock count with color bar
                local stock_str = tostring(item.stock)
                local sc = item.stock < 16 and theme.danger or (item.stock < 64 and theme.warning or theme.success)
                draw.put(buf, cx + 1, cy + 1, stock_str, sc, theme.surface2)
                -- Mini stock bar
                local bar_w = CARD_W - #stock_str - 3
                if bar_w > 1 then
                    local pct = math.min(1, item.stock / 256)
                    local filled = math.max(1, math.floor(pct * bar_w))
                    buf.setCursorPos(cx + #stock_str + 2, cy + 1)
                    buf.setBackgroundColor(sc)
                    buf.write(string.rep(" ", filled))
                    buf.setBackgroundColor(theme.border)
                    buf.write(string.rep(" ", bar_w - filled))
                end

                -- Row 3: empty (spacing)

                -- Row 4: Three GET buttons (x1 | x64 | ALL)
                local item_data = {name = item.name, nbt = item.nbt, displayName = item.displayName, count = item.stock}
                local btn_gap = 1
                local btn_total = CARD_W
                local btn_w = math.floor((btn_total - 2 * btn_gap) / 3)
                local btn_rem = btn_total - (btn_w * 3 + 2 * btn_gap)

                local btns = {
                    {label = "x1",  amount = 1,   bg = theme.accent},
                    {label = "x64", amount = 64,  bg = theme.accent},
                    {label = "ALL", amount = item.stock, bg = theme.accent2},
                }
                local bx = cx
                for bi, btn in ipairs(btns) do
                    local bw = btn_w + (bi <= btn_rem and 1 or 0)
                    buf.setCursorPos(bx, cy + 3)
                    buf.setBackgroundColor(btn.bg)
                    buf.setTextColor(theme.bg)
                    local lpad = math.floor((bw - #btn.label) / 2)
                    buf.write(string.rep(" ", lpad) .. btn.label .. string.rep(" ", math.max(0, bw - lpad - #btn.label)))
                    table.insert(desktop.quick_withdraw_areas, {
                        x = bx, y = cy + 3, w = bw, h = 1,
                        item = item_data, amount = math.min(btn.amount, item.stock),
                    })
                    bx = bx + bw + btn_gap
                end

                -- Also make the card body clickable for x1 withdraw
                table.insert(desktop.quick_withdraw_areas, {
                    x = cx, y = cy, w = CARD_W, h = 3,
                    item = item_data, amount = 1,
                })
            end
        else
            -- No withdraw data yet
            draw.center(buf, "Withdraw items to see quick access here", dock_y + 3, W, theme.fg_dark, theme.surface)
        end
    else
        draw.center(buf, "Storage loading...", dock_y + 3, W, theme.fg_dark, theme.surface)
    end

    -- ===== RIGHT: Loadout cards =====
    if not ld or not ld.ready then return end

    local names = {}
    for name in pairs(ld.saved) do
        table.insert(names, name)
    end
    table.sort(names)
    if #names == 0 then return end

    local right_x = W - 17
    local MAX_CARDS = 2
    local show = math.min(#names, MAX_CARDS)

    for i = 1, show do
        local name = names[i]
        local cw = 16
        local cy = card_y + (i - 1) * 3

        -- Icon row: armor pixel art + name
        buf.setCursorPos(right_x, cy)
        buf.setBackgroundColor(theme.surface2)
        -- Mini armor icon
        buf.blit("\131\143\131", "838", "787")
        buf.setBackgroundColor(theme.surface2)
        buf.setTextColor(theme.accent)
        local label = name
        if #label > cw - 5 then label = label:sub(1, cw - 7) .. ".." end
        buf.write(" " .. label .. string.rep(" ", math.max(0, cw - #label - 4)))

        -- Description row
        buf.setCursorPos(right_x, cy + 1)
        buf.setBackgroundColor(theme.surface2)
        buf.setTextColor(theme.fg_dark)
        buf.write(" Quick equip    ")

        -- Action button
        buf.setCursorPos(right_x, cy + 2)
        buf.setBackgroundColor(theme.accent)
        buf.setTextColor(theme.bg)
        buf.write(" \16 EQUIP       ")

        table.insert(desktop.loadout_card_areas, {
            x = right_x, y = cy, w = cw, h = 3,
            name = name,
        })
    end
end

-- =============================================
-- STATUS BAR (row H-2, just above taskbar)
-- =============================================
function desktop.draw_status_bar(buf, W, H)
    local st = state.storage
    if not st or not st.ready then return end

    local bar_y = H - 2
    local cx = 2

    draw.put(buf, cx, bar_y, "\4", theme.accent, theme.desktop_bg)
    cx = cx + 2
    if st.stats then
        local pct = st.stats.usage_pct or 0
        local bar_w = math.floor(W * 0.35)
        local filled = math.floor(pct * bar_w)
        local bar_fg = pct > 0.9 and theme.danger or (pct > 0.7 and theme.warning or theme.accent)
        buf.setCursorPos(cx, bar_y)
        buf.setBackgroundColor(bar_fg)
        buf.write(string.rep(" ", filled))
        buf.setBackgroundColor(theme.border)
        buf.write(string.rep(" ", bar_w - filled))
        local lbl = string.format(" %d%%", math.floor(pct * 100))
        draw.put(buf, cx + bar_w + 1, bar_y, lbl, theme.fg_dim, theme.desktop_bg)
        cx = cx + bar_w + #lbl + 2
    end

    -- Last import time
    if st.get_import_info then
        local info = st.get_import_info()
        local ago_str
        if info.last_time <= 0 then
            ago_str = "no imports"
        else
            local ago = math.floor(os.clock() - info.last_time)
            if ago < 60 then ago_str = ago .. "s ago"
            else ago_str = math.floor(ago / 60) .. "m ago" end
        end
        local ago_color = (info.last_time > 0 and (os.clock() - info.last_time) < 30)
            and theme.success or theme.fg_dim
        draw.put(buf, cx, bar_y, "\16", theme.fg_dark, theme.desktop_bg)
        cx = cx + 1
        draw.put(buf, cx, bar_y, ago_str, ago_color, theme.desktop_bg)
        cx = cx + #ago_str + 1
    end

    draw.put(buf, cx, bar_y, "\7", theme.fg_dark, theme.desktop_bg)
    cx = cx + 2

    if st.fuel_peripheral then
        draw.put(buf, cx, bar_y, "\7", theme.warning, theme.desktop_bg)
        cx = cx + 2
        local fl = st.fuel_chest_level or 0
        local ft = st.fuel_chest_target or 128
        local fpct = ft > 0 and math.floor(fl / ft * 100) or 0
        local fc = fpct < 25 and theme.danger or (fpct < 50 and theme.warning or theme.success)
        draw.put(buf, cx, bar_y, string.format("%d/%d", fl, ft), fc, theme.desktop_bg)
        cx = cx + #string.format("%d/%d", fl, ft) + 1

        draw.put(buf, cx, bar_y, "\7", theme.fg_dark, theme.desktop_bg)
        cx = cx + 2
    end

    if st.furnace_count and st.furnace_count > 0 then
        draw.put(buf, cx, bar_y, "\7", theme.info, theme.desktop_bg)
        cx = cx + 2
        local smelt_lbl = string.format("%dF", st.furnace_count)
        draw.put(buf, cx, bar_y, smelt_lbl, theme.fg_dim, theme.desktop_bg)
        cx = cx + #smelt_lbl + 1
        local on = st.smelting_enabled
        draw.put(buf, cx, bar_y, on and "ON" or "OFF", on and theme.success or theme.danger, theme.desktop_bg)
        cx = cx + (on and 2 or 3) + 1
    end

    local mm = state.mastermine
    if mm and mm.hub_id then
        draw.put(buf, cx, bar_y, "\7", theme.fg_dark, theme.desktop_bg)
        cx = cx + 2
        draw.put(buf, cx, bar_y, "T", theme.warning, theme.desktop_bg)
        cx = cx + 1
        draw.put(buf, cx, bar_y, "\7", mm.hub_connected and theme.success or theme.danger, theme.desktop_bg)
        cx = cx + 1
        draw.put(buf, cx, bar_y, mm.mining_on and "ON" or "OFF", mm.mining_on and theme.success or theme.danger, theme.desktop_bg)
        cx = cx + (mm.mining_on and 2 or 3) + 1
        local tc = 0
        for _ in pairs(mm.turtles or {}) do tc = tc + 1 end
        if tc > 0 then
            local tc_lbl = string.format("%dT", tc)
            draw.put(buf, cx, bar_y, tc_lbl, theme.fg_dim, theme.desktop_bg)
            cx = cx + #tc_lbl + 1
        end
    end

    local fm = state.farms
    if fm and fm.tree_clients then
        local online = 0
        local total = 0
        for _, c in pairs(fm.tree_clients) do
            total = total + 1
            if c.state ~= "offline" then online = online + 1 end
        end
        if total > 0 then
            draw.put(buf, cx, bar_y, "\7", theme.fg_dark, theme.desktop_bg)
            cx = cx + 2
            draw.put(buf, cx, bar_y, "\7", online > 0 and theme.success or theme.danger, theme.desktop_bg)
            cx = cx + 1
            local tf_lbl = string.format("%dTF", online)
            draw.put(buf, cx, bar_y, tf_lbl, theme.fg_dim, theme.desktop_bg)
            cx = cx + #tf_lbl + 1
        end
    end

    local ar = state.ar
    if ar and ar.ready then
        draw.put(buf, cx, bar_y, "\7", theme.fg_dark, theme.desktop_bg)
        cx = cx + 2
        draw.put(buf, cx, bar_y, "\7", ar.connected and theme.accent2 or theme.danger, theme.desktop_bg)
        cx = cx + 1
        draw.put(buf, cx, bar_y, "AR", ar.connected and theme.accent2 or theme.fg_dark, theme.desktop_bg)
        cx = cx + 3
        if ar.alert_count and ar.alert_count > 0 then
            draw.put(buf, cx, bar_y, tostring(ar.alert_count), theme.danger, theme.desktop_bg)
            cx = cx + #tostring(ar.alert_count) + 1
        end
    end
end

-- =============================================
-- TOUCH HANDLER
-- =============================================
function desktop.handle_touch(tx, ty, W, H)
    -- Quick withdraw cards (center dock)
    for _, card in ipairs(desktop.quick_withdraw_areas or {}) do
        if tx >= card.x and tx < card.x + card.w and
           ty >= card.y and ty < card.y + card.h then
            return "quick_withdraw", {item = card.item, amount = card.amount or 1}
        end
    end

    -- Loadout cards (right dock)
    for _, card in ipairs(desktop.loadout_card_areas or {}) do
        if tx >= card.x and tx < card.x + card.w and
           ty >= card.y and ty < card.y + card.h then
            return "loadout_equip", card.name
        end
    end

    -- Depot cards (left dock)
    for _, card in ipairs(desktop.depot_card_areas or {}) do
        if card.enabled and
           tx >= card.x and tx < card.x + card.w and
           ty >= card.y and ty < card.y + card.h then
            return "depot_action", card.id
        end
    end

    -- App icons
    local positions = desktop.get_icon_positions(W, H)
    for _, pos in ipairs(positions) do
        if tx >= pos.x and tx < pos.x + pos.w and
           ty >= pos.y and ty < pos.y + pos.h then
            return pos.app_id
        end
    end

    return nil
end

-- =============================================
-- FULL RENDER
-- =============================================
function desktop.render(buf, W, H)
    desktop.draw_wallpaper(buf, W, H)
    desktop.draw_icons(buf, W, H)
    desktop.draw_dock(buf, W, H)
    desktop.draw_status_bar(buf, W, H)
end

return desktop
