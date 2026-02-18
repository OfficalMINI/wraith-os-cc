-- =============================================
-- WRAITH OS - YOUCUBE APP
-- =============================================
-- YouTube video player using YouCube API.
-- Streams video + audio in a window.

local app = {
    id = "youcube",
    name = "YouCube",
    icon = "youcube",
    default_w = 53,
    default_h = 22,
    singleton = true,
    needs_real_window = true,  -- needs real window.create for term.redirect
}

-- App states
local STATE_INPUT = 1
local STATE_CONNECTING = 2
local STATE_PLAYING = 3
local STATE_ERROR = 4

local app_state = STATE_INPUT
local url_input = ""
local status_text = ""
local error_text = ""
local media_title = ""
local yc_api = nil
local yc_libs = nil

function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme

    if app_state == STATE_PLAYING then
        -- During playback, the real window handles rendering
        draw.fill(buf, y, x + w, theme.surface)
        draw.center(buf, "Video playing: " .. media_title:sub(1, w - 20), y, x + w, theme.accent, theme.surface)
        draw.fill(buf, y + 1, x + w, theme.surface)
        draw.center(buf, "Press Q to stop", y + 1, x + w, theme.fg_dim, theme.surface)
        -- Fill rest with dark bg (video renders in real window)
        for r = y + 2, y + h - 1 do
            draw.fill(buf, r, x + w, theme.bg)
        end
        return
    end

    -- Input / connecting / error states
    -- Background
    for r = y, y + h - 1 do
        draw.fill(buf, r, x + w, theme.surface)
    end

    -- YouCube logo
    local logo_y = y + 2
    draw.center(buf, "\7 Y O U C U B E \7", logo_y, x + w, theme.danger, theme.surface)
    draw.center(buf, "Stream YouTube in Minecraft", logo_y + 1, x + w, theme.fg_dim, theme.surface)

    if app_state == STATE_INPUT then
        -- URL input
        local input_y = logo_y + 4
        draw.center(buf, "Enter URL or search term:", input_y, x + w, theme.fg, theme.surface)

        -- Input box
        local box_w = w - 8
        local box_x = x + 4
        local box_y = input_y + 2

        draw.fillRect(buf, box_x, box_y, box_w, 1, theme.surface2)
        local display = url_input ~= "" and url_input or "paste or type here..."
        local dfg = url_input ~= "" and theme.fg or theme.fg_dim
        if #display > box_w - 2 then display = display:sub(-box_w + 4) .. ".." end
        draw.put(buf, box_x + 1, box_y, display, dfg, theme.surface2)

        -- Play button
        local btn_y = box_y + 3
        local btn_w = 14
        local btn_x = x + math.floor((w - btn_w) / 2)
        draw.button(buf, btn_x, btn_y, btn_w, 3, "\16 PLAY", theme.danger, theme.btn_text, url_input ~= "")

        -- Help text
        draw.center(buf, "Click input box to type on PC", btn_y + 4, x + w, theme.fg_dark, theme.surface)
        draw.center(buf, "Supports: YouTube, SoundCloud, etc.", btn_y + 5, x + w, theme.fg_dark, theme.surface)

    elseif app_state == STATE_CONNECTING then
        local mid_y = logo_y + 5
        draw.center(buf, status_text, mid_y, x + w, theme.accent, theme.surface)
        draw.center(buf, "Please wait...", mid_y + 2, x + w, theme.fg_dim, theme.surface)

    elseif app_state == STATE_ERROR then
        local mid_y = logo_y + 4
        draw.center(buf, "Error:", mid_y, x + w, theme.danger, theme.surface)
        local err = error_text
        if #err > w - 4 then err = err:sub(1, w - 6) .. ".." end
        draw.center(buf, err, mid_y + 1, x + w, theme.fg, theme.surface)

        -- Retry button
        local btn_y = mid_y + 4
        local btn_w = 12
        local btn_x = x + math.floor((w - btn_w) / 2)
        draw.button(buf, btn_x, btn_y, btn_w, 1, "TRY AGAIN", theme.accent, theme.btn_text, true)
    end
end

function app.main(ctx)
    local root = _G.WRAITH_ROOT or "."

    -- Load YouCube libraries
    local function load_yc_lib(name)
        local path = root .. "/youcube_lib/" .. name .. ".lua"
        if fs.exists(path) then
            return dofile(path)
        end
        return nil
    end

    yc_libs = {
        youcubeapi = load_yc_lib("youcubeapi"),
        numberformatter = load_yc_lib("numberformatter"),
        semver = load_yc_lib("semver"),
        string_pack = load_yc_lib("string_pack"),
    }

    if not yc_libs.youcubeapi then
        app_state = STATE_ERROR
        error_text = "YouCube libraries not found"
        while true do coroutine.yield() end
    end

    -- Main app loop
    while true do
        if app_state == STATE_INPUT then
            -- Wait for input events
            local ev = {coroutine.yield()}

            if ev[1] == "char" then
                url_input = url_input .. ev[2]
            elseif ev[1] == "key" then
                if ev[2] == keys.backspace then
                    url_input = url_input:sub(1, -2)
                elseif ev[2] == keys.enter and url_input ~= "" then
                    -- Start playback
                    app_state = STATE_CONNECTING
                    status_text = "Connecting to server..."

                    -- Use pcall for the whole playback sequence
                    local ok, err = pcall(function()
                        -- Connect to YouCube server
                        yc_api = yc_libs.youcubeapi.API.new()

                        -- Server detection (simplified - try all servers)
                        local servers = {
                            "ws://127.0.0.1:5000",
                            "wss://us-ky.youcube.knijn.one",
                            "wss://youcube.knijn.one",
                            "wss://youcube.onrender.com",
                        }

                        local connected = false
                        for _, server in ipairs(servers) do
                            status_text = "Trying " .. server .. "..."
                            local ws_ok, ws = pcall(http.websocket, server)
                            if ws_ok and ws then
                                yc_api.websocket = ws
                                connected = true
                                break
                            end
                        end

                        if not connected then
                            error("Could not connect to any YouCube server")
                        end

                        -- Request media
                        status_text = "Requesting media..."
                        local win = ctx.win
                        local vw, vh = win.w, win.h - win.titlebar_h

                        yc_api:request_media(url_input, vw, vh)

                        -- Wait for media response
                        local data
                        repeat
                            data = yc_api:receive()
                            if data.action == "status" then
                                status_text = "Status: " .. (data.message or "processing...")
                            end
                        until data.action == "media" or data.action == "error"

                        if data.action == "error" then
                            error(data.message or "Server error")
                        end

                        media_title = data.title or "Unknown"
                        app_state = STATE_PLAYING

                        -- Create buffers
                        local video_buffer = yc_libs.youcubeapi.Buffer.new(
                            yc_libs.youcubeapi.VideoFiller.new(yc_api, data.id, vw, vh),
                            60
                        )

                        local audio_buffer = yc_libs.youcubeapi.Buffer.new(
                            yc_libs.youcubeapi.AudioFiller.new(yc_api, data.id),
                            32
                        )

                        -- Get audio devices
                        local speakers = {peripheral.find("speaker")}
                        local has_audio = #speakers > 0
                        local decoder = nil
                        local audio_ok, dfpwm = pcall(require, "cc.audio.dfpwm")
                        if audio_ok then decoder = dfpwm.make_decoder() end

                        -- Redirect term to real window for video rendering
                        local old_term = nil
                        if win.content_win then
                            win.content_win_active = true
                            old_term = term.redirect(win.content_win)
                        end

                        local string_unpack = string.unpack
                        if not string_unpack and yc_libs.string_pack then
                            string_unpack = yc_libs.string_pack.unpack
                        end

                        -- Play functions
                        local function fill_buffers()
                            while true do
                                os.queueEvent("youcube:fill_buffers")
                                os.pullEvent()
                                audio_buffer:fill()
                                video_buffer:fill()
                            end
                        end

                        local function play_video()
                            yc_libs.youcubeapi.play_vid(video_buffer, nil, string_unpack)
                        end

                        local function play_audio()
                            if not has_audio or not decoder then return end
                            local speaker = speakers[1]
                            while true do
                                local chunk = audio_buffer:next()
                                if chunk == "" then
                                    speaker.playAudio({})
                                    return
                                end
                                local buffer = decoder(chunk)
                                while not speaker.playAudio(buffer) do
                                    os.pullEvent("speaker_audio_empty")
                                end
                            end
                        end

                        local function stop_handler()
                            while true do
                                local _, key = os.pullEvent("key")
                                if key == keys.q or key == keys.backspace then
                                    break
                                end
                            end
                        end

                        -- Play!
                        parallel.waitForAny(fill_buffers, play_video, play_audio, stop_handler)

                        -- Restore term
                        if old_term then
                            term.redirect(old_term)
                        end
                        win.content_win_active = false

                        -- Restore palette
                        if ctx.state.monitor then
                            local theme_mod = _G._wraith and _G._wraith.theme
                            if theme_mod and theme_mod.apply_palette then
                                theme_mod.apply_palette(ctx.state.monitor)
                            end
                        end

                        -- Close websocket
                        pcall(function() yc_api.websocket.close() end)
                    end)

                    if not ok then
                        app_state = STATE_ERROR
                        error_text = tostring(err)
                    else
                        -- Playback finished, return to input
                        app_state = STATE_INPUT
                        url_input = ""
                    end
                end

            elseif ev[1] == "mouse_click" then
                local ly = ev[4]
                local w = ctx.content_w

                -- Input box area (click to type on PC)
                if ly >= 7 and ly <= 10 then
                    local result = ctx.utils.pc_input("YOUCUBE", "Enter a YouTube URL or search term.")
                    if result then
                        url_input = result
                    end
                end

                -- Play button click
                local btn_w = 14
                local btn_x = math.floor((w - btn_w) / 2) + 1
                local btn_y = 11  -- approximate

                if ly >= btn_y and ly < btn_y + 3 and
                   ev[3] >= btn_x and ev[3] < btn_x + btn_w and
                   url_input ~= "" then
                    -- Trigger enter
                    os.queueEvent("key", keys.enter)
                end

            elseif ev[1] == "paste" then
                url_input = url_input .. ev[2]
            end

        elseif app_state == STATE_ERROR then
            local ev = {coroutine.yield()}
            if ev[1] == "mouse_click" or ev[1] == "key" then
                app_state = STATE_INPUT
                error_text = ""
            end

        else
            coroutine.yield()
        end
    end
end

return app
