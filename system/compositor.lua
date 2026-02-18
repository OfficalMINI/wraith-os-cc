-- =============================================
-- WRAITH OS - COMPOSITOR
-- =============================================
-- Single master buffer rendering: desktop -> windows -> taskbar

local compositor = {}

local state, config, theme, draw, wm, desktop, taskbar

local buf = nil
local W, H = 0, 0

function compositor.init(s, c, t, d, w, dt, tb)
    state = s
    config = c
    theme = t
    draw = d
    wm = w
    desktop = dt
    taskbar = tb
end

-- Initialize or reinitialize the master buffer
function compositor.setup(mon)
    W, H = mon.getSize()
    state.mon_w = W
    state.mon_h = H
    buf = window.create(mon, 1, 1, W, H, false)
    return buf
end

-- Get the master buffer
function compositor.get_buffer()
    return buf
end

function compositor.get_size()
    return W, H
end

-- Full render frame
function compositor.render(app_draw_fns)
    if not buf then return end

    -- Check for monitor resize
    local mon = state.monitor
    if mon then
        local nw, nh = mon.getSize()
        if nw ~= W or nh ~= H then
            compositor.setup(mon)
        end
    end

    -- Clear buffer
    draw.setC(buf, theme.fg, theme.bg)
    buf.clear()

    -- Layer 1: Desktop (wallpaper + icons)
    desktop.render(buf, W, H)

    -- Layer 2: Windows (bottom to top z-order)
    local visible = wm.visible_windows()
    for _, win in ipairs(visible) do
        wm.draw_titlebar(buf, win)

        if win.content_win_active then
            -- Real content_win handles rendering (Terminal/YouCube playback)
            draw.fillRect(buf, win.x, win.y + win.titlebar_h, win.w, win.h - win.titlebar_h, theme.bg)
        else
            -- Standard master-buffer rendering
            draw.fillRect(buf, win.x, win.y + win.titlebar_h, win.w, win.h - win.titlebar_h, theme.surface)

            if app_draw_fns and app_draw_fns[win.id] then
                app_draw_fns[win.id](buf, win)
            end

            -- Subtle border
            local bfg = win.focused and theme.accent or theme.border
            for r = win.y + win.titlebar_h, win.y + win.h - 1 do
                draw.put(buf, win.x, r, "\149", bfg, theme.surface)
            end
            for r = win.y + win.titlebar_h, win.y + win.h - 1 do
                draw.put(buf, win.x + win.w - 1, r, "\149", bfg, theme.surface)
            end
            draw.put(buf, win.x, win.y + win.h - 1,
                string.rep("\140", win.w), bfg, theme.surface)
        end
    end

    -- Layer 3: Taskbar (always on top)
    local taskbar_areas = taskbar.render(buf, W, H)

    -- Flush to monitor
    buf.setVisible(true)
    buf.setVisible(false)

    -- Flush real windows only when actively rendering
    for _, win in ipairs(visible) do
        if win.content_win and win.content_win_active then
            win.content_win.setVisible(true)
            win.content_win.setVisible(false)
        end
    end

    return taskbar_areas
end

return compositor
