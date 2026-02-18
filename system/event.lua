-- =============================================
-- WRAITH OS - EVENT ROUTER
-- =============================================

local event = {}

local state, wm, desktop, taskbar

function event.init(s, w, d, t)
    state = s
    wm = w
    desktop = d
    taskbar = t
end

-- Should a given event be delivered to an app coroutine?
function event.should_deliver(win, ev_type)
    -- Touch/click events only go to focused window
    if ev_type == "mouse_click" or ev_type == "mouse_scroll" or
       ev_type == "mouse_drag" or ev_type == "mouse_up" or
       ev_type == "monitor_touch" then
        return win.focused
    end

    -- Key events only go to focused window
    if ev_type == "key" or ev_type == "char" or ev_type == "key_up"
       or ev_type == "paste" then
        return win.focused
    end

    -- Timer events go to all apps (they self-filter by timer ID)
    if ev_type == "timer" then
        return true
    end

    -- Audio events go to all (YouCube needs speaker_audio_empty)
    if ev_type == "speaker_audio_empty" then
        return true
    end

    -- Websocket events go to all
    if ev_type == "websocket_success" or ev_type == "websocket_failure" or
       ev_type == "websocket_message" or ev_type == "websocket_closed" then
        return true
    end

    -- Custom namespaced events go to all
    if type(ev_type) == "string" and ev_type:find(":") then
        return true
    end

    -- Rednet messages go to all
    if ev_type == "rednet_message" then
        return true
    end

    -- All other events (peripheral task callbacks, CC:Tweaked internals):
    -- deliver to focused window so peripheral calls work in app coroutines
    return win.focused
end

-- Translate an event for delivery to a specific window
-- Converts monitor_touch coords to window-local mouse_click
function event.translate_for_window(win, ev)
    local ev_type = ev[1]

    if ev_type == "monitor_touch" then
        -- Convert to local coordinates
        local lx, ly = wm.to_local(win, ev[3], ev[4])
        return {"mouse_click", 1, lx, ly}
    end

    return ev
end

-- Handle a monitor touch event at global coordinates
-- Returns the action taken
function event.handle_touch(tx, ty, taskbar_areas, W, H)
    -- 1. Check taskbar (always on top)
    if ty >= H - 1 then
        local action, data = taskbar.handle_touch(tx, ty, taskbar_areas)
        if action == "focus_window" then
            local win = wm.get(data)
            if win then
                if win.minimized then
                    wm.restore(data)
                else
                    wm.focus(data)
                end
            end
            return "taskbar"
        elseif action == "toggle_desktop" then
            -- Minimize all windows to show desktop
            for _, w in ipairs(state.windows) do
                if not w.minimized then
                    wm.minimize(w.id)
                end
            end
            return "desktop_toggle"
        end
        return "taskbar"
    end

    -- 2. Check windows (top to bottom z-order)
    local win = wm.window_at(tx, ty)
    if win then
        -- Title bar?
        if wm.in_titlebar(win, tx, ty) then
            if wm.hit_close(win, tx, ty) then
                wm.close(win.id)
                return "window_close"
            elseif wm.hit_minimize(win, tx, ty) then
                wm.minimize(win.id)
                return "window_minimize"
            else
                wm.focus(win.id)
                return "window_focus"
            end
        end

        -- Content area
        if wm.in_content(win, tx, ty) then
            wm.focus(win.id)
            return "window_content", win
        end
    end

    -- 3. Desktop (loadout cards + app icons)
    local result, data = desktop.handle_touch(tx, ty, W, H)
    if result == "quick_withdraw" then
        return "quick_withdraw", data
    elseif result == "loadout_equip" then
        return "loadout_equip", data
    elseif result == "depot_action" then
        return "depot_action", data
    elseif result then
        return "launch_app", result
    end

    return "desktop"
end

return event
