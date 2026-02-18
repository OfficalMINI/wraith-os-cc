-- =============================================
-- WRAITH OS - UTILITY FUNCTIONS
-- =============================================

local utils = {}

-- String helpers
function utils.pad_right(text, len)
    text = tostring(text)
    if #text >= len then return text:sub(1, len) end
    return text .. string.rep(" ", len - #text)
end

function utils.pad_left(text, len)
    text = tostring(text)
    if #text >= len then return text:sub(1, len) end
    return string.rep(" ", len - #text) .. text
end

function utils.pad_center(text, len)
    text = tostring(text)
    if #text >= len then return text:sub(1, len) end
    local left = math.floor((len - #text) / 2)
    local right = len - #text - left
    return string.rep(" ", left) .. text .. string.rep(" ", right)
end

function utils.truncate(str, max_len)
    if #str > max_len then
        return str:sub(1, max_len - 2) .. ".."
    end
    return str
end

function utils.format_number(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(num)
end

function utils.format_time(time)
    local hours = math.floor(time)
    local minutes = math.floor((time - hours) * 60)
    return string.format("%02d:%02d", hours, minutes)
end

function utils.format_uptime(seconds)
    if seconds >= 3600 then
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return string.format("%dm %ds", math.floor(seconds / 60), math.floor(seconds % 60))
    end
    return string.format("%ds", math.floor(seconds))
end

function utils.clean_name(id)
    return id:gsub(".*:", ""):gsub("_", " ")
end

function utils.capitalize(str)
    return str:sub(1, 1):upper() .. str:sub(2)
end

-- Table helpers
function utils.table_size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function utils.shallow_copy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

-- Notification helpers
function utils.set_status(state, msg, color, duration)
    state.status_msg = msg
    state.status_color = color
    state.status_timeout = duration and (os.clock() + duration) or 0
end

function utils.clear_status(state)
    state.status_msg = ""
    state.status_color = nil
    state.status_timeout = 0
end

function utils.add_notification(state, msg, color)
    table.insert(state.notifications, {
        msg = msg,
        color = color,
        time = os.clock(),
    })
    while #state.notifications > 30 do
        table.remove(state.notifications, 1)
    end
end

-- Safe pcall wrapper
function utils.safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- PC terminal input TUI
-- Shows a styled prompt on the PC terminal with manual key handling.
-- Uses coroutine.yield() directly instead of read() for reliable coroutine support.
function utils.pc_input(title, prompt, default_val)
    local native = term.native()
    local old = term.redirect(native)
    local W, H = native.getSize()
    local max_input = W - 8

    local function draw_frame()
        native.setBackgroundColor(colors.black)
        native.clear()

        -- Header bar
        native.setCursorPos(1, 1)
        if native.isColor() then
            native.setBackgroundColor(colors.gray)
            native.setTextColor(colors.cyan)
        end
        native.write(" WRAITH OS" .. string.rep(" ", math.max(0, W - 10)))
        native.setBackgroundColor(colors.black)

        -- Title
        native.setCursorPos(3, 4)
        if native.isColor() then native.setTextColor(colors.cyan) end
        native.write("\16 ")
        if native.isColor() then native.setTextColor(colors.white) end
        native.write(title or "Input")

        -- Prompt text
        native.setCursorPos(3, 6)
        if native.isColor() then native.setTextColor(colors.lightGray) end
        native.write(prompt or "Type and press Enter.")
        native.setCursorPos(3, 7)
        native.write("Leave empty and press Enter to cancel.")

        -- Separator
        native.setCursorPos(1, H - 2)
        if native.isColor() then native.setTextColor(colors.gray) end
        native.write(string.rep("\140", W))

        -- Footer
        native.setCursorPos(2, H - 1)
        if native.isColor() then native.setTextColor(colors.gray) end
        native.write("Wraith OS | Desktop is live on the monitor.")
    end

    local function draw_input(input)
        native.setCursorPos(3, 9)
        if native.isColor() then
            native.setTextColor(colors.white)
            native.setBackgroundColor(colors.black)
        end
        native.write("> ")
        local display = input
        if #display > max_input then
            display = ".." .. display:sub(-(max_input - 2))
        end
        native.write(display .. string.rep(" ", math.max(0, max_input - #display)))
        native.setCursorPos(5 + math.min(#input, max_input), 9)
        native.setCursorBlink(true)
    end

    draw_frame()
    local input = default_val or ""
    draw_input(input)

    -- Manual key handling loop using coroutine.yield
    while true do
        local ev = {coroutine.yield()}
        if ev[1] == "char" then
            input = input .. ev[2]
            draw_input(input)
        elseif ev[1] == "key" then
            if ev[2] == keys.enter then
                break
            elseif ev[2] == keys.backspace then
                if #input > 0 then
                    input = input:sub(1, -2)
                    draw_input(input)
                end
            end
        elseif ev[1] == "paste" then
            input = input .. ev[2]
            draw_input(input)
        end
    end

    native.setCursorBlink(false)

    -- Restore idle screen
    native.setBackgroundColor(colors.black)
    native.clear()
    native.setCursorPos(1, 1)
    if native.isColor() then native.setTextColor(colors.cyan) end
    native.write("Wraith OS")
    native.setCursorPos(1, 2)
    if native.isColor() then native.setTextColor(colors.lightGray) end
    native.write("Desktop is live on the monitor.")

    term.redirect(old)
    if input ~= "" then return input end
    return nil
end

-- Find modem on any side (prefer wireless/ender over wired)
function utils.find_modem()
    local wired = nil
    local sides = {"back", "top", "left", "right", "bottom", "front"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            local modem = peripheral.wrap(side)
            if modem and modem.isWireless and modem.isWireless() then
                return side  -- wireless/ender modem, use immediately
            end
            wired = wired or side  -- remember first wired modem as fallback
        end
    end
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local modem = peripheral.wrap(name)
            if modem and modem.isWireless and modem.isWireless() then
                return name
            end
            wired = wired or name
        end
    end
    return wired  -- fallback to wired if no wireless found
end

return utils
