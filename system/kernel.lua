-- =============================================
-- WRAITH OS - KERNEL
-- =============================================
-- Central event loop with coroutine scheduler

local kernel = {}

local state, config, theme, draw, utils
local wm, desktop, taskbar, compositor, event_router

-- Service coroutines: {co, filter, id, name}
local services = {}

-- App draw functions: {win_id -> fn(buf, win)}
local app_draw_fns = {}

-- Taskbar hit areas (updated each render)
local taskbar_areas = {}

function kernel.init(modules)
    state       = modules.state
    config      = modules.config
    theme       = modules.theme
    draw        = modules.draw
    utils       = modules.utils
    wm          = modules.wm
    desktop     = modules.desktop
    taskbar     = modules.taskbar
    compositor  = modules.compositor
    event_router = modules.event
end

-- Register a background service
function kernel.add_service(id, name, main_fn)
    local co = coroutine.create(function()
        local ok, err = pcall(main_fn, state, config, utils)
        if not ok then
            utils.add_notification(state, "Service " .. name .. " crashed: " .. tostring(err), theme.danger)
        end
    end)
    table.insert(services, {co = co, filter = nil, id = id, name = name})

    -- Initial resume
    local ok, filter = coroutine.resume(co)
    if ok then
        services[#services].filter = filter
    else
        -- Service crashed on first resume - log it visibly
        local err_msg = "SVC CRASH [" .. name .. "]: " .. tostring(filter)
        utils.add_notification(state, err_msg, theme.danger)
        -- Also print to native terminal so it's always visible
        local native = term.native()
        native.setTextColor(colors.red)
        native.setCursorPos(1, 1)
        native.write(err_msg:sub(1, 50))
    end
end

-- Launch an app in a window
function kernel.launch_app(app_id)
    local app_def = state.app_registry[app_id]
    if not app_def then return nil end

    -- Check singleton
    if app_def.singleton then
        local running, win_id = wm.is_app_running(app_id)
        if running then
            local win = wm.get(win_id)
            if win and win.minimized then
                wm.restore(win_id)
            else
                wm.focus(win_id)
            end
            return win_id
        end
    end

    -- Create window
    local w = app_def.default_w or config.window.default_w
    local h = app_def.default_h or config.window.default_h
    local win = wm.create(app_id, app_def.name or app_id, nil, nil, w, h, {
        needs_real_window = app_def.needs_real_window,
    })

    -- Create app context
    local ctx = {
        win = win,
        state = state,
        config = config,
        theme = theme,
        draw = draw,
        utils = utils,
        wm = wm,
    }

    -- Create scoped drawing: offsets all coords to window content area
    ctx.content_x = win.x + 1  -- +1 for border
    ctx.content_y = win.y + win.titlebar_h
    ctx.content_w = win.w - 2  -- -2 for borders
    ctx.content_h = win.h - win.titlebar_h - 1  -- -1 for bottom border

    -- Register the app's draw function
    if app_def.render then
        app_draw_fns[win.id] = function(buf, w)
            -- Update content dimensions in case window moved
            ctx.content_x = w.x + 1
            ctx.content_y = w.y + w.titlebar_h
            ctx.content_w = w.w - 2
            ctx.content_h = w.h - w.titlebar_h - 1
            app_def.render(ctx, buf)
        end
    end

    -- Create app coroutine
    if app_def.main then
        win.app_coroutine = coroutine.create(function()
            local ok, err = pcall(app_def.main, ctx)
            if not ok then
                utils.add_notification(state, app_id .. " crashed: " .. tostring(err), theme.danger)
            end
            -- Clean up draw function when app exits
            app_draw_fns[win.id] = nil
        end)

        -- Initial resume
        local ok, filter = coroutine.resume(win.app_coroutine)
        if ok then
            win.event_filter = filter
        end
    end

    return win.id
end

-- Resume an app coroutine with an event
local function resume_app(win, ev)
    if not win.app_coroutine then return end
    if coroutine.status(win.app_coroutine) == "dead" then
        win.app_coroutine = nil
        app_draw_fns[win.id] = nil
        return
    end

    local ok, filter = coroutine.resume(win.app_coroutine, table.unpack(ev))
    if ok then
        win.event_filter = filter
    else
        -- App crashed
        utils.add_notification(state, win.app_id .. ": " .. tostring(filter), theme.danger)
        win.app_coroutine = nil
        app_draw_fns[win.id] = nil
    end
end

-- Main event loop
function kernel.run()
    -- Initial render
    taskbar_areas = compositor.render(app_draw_fns) or {}

    -- Start refresh timer
    local refresh_timer = os.startTimer(config.monitor.refresh_rate)

    while state.running do
        local ev = {os.pullEventRaw()}
        local ev_type = ev[1]

        -- Route to services
        for _, svc in ipairs(services) do
            if coroutine.status(svc.co) ~= "dead" then
                if svc.filter == nil or svc.filter == ev_type then
                    local ok, filter = coroutine.resume(svc.co, table.unpack(ev))
                    if ok then
                        svc.filter = filter
                    else
                        utils.add_notification(state,
                            "Svc " .. svc.name .. ": " .. tostring(filter), theme.danger)
                    end
                end
            end
        end

        -- Clean up dead one-shot coroutines
        for i = #services, 1, -1 do
            if coroutine.status(services[i].co) == "dead" then
                table.remove(services, i)
            end
        end

        -- Handle monitor touch
        if ev_type == "monitor_touch" and ev[2] == state.monitor_name then
            local tx, ty = ev[3], ev[4]
            local W, H = compositor.get_size()
            local action, data = event_router.handle_touch(tx, ty, taskbar_areas, W, H)

            if action == "launch_app" then
                kernel.launch_app(data)
            elseif action == "quick_withdraw" then
                -- Spawn a one-shot coroutine so sleep() inside give_to_player
                -- can't eat the storage service's tick timer
                local item = data.item or data
                local amount = data.amount or 1
                kernel.add_service("qw", "Quick Withdraw", function()
                    local st = state.storage
                    if st and st.withdraw then
                        st.withdraw(item, amount)
                    elseif st and st.extract then
                        st.extract(item, amount)
                    end
                end)
            elseif action == "loadout_equip" then
                os.queueEvent("loadout:equip", data)
            elseif action == "depot_action" then
                os.queueEvent("depot:" .. data)
            elseif action == "window_content" then
                -- Deliver translated touch to the focused window's app
                local win = data
                if win and win.app_coroutine then
                    local translated = event_router.translate_for_window(win, ev)
                    resume_app(win, translated)
                end
            end
            -- Force redraw after any touch
            taskbar_areas = compositor.render(app_draw_fns) or {}

        -- Route other events to app coroutines
        elseif ev_type ~= "timer" or ev[2] ~= refresh_timer then
            -- Cross-app launch event
            if ev_type == "wraith:launch_app" then
                kernel.launch_app(ev[2])
                taskbar_areas = compositor.render(app_draw_fns) or {}
            end

            for _, win in ipairs(state.windows) do
                if win.app_coroutine and event_router.should_deliver(win, ev_type) then
                    if win.event_filter == nil or win.event_filter == ev_type then
                        local translated = ev
                        if ev_type == "monitor_touch" then
                            translated = event_router.translate_for_window(win, ev)
                        end
                        resume_app(win, translated)
                    end
                end
            end
        end

        -- Compositor refresh on timer
        if ev_type == "timer" and ev[2] == refresh_timer then
            -- Clear expired status
            if state.status_timeout > 0 and os.clock() > state.status_timeout then
                utils.clear_status(state)
            end

            taskbar_areas = compositor.render(app_draw_fns) or {}
            refresh_timer = os.startTimer(config.monitor.refresh_rate)
        end

        -- Handle terminate
        if ev_type == "terminate" then
            if state.focused_id then
                wm.close(state.focused_id)
                taskbar_areas = compositor.render(app_draw_fns) or {}
            else
                state.running = false
            end
        end
    end
end

return kernel
