-- =============================================
-- WRAITH OS - DRAWING PRIMITIVES
-- =============================================
-- All functions draw to a provided buffer (term-like object).

local draw = {}

-- Set colors on buffer
function draw.setC(buf, fg, bg)
    if fg then buf.setTextColor(fg) end
    if bg then buf.setBackgroundColor(bg) end
end

-- Fill entire line with background color
function draw.fill(buf, y, w, bg)
    buf.setCursorPos(1, y)
    if bg then buf.setBackgroundColor(bg) end
    buf.write(string.rep(" ", w))
end

-- Fill range of lines
function draw.fillR(buf, y1, y2, w, bg)
    for r = y1, y2 do draw.fill(buf, r, w, bg) end
end

-- Fill a rectangular region
function draw.fillRect(buf, x, y, w, h, bg)
    if bg then buf.setBackgroundColor(bg) end
    for r = 0, h - 1 do
        buf.setCursorPos(x, y + r)
        buf.write(string.rep(" ", w))
    end
end

-- Put text at position
function draw.put(buf, x, y, text, fg, bg)
    buf.setCursorPos(x, y)
    draw.setC(buf, fg, bg)
    buf.write(text)
end

-- Center text on line
function draw.center(buf, text, y, w, fg, bg)
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    draw.put(buf, x, y, text, fg, bg)
end

-- Horizontal rule
function draw.rule(buf, y, w, fg, bg)
    draw.fill(buf, y, w, bg)
    draw.put(buf, 1, y, string.rep("\140", w), fg, bg)
end

-- Section header (gray bar with label)
function draw.header(buf, y, w, title, fg, bg)
    draw.fill(buf, y, w, bg)
    draw.put(buf, 2, y, " " .. title .. " ", fg, bg)
    return y + 1
end

-- Progress bar
function draw.progress(buf, x, y, w, pct, fg, bg)
    pct = math.max(0, math.min(1, pct))
    local filled = math.floor(pct * w)
    buf.setCursorPos(x, y)
    if fg then buf.setBackgroundColor(fg) end
    buf.write(string.rep(" ", filled))
    if bg then buf.setBackgroundColor(bg) end
    buf.write(string.rep(" ", w - filled))
end

-- Button (returns hit area table)
function draw.button(buf, x, y, w, h, text, bg, fg, enabled)
    local _wraith = _G._wraith
    local dis_bg = (_wraith and _wraith.theme and _wraith.theme.btn_disabled_bg) or colors.blue
    local dis_fg = (_wraith and _wraith.theme and _wraith.theme.btn_disabled_fg) or colors.lightGray
    local abg = (enabled ~= false) and bg or dis_bg
    local afg = (enabled ~= false) and (fg or colors.white) or dis_fg
    for r = 0, h - 1 do
        buf.setCursorPos(x, y + r)
        draw.setC(buf, afg, abg)
        if r == math.floor(h / 2) then
            local pad = math.max(0, math.floor((w - #text) / 2))
            local s = string.rep(" ", pad) .. text
            buf.write((s .. string.rep(" ", math.max(0, w - #s))):sub(1, w))
        else
            buf.write(string.rep(" ", w))
        end
    end
    return {x = x, y = y, w = w, h = h, enabled = enabled}
end

-- Check if point is inside a hit area
function draw.hit_test(area, tx, ty)
    return area and
           tx >= area.x and tx < area.x + area.w and
           ty >= area.y and ty < area.y + area.h
end

-- Draw a box border (single line style using special chars)
function draw.box(buf, x, y, w, h, fg, bg)
    -- Top border
    draw.put(buf, x, y, "\151" .. string.rep("\140", w - 2) .. "\148", fg, bg)
    -- Sides
    for r = 1, h - 2 do
        draw.put(buf, x, y + r, "\149", fg, bg)
        draw.put(buf, x + w - 1, y + r, "\149", fg, bg)
    end
    -- Bottom border
    draw.put(buf, x, y + h - 1, "\138" .. string.rep("\140", w - 2) .. "\133", fg, bg)
end

return draw
