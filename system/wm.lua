-- =============================================
-- WRAITH OS - WINDOW MANAGER
-- =============================================

local wm = {}

local state, config, theme, draw

function wm.init(s, c, t, d)
    state = s
    config = c
    theme = t
    draw = d
end

-- Create a new window
function wm.create(app_id, title, x, y, w, h, opts)
    opts = opts or {}
    local tb_h = config.window.titlebar_h

    -- Default position: cascading from top-left
    local win_count = #state.windows
    if not x then x = 4 + (win_count % 5) * 3 end
    if not y then y = 3 + (win_count % 5) * 2 end

    -- Clamp to monitor bounds
    w = math.min(w or config.window.default_w, state.mon_w - 2)
    h = math.min(h or config.window.default_h, state.mon_h - 4)
    x = math.max(1, math.min(x, state.mon_w - w + 1))
    y = math.max(1, math.min(y, state.mon_h - h - 1))  -- leave room for taskbar

    local id = state.next_window_id
    state.next_window_id = id + 1

    -- Create a real CC window for the content area (needed for term.redirect)
    local content_win = nil
    if opts.needs_real_window and state.monitor then
        content_win = window.create(state.monitor, x, y + tb_h, w, h - tb_h, false)
    end

    local win = {
        id = id,
        app_id = app_id,
        title = title,
        x = x,
        y = y,
        w = w,
        h = h,
        titlebar_h = tb_h,
        visible = true,
        minimized = false,
        focused = false,
        content_win = content_win,    -- real window for YouCube-type apps
        app_coroutine = nil,
        event_filter = nil,
        app_state = {},               -- per-app state
    }

    table.insert(state.windows, win)
    wm.focus(id)

    return win
end

-- Close a window
function wm.close(id)
    for i, win in ipairs(state.windows) do
        if win.id == id then
            -- Kill the app coroutine
            win.app_coroutine = nil
            -- Destroy real window if exists
            if win.content_win then
                win.content_win.setVisible(false)
                win.content_win = nil
            end
            table.remove(state.windows, i)

            -- Focus next window
            if state.focused_id == id then
                state.focused_id = nil
                if #state.windows > 0 then
                    wm.focus(state.windows[#state.windows].id)
                end
            end
            return true
        end
    end
    return false
end

-- Minimize a window
function wm.minimize(id)
    local win = wm.get(id)
    if win then
        win.minimized = true
        win.visible = false
        if win.content_win then
            win.content_win.setVisible(false)
        end
        -- Focus next visible window
        if state.focused_id == id then
            state.focused_id = nil
            for i = #state.windows, 1, -1 do
                if not state.windows[i].minimized then
                    wm.focus(state.windows[i].id)
                    break
                end
            end
        end
    end
end

-- Restore a minimized window
function wm.restore(id)
    local win = wm.get(id)
    if win then
        win.minimized = false
        win.visible = true
        wm.focus(id)
    end
end

-- Focus a window (bring to top of z-order)
function wm.focus(id)
    -- Unfocus all
    for _, w in ipairs(state.windows) do
        w.focused = false
    end

    -- Move target to end (top of z-order) and focus it
    for i, w in ipairs(state.windows) do
        if w.id == id then
            table.remove(state.windows, i)
            table.insert(state.windows, w)
            w.focused = true
            state.focused_id = id
            return
        end
    end
end

-- Get window by ID
function wm.get(id)
    for _, w in ipairs(state.windows) do
        if w.id == id then return w end
    end
    return nil
end

-- Get focused window
function wm.get_focused()
    if state.focused_id then
        return wm.get(state.focused_id)
    end
    return nil
end

-- Find window containing point (x, y) - checks top-to-bottom (reverse z)
function wm.window_at(tx, ty)
    for i = #state.windows, 1, -1 do
        local w = state.windows[i]
        if w.visible and not w.minimized then
            if tx >= w.x and tx < w.x + w.w and
               ty >= w.y and ty < w.y + w.h then
                return w
            end
        end
    end
    return nil
end

-- Check if point is in a window's title bar
function wm.in_titlebar(win, tx, ty)
    return ty >= win.y and ty < win.y + win.titlebar_h and
           tx >= win.x and tx < win.x + win.w
end

-- Check if point hits close button (red dot at x+1)
function wm.hit_close(win, tx, ty)
    return ty == win.y and tx >= win.x and tx <= win.x + 1
end

-- Check if point hits minimize button (yellow dot at x+3)
function wm.hit_minimize(win, tx, ty)
    return ty == win.y and tx >= win.x + 2 and tx <= win.x + 4
end

-- Translate monitor coords to window content-local coords
function wm.to_local(win, tx, ty)
    return tx - win.x + 1, ty - (win.y + win.titlebar_h) + 1
end

-- Check if point is in window content area
function wm.in_content(win, tx, ty)
    return tx >= win.x and tx < win.x + win.w and
           ty >= win.y + win.titlebar_h and ty < win.y + win.h
end

-- Draw a window's title bar (macOS traffic light style)
function wm.draw_titlebar(buf, win)
    local bg = win.focused and theme.titlebar_focused or theme.titlebar_unfocused
    local fg = win.focused and theme.titlebar_text or theme.titlebar_text_dim

    -- Fill title bar
    buf.setCursorPos(win.x, win.y)
    draw.setC(buf, fg, bg)
    buf.write(string.rep(" ", win.w))

    -- Traffic light buttons (colored dots)
    if win.focused then
        draw.put(buf, win.x + 1, win.y, "\7", theme.close_btn, bg)      -- red
        draw.put(buf, win.x + 3, win.y, "\7", theme.minimize_btn, bg)   -- yellow
        draw.put(buf, win.x + 5, win.y, "\7", theme.zoom_btn, bg)      -- green
    else
        draw.put(buf, win.x + 1, win.y, "\7", theme.border, bg)
        draw.put(buf, win.x + 3, win.y, "\7", theme.border, bg)
        draw.put(buf, win.x + 5, win.y, "\7", theme.border, bg)
    end

    -- Centered title text
    local title = win.title
    local max_title = win.w - 8
    if #title > max_title then title = title:sub(1, max_title - 2) .. ".." end
    local title_x = win.x + math.floor((win.w - #title) / 2)
    draw.put(buf, title_x, win.y, title, fg, bg)
end

-- Get all visible windows in z-order (bottom to top)
function wm.visible_windows()
    local result = {}
    for _, w in ipairs(state.windows) do
        if w.visible and not w.minimized then
            table.insert(result, w)
        end
    end
    return result
end

-- Check if any window is open for a given app
function wm.is_app_running(app_id)
    for _, w in ipairs(state.windows) do
        if w.app_id == app_id then return true, w.id end
    end
    return false
end

return wm
