-- =============================================
-- WRAITH OS - ANALYTICS APP
-- =============================================
-- Live storage throughput graphs, smelting rates,
-- top items, capacity trends.

local app = {
    id = "analytics",
    name = "Analytics",
    icon = "analytics",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local scroll = 0
local tab = 1  -- 1=throughput, 2=smelting, 3=top items, 4=farms
local TAB_COUNT = 4

local hits = {}

-- ========================================
-- Graph drawing helpers
-- ========================================

-- Draw a bar chart with half-block resolution
-- values: array of numbers, area: {x, y, w, h}, colors: {bar, bar2, bg, axis}
local function draw_bar_graph(buf, draw, values, area, cols, label_fn)
    local x, y, w, h = area.x, area.y, area.w, area.h
    if #values == 0 then return end

    -- Find max for scaling
    local max_val = 1
    for _, v in ipairs(values) do
        if type(v) == "table" then
            local sum = 0
            for _, sv in ipairs(v) do sum = sum + sv end
            if sum > max_val then max_val = sum end
        else
            if v > max_val then max_val = v end
        end
    end

    -- Draw each column
    local bar_w = math.max(1, math.floor(w / #values))
    local levels = h * 2  -- half-block resolution

    for i, val in ipairs(values) do
        local bx = x + (i - 1) * bar_w
        if bx >= x + w then break end

        if type(val) == "table" then
            -- Stacked bar: val = {bottom_val, top_val}
            local fill1 = math.floor((val[1] / max_val) * levels)
            local fill2 = math.floor((val[2] / max_val) * levels)
            draw_single_bar(buf, draw, bx, y, bar_w, h, fill1, cols.bar, cols.bg)
            draw_single_bar_overlay(buf, draw, bx, y, bar_w, h, fill1, fill1 + fill2, cols.bar2, cols.bg)
        else
            local fill = math.floor((val / max_val) * levels)
            draw_single_bar(buf, draw, bx, y, bar_w, h, fill, cols.bar, cols.bg)
        end
    end

    -- Y-axis max label
    if label_fn then
        local lbl = label_fn(max_val)
        draw.put(buf, x, y, lbl, cols.axis or cols.bar, cols.bg)
    end
end

-- Draw a single bar column with half-block precision
local function draw_single_bar(buf, draw, bx, y, bw, h, fill, bar_col, bg_col)
    local full_rows = math.floor(fill / 2)
    local has_half = fill % 2 == 1

    for row = 0, h - 1 do
        local ry = y + row
        local rows_from_bottom = h - 1 - row

        if rows_from_bottom < full_rows then
            -- Full filled row
            buf.setCursorPos(bx, ry)
            buf.setBackgroundColor(bar_col)
            buf.write(string.rep(" ", bw))
        elseif rows_from_bottom == full_rows and has_half then
            -- Half-block transition: bottom half filled
            buf.setCursorPos(bx, ry)
            buf.setTextColor(bar_col)
            buf.setBackgroundColor(bg_col)
            buf.write(string.rep("\131", bw))  -- ▄
        else
            -- Empty row
            buf.setCursorPos(bx, ry)
            buf.setBackgroundColor(bg_col)
            buf.write(string.rep(" ", bw))
        end
    end
end

-- Draw a sparkline (single row, using ▄▀ chars)
local function draw_sparkline(buf, draw, values, x, y, w, fg, bg)
    if #values == 0 then return end
    local max_val = 1
    for _, v in ipairs(values) do if v > max_val then max_val = v end end

    local chars = {" ", "\131", "\131", "\143"}  -- 0, low, mid, high
    for i = 1, math.min(w, #values) do
        local v = values[#values - math.min(w, #values) + i] or 0
        local pct = v / max_val
        local ch
        if pct <= 0 then ch = " "
        elseif pct < 0.33 then ch = "\131"  -- ▄ (bottom)
        elseif pct < 0.66 then ch = "\143"  -- ▀ (top half = mid)
        else ch = "\127"  -- full block
        end
        buf.setCursorPos(x + i - 1, y)
        buf.setTextColor(fg)
        buf.setBackgroundColor(bg)
        buf.write(ch)
    end
end

function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local an = ctx.state.analytics
    local st = ctx.state.storage

    hits = {}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- ========================================
    -- Header: Icon + summary stats
    -- ========================================
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.analytics

    for r = 0, 3 do
        draw.fill(buf, y + r, x + w, theme.surface2)
    end

    if icon_data and icon_lib then
        icon_lib.draw(buf, icon_data, x + 2, y)
    end

    local sx = x + 11
    draw.put(buf, sx, y, "ANALYTICS", theme.accent, theme.surface2)

    -- Live throughput summary
    local cur_min = math.floor(os.clock() / 60)
    local cur_bucket = an.buckets[cur_min] or {}
    local prev_bucket = an.buckets[cur_min - 1] or {}

    local ext_rate = (prev_bucket.extracted or 0)
    local imp_rate = (prev_bucket.imported or 0)
    local smelt_rate = (prev_bucket.smelted_out or 0)

    draw.put(buf, sx, y + 1, string.format("OUT: %d/min", ext_rate), theme.accent2, theme.surface2)
    draw.put(buf, sx + 14, y + 1, string.format("IN: %d/min", imp_rate), theme.success, theme.surface2)
    draw.put(buf, sx, y + 2, string.format("Smelted: %d/min", smelt_rate), theme.warning, theme.surface2)
    draw.put(buf, sx, y + 3, string.format("Total: %s out  %s in",
        utils.format_number(an.totals.extracted or 0),
        utils.format_number(an.totals.imported or 0)), theme.fg_dim, theme.surface2)

    y = y + 4

    -- ========================================
    -- Tab bar
    -- ========================================
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"THROUGHPUT", "SMELTING", "TOP ITEMS", "FARMS"}
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

    -- ========================================
    -- Tab content
    -- ========================================
    local content_h = h - (y - ctx.content_y)

    if tab == 1 then
        -- THROUGHPUT: extraction + import bar graph over last 20 minutes
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "Items per Minute (last 20 min)", theme.fg, theme.surface)
        y = y + 1

        -- Build data arrays
        local graph_mins = math.min(20, w - 4)
        local ext_data = {}
        local imp_data = {}
        local max_val = 1
        for i = graph_mins, 1, -1 do
            local m = cur_min - i
            local b = an.buckets[m] or {}
            local ev = b.extracted or 0
            local iv = b.imported or 0
            table.insert(ext_data, ev)
            table.insert(imp_data, iv)
            if ev > max_val then max_val = ev end
            if iv > max_val then max_val = iv end
        end

        -- Draw graph area
        local graph_h = math.min(8, content_h - 6)
        local graph_x = x + 6
        local graph_w = w - 8
        local levels = graph_h * 2

        -- Y-axis labels
        draw.put(buf, x + 1, y, utils.pad_left(tostring(max_val), 4), theme.fg_dim, theme.surface)
        draw.put(buf, x + 1, y + graph_h - 1, utils.pad_left("0", 4), theme.fg_dim, theme.surface)

        -- Draw bars
        local bar_w = math.max(1, math.floor(graph_w / graph_mins))
        for i = 1, graph_mins do
            local bx = graph_x + (i - 1) * bar_w
            if bx + bar_w > x + w - 1 then break end

            -- Extract bar (orange/accent2)
            local ev = ext_data[i] or 0
            local fill_e = math.floor((ev / max_val) * levels)
            local full_e = math.floor(fill_e / 2)
            local half_e = fill_e % 2 == 1

            -- Import bar (green/success) - draw on top
            local iv = imp_data[i] or 0
            local fill_i = math.floor((iv / max_val) * levels)
            local full_i = math.floor(fill_i / 2)
            local half_i = fill_i % 2 == 1

            for row = 0, graph_h - 1 do
                local ry = y + row
                local rfb = graph_h - 1 - row  -- rows from bottom

                -- Determine what to draw: extract has priority at bottom
                local e_here = rfb < full_e or (rfb == full_e and half_e)
                local e_full = rfb < full_e
                local i_here = rfb < full_i or (rfb == full_i and half_i)
                local i_full = rfb < full_i

                buf.setCursorPos(bx, ry)
                if e_full and i_full then
                    -- Both full: split - show extract
                    buf.setBackgroundColor(theme.accent2)
                    buf.write(string.rep(" ", bar_w))
                elseif e_full then
                    buf.setBackgroundColor(theme.accent2)
                    buf.write(string.rep(" ", bar_w))
                elseif i_full then
                    buf.setBackgroundColor(theme.success)
                    buf.write(string.rep(" ", bar_w))
                elseif rfb == full_e and half_e then
                    buf.setTextColor(theme.accent2)
                    buf.setBackgroundColor(theme.surface)
                    buf.write(string.rep("\131", bar_w))
                elseif rfb == full_i and half_i then
                    buf.setTextColor(theme.success)
                    buf.setBackgroundColor(theme.surface)
                    buf.write(string.rep("\131", bar_w))
                else
                    buf.setBackgroundColor(theme.surface)
                    buf.write(string.rep(" ", bar_w))
                end
            end
        end
        y = y + graph_h

        -- Legend
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "\127", theme.accent2, theme.surface)
        draw.put(buf, x + 4, y, "Extracted", theme.fg_dim, theme.surface)
        draw.put(buf, x + 16, y, "\127", theme.success, theme.surface)
        draw.put(buf, x + 18, y, "Imported", theme.fg_dim, theme.surface)
        y = y + 1

        -- Capacity sparkline
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "CAPACITY:", theme.fg_dim, theme.surface)
        if st.stats then
            local pct = math.floor(st.stats.usage_pct * 100)
            local pc = pct > 90 and theme.danger or (pct > 70 and theme.warning or theme.accent)
            draw.put(buf, x + 11, y, pct .. "%", pc, theme.surface)
        end

        -- Draw capacity sparkline from history
        local spark_data = {}
        for _, entry in ipairs(an.capacity_log) do
            table.insert(spark_data, entry[2] * 100)
        end
        if #spark_data > 0 then
            local spark_w = w - 20
            draw_sparkline(buf, draw, spark_data, x + 17, y, spark_w, theme.info, theme.surface)
        end
        y = y + 1

        -- ETA until full (5-min rolling average of net input)
        draw.fill(buf, y, x + w, theme.surface)
        local avg_window = 5
        local net_sum = 0
        local avg_count = 0
        for i = 1, avg_window do
            local m = cur_min - i
            local b = an.buckets[m]
            if b then
                net_sum = net_sum + (b.imported or 0) - (b.extracted or 0)
                avg_count = avg_count + 1
            end
        end
        local eta_str = "N/A"
        local eta_col = theme.fg_dim
        if avg_count > 0 then
            local net_per_min = net_sum / avg_count
            if net_per_min <= 0 then
                eta_str = "Not filling"
            elseif st.stats and st.stats.free_slots then
                -- Estimate remaining capacity in items (free slots * ~64 items per slot)
                local remaining_items = st.stats.free_slots * 64
                local mins = remaining_items / net_per_min
                eta_col = mins < 30 and theme.danger or (mins < 120 and theme.warning or theme.success)
                if mins < 60 then
                    eta_str = string.format("%.0fm", mins)
                elseif mins < 1440 then
                    eta_str = string.format("%.0fh %dm", math.floor(mins / 60), mins % 60)
                else
                    eta_str = string.format("%.1fd", mins / 1440)
                end
            end
        end
        draw.put(buf, x + 1, y, "ETA FULL: ", theme.fg_dim, theme.surface)
        draw.put(buf, x + 11, y, eta_str, eta_col, theme.surface)
        y = y + 1

        -- Totals
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, string.format("Peak: %d/min  |  Lifetime: %s out, %s in",
            an.peak_items_min,
            utils.format_number(an.totals.extracted or 0),
            utils.format_number(an.totals.imported or 0)), theme.fg_dim, theme.surface)
        y = y + 1

        -- Stack consolidation (defrag) status
        local ss = st.stack_stats
        if ss then
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 1, y, "DEFRAG:", theme.fg_dim, theme.surface)
            local frag_col = (ss.fragmented or 0) > 0 and theme.warning or theme.success
            local frag_str = (ss.fragmented or 0) > 0
                and string.format("%d split", ss.fragmented)
                or "clean"
            draw.put(buf, x + 9, y, frag_str, frag_col, theme.surface)
            draw.put(buf, x + 20, y,
                string.format("freed:%d  ops:%d  moved:%s",
                    ss.slots_freed or 0, ss.ops or 0,
                    utils.format_number(ss.items_moved or 0)),
                theme.fg_dim, theme.surface)
            y = y + 1

            draw.fill(buf, y, x + w, theme.surface)
            if ss.last_result then
                draw.put(buf, x + 1, y, "Last: " .. (ss.last_result or ""), theme.fg_dim, theme.surface)
                if (ss.last_time or 0) > 0 then
                    local ago = math.floor(os.clock() - ss.last_time)
                    local ago_str = ago < 60 and (ago .. "s ago") or (math.floor(ago / 60) .. "m ago")
                    draw.put(buf, x + w - #ago_str - 1, y, ago_str, theme.fg_dim, theme.surface)
                end
            end
        end

    elseif tab == 2 then
        -- SMELTING tab
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "Smelting Activity (last 20 min)", theme.fg, theme.surface)
        y = y + 1

        local graph_mins = math.min(20, w - 4)
        local smelt_in_data = {}
        local smelt_out_data = {}
        local fuel_data = {}
        local max_val = 1
        for i = graph_mins, 1, -1 do
            local m = cur_min - i
            local b = an.buckets[m] or {}
            local si = b.smelted_in or 0
            local so = b.smelted_out or 0
            local fu = b.fuel_pushed or 0
            table.insert(smelt_in_data, si)
            table.insert(smelt_out_data, so)
            table.insert(fuel_data, fu)
            if si > max_val then max_val = si end
            if so > max_val then max_val = so end
        end

        local graph_h = math.min(8, content_h - 8)
        local graph_x = x + 6
        local bar_w = math.max(1, math.floor((w - 8) / graph_mins))
        local levels = graph_h * 2

        -- Y-axis
        draw.put(buf, x + 1, y, utils.pad_left(tostring(max_val), 4), theme.fg_dim, theme.surface)
        draw.put(buf, x + 1, y + graph_h - 1, utils.pad_left("0", 4), theme.fg_dim, theme.surface)

        -- Draw smelt bars (in = orange, out = lime)
        for i = 1, graph_mins do
            local bx = graph_x + (i - 1) * bar_w
            if bx + bar_w > x + w - 1 then break end

            local si = smelt_in_data[i] or 0
            local so = smelt_out_data[i] or 0
            local fill_in = math.floor((si / max_val) * levels)
            local fill_out = math.floor((so / max_val) * levels)

            for row = 0, graph_h - 1 do
                local ry = y + row
                local rfb = graph_h - 1 - row
                local in_full = rfb < math.floor(fill_in / 2)
                local in_half = rfb == math.floor(fill_in / 2) and fill_in % 2 == 1
                local out_full = rfb < math.floor(fill_out / 2)
                local out_half = rfb == math.floor(fill_out / 2) and fill_out % 2 == 1

                buf.setCursorPos(bx, ry)
                if out_full then
                    buf.setBackgroundColor(theme.success)
                    buf.write(string.rep(" ", bar_w))
                elseif in_full then
                    buf.setBackgroundColor(theme.warning)
                    buf.write(string.rep(" ", bar_w))
                elseif out_half then
                    buf.setTextColor(theme.success)
                    buf.setBackgroundColor(theme.surface)
                    buf.write(string.rep("\131", bar_w))
                elseif in_half then
                    buf.setTextColor(theme.warning)
                    buf.setBackgroundColor(theme.surface)
                    buf.write(string.rep("\131", bar_w))
                else
                    buf.setBackgroundColor(theme.surface)
                    buf.write(string.rep(" ", bar_w))
                end
            end
        end
        y = y + graph_h

        -- Legend
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "\127", theme.warning, theme.surface)
        draw.put(buf, x + 4, y, "Ores In", theme.fg_dim, theme.surface)
        draw.put(buf, x + 14, y, "\127", theme.success, theme.surface)
        draw.put(buf, x + 16, y, "Smelted Out", theme.fg_dim, theme.surface)
        y = y + 1

        -- Fuel sparkline
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "FUEL USED:", theme.fg_dim, theme.surface)
        local fuel_spark_w = w - 14
        draw_sparkline(buf, draw, fuel_data, x + 12, y, fuel_spark_w, theme.accent2, theme.surface)
        y = y + 1

        -- Smelting stats
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, string.format("Total: %s smelted  |  %s fuel used",
            utils.format_number(an.totals.smelted_out or 0),
            utils.format_number(an.totals.fuel_pushed or 0)), theme.fg_dim, theme.surface)
        y = y + 1

        -- Efficiency
        local total_in = an.totals.smelted_in or 0
        local total_out = an.totals.smelted_out or 0
        local eff = total_in > 0 and math.floor(total_out / total_in * 100) or 0
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, string.format("Efficiency: %d%%  |  Furnaces: %d  |  %s",
            eff, st.furnace_count or 0,
            st.smelting_enabled and "AUTO ON" or "AUTO OFF"),
            theme.fg_dim, theme.surface)

        -- Fuel ratio info
        y = y + 1
        draw.fill(buf, y, x + w, theme.surface)
        local total_fuel = an.totals.fuel_pushed or 0
        local ratio = total_fuel > 0 and string.format("%.1f ores/coal", total_out / total_fuel) or "N/A"
        draw.put(buf, x + 1, y, "Fuel ratio: " .. ratio .. "  (optimal: 8.0)", theme.fg_dim, theme.surface)

    elseif tab == 3 then
        -- TOP ITEMS tab - extracted + imported + consumed (craft/smelt)
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "Top Items (All Time)", theme.fg, theme.surface)
        y = y + 1

        -- Merge all sources into one sorted list
        local merged = {}
        local all_names = {}
        for name, _ in pairs(an.top_extracted or {}) do all_names[name] = true end
        for name, _ in pairs(an.top_imported or {}) do all_names[name] = true end
        for name, _ in pairs(an.top_craft_used or {}) do all_names[name] = true end
        for name, _ in pairs(an.top_smelt_used or {}) do all_names[name] = true end

        for name, _ in pairs(all_names) do
            local ext = (an.top_extracted or {})[name] or 0
            local imp = (an.top_imported or {})[name] or 0
            local craft = (an.top_craft_used or {})[name] or 0
            local smelt = (an.top_smelt_used or {})[name] or 0
            local used = craft + smelt
            table.insert(merged, {name = name, extracted = ext, imported = imp, used = used, total = ext + imp + used})
        end
        table.sort(merged, function(a, b) return a.total > b.total end)

        local list_h = content_h - 3  -- leave room for legend
        local max_display = math.min(list_h, #merged)
        local top_max = merged[1] and merged[1].total or 1

        -- Legend row
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "\127", theme.accent2, theme.surface)
        draw.put(buf, x + 4, y, "Out", theme.fg_dim, theme.surface)
        draw.put(buf, x + 10, y, "\127", theme.success, theme.surface)
        draw.put(buf, x + 12, y, "In", theme.fg_dim, theme.surface)
        draw.put(buf, x + 18, y, "\127", theme.warning, theme.surface)
        draw.put(buf, x + 20, y, "Used", theme.fg_dim, theme.surface)
        y = y + 1

        if #merged == 0 then
            for r = y, y + list_h - 1 do
                draw.fill(buf, r, x + w, theme.surface)
            end
            draw.center(buf, "No activity yet", y + math.floor(list_h / 2), x + w, theme.fg_dim, theme.surface)
        else
            for i = 1 + scroll, math.min(max_display + scroll, #merged) do
                local item = merged[i]
                if not item then break end

                local rbg = (i % 2 == 0) and theme.surface2 or theme.surface
                draw.fill(buf, y, x + w, rbg)

                -- Rank
                draw.put(buf, x + 1, y, string.format("#%d", i), theme.accent, rbg)

                -- Name
                local nw = w - 32
                local dn = item.name
                if #dn > nw then dn = dn:sub(1, nw - 2) .. ".." end
                draw.put(buf, x + 5, y, dn, theme.fg, rbg)

                -- Extracted count (purple)
                if item.extracted > 0 then
                    draw.put(buf, x + w - 27, y, utils.pad_left(utils.format_number(item.extracted), 6), theme.accent2, rbg)
                end

                -- Imported count (green)
                if item.imported > 0 then
                    draw.put(buf, x + w - 20, y, utils.pad_left(utils.format_number(item.imported), 6), theme.success, rbg)
                end

                -- Used count (orange) - craft + smelt ingredients consumed
                if item.used > 0 then
                    draw.put(buf, x + w - 13, y, utils.pad_left(utils.format_number(item.used), 6), theme.warning, rbg)
                end

                -- Mini bar showing proportion
                local bar_total = math.floor((item.total / top_max) * 6)
                if bar_total > 0 then
                    local ext_part = math.max(0, math.floor((item.extracted / top_max) * 6))
                    local imp_part = math.max(0, math.floor((item.imported / top_max) * 6))
                    local used_part = math.max(0, bar_total - ext_part - imp_part)
                    draw.put(buf, x + w - 6, y, string.rep("\127", math.min(ext_part, 6)), theme.accent2, rbg)
                    local pos = ext_part
                    if pos < 6 and imp_part > 0 then
                        draw.put(buf, x + w - 6 + pos, y, string.rep("\127", math.min(imp_part, 6 - pos)), theme.success, rbg)
                        pos = pos + imp_part
                    end
                    if pos < 6 and used_part > 0 then
                        draw.put(buf, x + w - 6 + pos, y, string.rep("\127", math.min(used_part, 6 - pos)), theme.warning, rbg)
                    end
                end

                y = y + 1
            end

            -- Fill remaining space
            for r = y, ctx.content_y + h - 2 do
                draw.fill(buf, r, x + w, theme.surface)
            end

            -- Scroll info
            y = ctx.content_y + h - 2
            if #merged > max_display then
                draw.fill(buf, y, x + w, theme.surface2)
                draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
                hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}

                local info = string.format("%d-%d of %d", scroll + 1,
                    math.min(scroll + max_display, #merged), #merged)
                draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)

                local max_s = math.max(0, #merged - max_display)
                draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_s)
                hits.scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
                hits.max_scroll = max_s
            end
        end

    elseif tab == 4 then
        -- FARMS tab - per-farm breakdown with I/O ratios
        local farms_state = ctx.state.farms
        local plots = farms_state and farms_state.plots or {}

        -- Global totals header
        draw.fill(buf, y, x + w, theme.surface)
        local farm_sup = an.totals.farm_supplied or 0
        local farm_har = an.totals.farm_harvested or 0
        draw.put(buf, x + 1, y, "Farm I/O Analytics", theme.fg, theme.surface)
        draw.put(buf, x + w - 24, y,
            string.format("S:%s H:%s", utils.format_number(farm_sup), utils.format_number(farm_har)),
            theme.fg_dim, theme.surface)
        y = y + 1

        -- Legend
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "\127", theme.accent2, theme.surface)
        draw.put(buf, x + 4, y, "In (supplied)", theme.fg_dim, theme.surface)
        draw.put(buf, x + 19, y, "\127", theme.success, theme.surface)
        draw.put(buf, x + 21, y, "Out (harvested)", theme.fg_dim, theme.surface)
        y = y + 1

        -- Build flat rows: farm headers + their item rows
        local rows = {}  -- {type="farm"|"item", ...}
        for pi, plot in ipairs(plots) do
            local stats = plot.stats or {}
            local sup_items = stats.supplied_by_item or {}
            local har_items = stats.harvested_by_item or {}
            local total_in = stats.items_supplied or 0
            local total_out = stats.items_harvested or 0

            -- Compute ratio string
            local ratio_str = ""
            if total_in > 0 and total_out > 0 then
                local r = total_in / total_out
                if r >= 1 then
                    ratio_str = string.format("%.1f:1 in/out", r)
                else
                    ratio_str = string.format("1:%.1f in/out", 1 / r)
                end
            elseif total_in > 0 then
                ratio_str = "no output yet"
            elseif total_out > 0 then
                ratio_str = "no input"
            end

            table.insert(rows, {
                type = "farm", name = plot.name or ("Farm " .. pi),
                total_in = total_in, total_out = total_out,
                ratio = ratio_str, enabled = plot.enabled,
            })

            -- Collect unique items from both sides
            local all_items = {}
            for name, _ in pairs(sup_items) do all_items[name] = true end
            for name, _ in pairs(har_items) do all_items[name] = true end

            -- Sort items by total activity
            local item_list = {}
            for name, _ in pairs(all_items) do
                local s = sup_items[name] or 0
                local h = har_items[name] or 0
                table.insert(item_list, {name = name, supplied = s, harvested = h, total = s + h})
            end
            table.sort(item_list, function(a, b) return a.total > b.total end)

            for _, item in ipairs(item_list) do
                -- Skip junk items (<1% of output) - likely accidental
                if total_out > 0 and item.harvested > 0 and item.harvested < total_out * 0.01 and item.supplied == 0 then
                    goto skip_item
                end
                -- Per-item ratio (only if item appears on both sides within this farm)
                local item_ratio = ""
                if item.supplied > 0 and item.harvested > 0 then
                    local r = item.supplied / item.harvested
                    if r >= 1 then
                        item_ratio = string.format("%.1f:1", r)
                    else
                        item_ratio = string.format("1:%.1f", 1 / r)
                    end
                end
                table.insert(rows, {
                    type = "item", name = item.name,
                    supplied = item.supplied, harvested = item.harvested,
                    ratio = item_ratio,
                })
                ::skip_item::
            end
        end

        local list_h = content_h - 4
        local max_display = math.min(list_h, #rows)
        local total_rows = #rows

        if total_rows == 0 then
            for r = y, y + list_h - 1 do
                draw.fill(buf, r, x + w, theme.surface)
            end
            draw.center(buf, "No farms configured", y + math.floor(list_h / 2), x + w, theme.fg_dim, theme.surface)
        else
            local drawn = 0
            for i = 1 + scroll, total_rows do
                if drawn >= max_display then break end
                local row = rows[i]
                if not row then break end

                if row.type == "farm" then
                    -- Farm header row
                    draw.fill(buf, y, x + w, theme.surface2)
                    local en_col = row.enabled and theme.success or theme.fg_dim
                    draw.put(buf, x + 1, y, "\7", en_col, theme.surface2)
                    draw.put(buf, x + 3, y, row.name:sub(1, 16), theme.accent, theme.surface2)
                    -- Totals
                    if row.total_in > 0 or row.total_out > 0 then
                        draw.put(buf, x + 20, y,
                            string.format("IN:%s OUT:%s",
                                utils.format_number(row.total_in),
                                utils.format_number(row.total_out)),
                            theme.fg_dim, theme.surface2)
                    end
                    -- Ratio
                    if row.ratio ~= "" then
                        local rc = theme.info
                        if row.ratio == "no output yet" then rc = theme.fg_dim end
                        draw.put(buf, x + w - #row.ratio - 1, y, row.ratio, rc, theme.surface2)
                    end
                else
                    -- Item row
                    local rbg = theme.surface
                    draw.fill(buf, y, x + w, rbg)

                    -- Indented item name
                    local dn = row.name:gsub("^minecraft:", "")
                    if #dn > 18 then dn = dn:sub(1, 17) .. "." end
                    draw.put(buf, x + 4, y, dn, theme.fg, rbg)

                    -- Supplied count
                    if row.supplied > 0 then
                        draw.put(buf, x + 23, y,
                            utils.pad_left(utils.format_number(row.supplied), 6),
                            theme.accent2, rbg)
                    end

                    -- Harvested count
                    if row.harvested > 0 then
                        draw.put(buf, x + 30, y,
                            utils.pad_left(utils.format_number(row.harvested), 6),
                            theme.success, rbg)
                    end

                    -- Per-item ratio
                    if row.ratio ~= "" then
                        draw.put(buf, x + 38, y, row.ratio, theme.info, rbg)
                    end

                    -- Direction indicator
                    if row.supplied > 0 and row.harvested == 0 then
                        draw.put(buf, x + 2, y, "\16", theme.accent2, rbg)  -- arrow right (input)
                    elseif row.harvested > 0 and row.supplied == 0 then
                        draw.put(buf, x + 2, y, "\17", theme.success, rbg)  -- arrow left (output)
                    elseif row.supplied > 0 and row.harvested > 0 then
                        draw.put(buf, x + 2, y, "\29", theme.info, rbg)    -- both directions
                    end
                end

                y = y + 1
                drawn = drawn + 1
            end

            -- Fill remaining
            for r = y, ctx.content_y + h - 2 do
                draw.fill(buf, r, x + w, theme.surface)
            end

            -- Scroll controls
            y = ctx.content_y + h - 2
            if total_rows > max_display then
                draw.fill(buf, y, x + w, theme.surface2)
                draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
                hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}

                local info = string.format("%d-%d of %d", scroll + 1,
                    math.min(scroll + max_display, total_rows), total_rows)
                draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)

                local max_s = math.max(0, total_rows - max_display)
                draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_s)
                hits.scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
                hits.max_scroll = max_s
            end
        end
    end

    -- Fill any remaining rows
    for r = y + 1, ctx.content_y + h - 1 do
        draw.fill(buf, r, x + w, theme.surface)
    end
end

function app.main(ctx)
    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3], ev[4]

            -- Tab clicks
            if hits.tabs then
                for ti = 1, TAB_COUNT do
                    if hits.tabs[ti] and ctx.draw.hit_test(hits.tabs[ti], tx, ty) then
                        tab = ti
                        scroll = 0
                        break
                    end
                end
            end

            -- Scroll buttons
            if hits.scroll_up and ctx.draw.hit_test(hits.scroll_up, tx, ty) then
                if scroll > 0 then scroll = scroll - 1 end
            elseif hits.scroll_down and ctx.draw.hit_test(hits.scroll_down, tx, ty) then
                local max_s = hits.max_scroll or 0
                if scroll < max_s then scroll = scroll + 1 end
            end

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            local max_s = hits.max_scroll or 0
            scroll = math.max(0, math.min(max_s, scroll + dir))
        end
    end
end

return app
