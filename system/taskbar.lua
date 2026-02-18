-- =============================================
-- WRAITH OS - TASKBAR
-- =============================================
-- macOS-style dock: subtle glass bar with app tabs and clock

local taskbar = {}

local state, config, theme, draw, utils

function taskbar.init(s, c, t, d, u)
    state = s
    config = c
    theme = t
    draw = d
    utils = u
end

-- Draw the taskbar onto the buffer
-- Returns hit areas for tab clicks
function taskbar.render(buf, W, H)
    local areas = {}
    local sep_y = H - 1   -- subtle separator line
    local bar_y = H       -- main dock row

    -- Status bar / separator line
    draw.fill(buf, sep_y, W, theme.bg)
    if state.status_msg and state.status_msg ~= "" then
        -- Show status message on the separator line
        local msg = state.status_msg
        if #msg > W - 2 then msg = msg:sub(1, W - 4) .. ".." end
        draw.put(buf, 2, sep_y, msg, state.status_color or theme.fg_dim, theme.bg)
    else
        -- Subtle separator
        buf.setCursorPos(1, sep_y)
        draw.setC(buf, theme.border, theme.bg)
        buf.write(string.rep("\140", W))
    end

    -- Dock background (surface2 = frosted glass feel)
    draw.fill(buf, bar_y, W, theme.taskbar_bg)

    -- Wraith logo (minimal dot + label)
    draw.put(buf, 2, bar_y, "\7", theme.accent, theme.taskbar_bg)
    areas.logo = {x = 1, y = bar_y, w = 3, h = 1}

    -- Running app tabs (centered in available space)
    local tab_start = 5
    local clock = utils.format_time(os.time())
    local day_str = "D" .. os.day()
    local right_width = #day_str + 1 + #clock + 3  -- day + space + clock + padding + net dot
    local tab_end = W - right_width

    local tx = tab_start
    for _, win in ipairs(state.windows) do
        local label = win.title:sub(1, 10)

        if tx + #label + 2 > tab_end then break end

        if win.focused then
            -- Focused: accent pill
            draw.put(buf, tx, bar_y, " " .. label .. " ", theme.taskbar_bg, theme.accent)
        elseif win.minimized then
            -- Minimized: dim with no indicator
            draw.put(buf, tx, bar_y, " " .. label .. " ", theme.fg_dark, theme.taskbar_bg)
        else
            -- Running but unfocused: normal text with dot
            draw.put(buf, tx, bar_y, " " .. label .. " ", theme.taskbar_fg, theme.taskbar_bg)
            -- Small running indicator dot on separator line
            local dot_x = tx + math.floor(#label / 2) + 1
            draw.put(buf, dot_x, sep_y, "\7", theme.accent, theme.bg)
        end

        local tab_w = #label + 2
        areas[win.id] = {x = tx, y = bar_y, w = tab_w, h = 1, win_id = win.id}
        tx = tx + tab_w + 1
    end

    -- Right side: network dot + day + clock
    local net_col = state.network.ws_connected and theme.success
        or (state.network.modem_side and theme.fg_dim or theme.danger)
    draw.put(buf, W - right_width + 1, bar_y, "\7", net_col, theme.taskbar_bg)
    draw.put(buf, W - right_width + 3, bar_y, day_str, theme.fg_dim, theme.taskbar_bg)
    draw.put(buf, W - #clock, bar_y, clock, theme.fg, theme.taskbar_bg)

    return areas
end

-- Handle touch on taskbar
-- Returns: action string and data
function taskbar.handle_touch(tx, ty, areas)
    -- Check logo button
    if areas.logo and draw.hit_test(areas.logo, tx, ty) then
        return "toggle_desktop"
    end

    -- Check app tabs
    for key, area in pairs(areas) do
        if type(key) == "number" and area.win_id and draw.hit_test(area, tx, ty) then
            return "focus_window", area.win_id
        end
    end

    return nil
end

return taskbar
