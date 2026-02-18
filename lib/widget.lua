-- =============================================
-- WRAITH OS - REUSABLE UI WIDGETS
-- =============================================
-- Widgets draw to a buffer at given coordinates.
-- They return hit areas for touch detection.

local widget = {}

-- Scrollable list widget
-- Returns: {items_drawn, hit_areas, scroll_up_area, scroll_dn_area}
function widget.list(buf, x, y, w, h, items, scroll, selected, theme, format_fn)
    local draw = _G._wraith.draw
    local utils = _G._wraith.utils
    local hit_areas = {}
    local max_scroll = math.max(0, #items - h)
    if scroll > max_scroll then scroll = max_scroll end

    if #items == 0 then
        draw.fillR(buf, y, y + h - 1, w, theme.bg)
        draw.center(buf, "No items", y + math.floor(h / 2), w, theme.fg_dim, theme.bg)
        return {drawn = 0, hits = hit_areas, scroll = scroll}
    end

    for i = 1, h do
        local idx = scroll + i
        local item = items[idx]
        local row_y = y + i - 1
        if item then
            local is_sel = (idx == selected)
            local rbg = is_sel and theme.highlight or theme.bg
            local rfg = is_sel and theme.bg or theme.fg
            draw.fill(buf, row_y, w, rbg)
            if is_sel then
                draw.put(buf, x, row_y, "\16", theme.accent, rbg)
            end
            if format_fn then
                format_fn(buf, x + 2, row_y, w - 3, item, is_sel, rfg, rbg)
            else
                local text = tostring(item)
                if #text > w - 3 then text = text:sub(1, w - 5) .. ".." end
                draw.put(buf, x + 2, row_y, text, rfg, rbg)
            end
            hit_areas[idx] = {x = x, y = row_y, w = w, h = 1}
        else
            draw.fill(buf, row_y, w, theme.bg)
        end
    end

    return {drawn = math.min(h, #items), hits = hit_areas, scroll = scroll, max_scroll = max_scroll}
end

-- Search bar widget
function widget.search_bar(buf, x, y, w, query, theme)
    local draw = _G._wraith.draw
    draw.put(buf, x, y, "\16", theme.accent, theme.bg)
    draw.put(buf, x + 2, y, "[", theme.fg_dim, theme.bg)
    local sw = w - 5
    local display = query ~= "" and query or "search..."
    local fg = query ~= "" and theme.fg or theme.fg_dim
    draw.put(buf, x + 3, y, display:sub(1, sw), fg, theme.bg)
    if #display < sw then
        buf.write(string.rep(" ", sw - #display))
    end
    draw.put(buf, x + 3 + sw, y, "]", theme.fg_dim, theme.bg)
    return {x = x, y = y, w = w, h = 1}
end

-- Action button row (multiple buttons in a row)
function widget.button_row(buf, x, y, w, buttons, theme)
    local draw = _G._wraith.draw
    local n = #buttons
    if n == 0 then return {} end
    local gap = 1
    local bw = math.floor((w - (n - 1) * gap) / n)
    if bw < 6 then bw = 6 end
    local areas = {}
    local bx = x

    for _, b in ipairs(buttons) do
        local bg = b.bg or theme.btn_bg
        local fg = b.fg or theme.btn_text
        local area = draw.button(buf, bx, y, bw, 1, b.text, bg, fg, b.enabled)
        area.id = b.id
        area.callback = b.callback
        areas[b.id] = area
        bx = bx + bw + gap
    end

    return areas
end

-- Toast notification
function widget.toast(buf, x, y, w, msg, color, theme)
    local draw = _G._wraith.draw
    draw.fill(buf, y, w, theme.bg)
    local icon_char = "\7 "
    local text = icon_char .. msg
    if #text > w - 2 then text = text:sub(1, w - 4) .. ".." end
    draw.put(buf, x, y, text, color or theme.fg, theme.bg)
end

-- Capacity/progress bar with label
function widget.capacity_bar(buf, x, y, w, pct, label, theme)
    local draw = _G._wraith.draw
    draw.put(buf, x, y, label or "CAP", theme.fg_dim, theme.bg)
    local bar_x = x + #(label or "CAP") + 1
    local bar_w = w - #(label or "CAP") - 7
    local fg = pct > 0.9 and theme.danger or (pct > 0.7 and theme.warning or theme.accent)
    draw.progress(buf, bar_x, y, bar_w, pct, fg, theme.border)
    draw.put(buf, bar_x + bar_w + 1, y, string.format("%3d%%", math.floor(pct * 100)), theme.fg_dim, theme.bg)
end

return widget
