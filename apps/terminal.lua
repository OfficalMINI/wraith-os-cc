-- =============================================
-- WRAITH OS - TERMINAL APP
-- =============================================
-- Simple shell in a window on the monitor.
-- Uses content_win for rendering, receives keyboard
-- events from the PC via kernel event routing.

local app = {
    id = "terminal",
    name = "Terminal",
    icon = "terminal",
    default_w = 51,
    default_h = 19,
    singleton = true,
    needs_real_window = true,
}

function app.main(ctx)
    local win = ctx.win
    if not win.content_win then
        while true do coroutine.yield() end
    end

    win.content_win_active = true

    local cw = win.content_win
    cw.setBackgroundColor(colors.black)
    cw.setTextColor(colors.white)
    cw.clear()
    cw.setCursorPos(1, 1)

    -- Simple shell: handle events directly for reliability
    local cw_w, cw_h = cw.getSize()
    local input = ""
    local history = {}
    local hist_idx = 0

    local function scroll_up()
        cw.scroll(1)
        cw.setCursorPos(1, cw_h)
    end

    local function safe_print(text)
        text = tostring(text)
        local cx, cy = cw.getCursorPos()
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if cy > cw_h then
                scroll_up()
                cy = cw_h
            end
            cw.setCursorPos(1, cy)
            -- Handle long lines
            while #line > 0 do
                local chunk = line:sub(1, cw_w)
                line = line:sub(cw_w + 1)
                cw.write(chunk)
                if #line > 0 then
                    cy = cy + 1
                    if cy > cw_h then
                        scroll_up()
                        cy = cw_h
                    end
                    cw.setCursorPos(1, cy)
                end
            end
            cy = cy + 1
        end
        cw.setCursorPos(1, cy)
    end

    local function draw_prompt()
        local cx, cy = cw.getCursorPos()
        if cy > cw_h then
            scroll_up()
            cy = cw_h
        end
        cw.setCursorPos(1, cy)
        cw.setTextColor(colors.cyan)
        cw.write("> ")
        cw.setTextColor(colors.white)
        -- Show input (may need to truncate)
        local avail = cw_w - 2
        local display = input
        if #display > avail then
            display = display:sub(#display - avail + 1)
        end
        cw.write(display)
        -- Clear rest of line
        local rx = 2 + #display
        if rx < cw_w then
            cw.write(string.rep(" ", cw_w - rx))
        end
        cw.setCursorPos(2 + #display + 1, cy)
    end

    -- Welcome
    cw.setTextColor(colors.cyan)
    safe_print("Wraith OS Terminal")
    cw.setTextColor(colors.lightGray)
    safe_print("Type commands. 'exit' to close.")
    safe_print("")
    cw.setTextColor(colors.white)
    draw_prompt()

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "char" then
            input = input .. ev[2]
            draw_prompt()

        elseif ev[1] == "key" then
            local key = ev[2]

            if key == keys.enter then
                -- Move to next line
                local _, cy = cw.getCursorPos()
                cw.setCursorPos(1, cy)
                cw.setTextColor(colors.cyan)
                cw.write("> ")
                cw.setTextColor(colors.white)
                cw.write(input)
                local nx, ny = cw.getCursorPos()
                ny = ny + 1
                if ny > cw_h then scroll_up(); ny = cw_h end
                cw.setCursorPos(1, ny)

                local cmd = input
                input = ""
                hist_idx = 0

                if cmd == "exit" then
                    break
                elseif cmd == "clear" then
                    cw.clear()
                    cw.setCursorPos(1, 1)
                elseif cmd ~= "" then
                    -- Save to history
                    table.insert(history, cmd)

                    -- Capture output by redirecting to content_win
                    local old = term.redirect(cw)
                    local ok, err = pcall(shell.run, cmd)
                    term.redirect(old)

                    if not ok then
                        cw.setTextColor(colors.red)
                        safe_print("Error: " .. tostring(err))
                        cw.setTextColor(colors.white)
                    end
                end

                draw_prompt()

            elseif key == keys.backspace then
                if #input > 0 then
                    input = input:sub(1, -2)
                    draw_prompt()
                end

            elseif key == keys.up then
                -- History navigation
                if #history > 0 then
                    if hist_idx == 0 then
                        hist_idx = #history
                    elseif hist_idx > 1 then
                        hist_idx = hist_idx - 1
                    end
                    input = history[hist_idx]
                    draw_prompt()
                end

            elseif key == keys.down then
                if hist_idx > 0 then
                    hist_idx = hist_idx + 1
                    if hist_idx > #history then
                        hist_idx = 0
                        input = ""
                    else
                        input = history[hist_idx]
                    end
                    draw_prompt()
                end
            end

        elseif ev[1] == "paste" then
            input = input .. ev[2]
            draw_prompt()
        end
    end

    win.content_win_active = false
end

return app
