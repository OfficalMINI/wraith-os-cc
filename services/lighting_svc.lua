-- =============================================
-- WRAITH OS - LIGHTING CONTROLLER SERVICE
-- =============================================
-- Player detection, controller registry, proximity
-- matching, theme distribution via rednet.

local svc = {}

function svc.main(state, config, utils)
    local lt = state.lighting
    local cfg = config.lighting
    local proto = cfg.protocols

    -- ========================================
    -- Color Map (Rainbow Lamp signal 0-15)
    -- ========================================
    local COLOR_NAMES = {
        [0]  = "Off",       [1]  = "Gray",      [2]  = "Lt.Gray",  [3]  = "Brown",
        [4]  = "Green",     [5]  = "Lime",      [6]  = "Cyan",     [7]  = "Lt.Blue",
        [8]  = "Blue",      [9]  = "Purple",    [10] = "Magenta",  [11] = "Pink",
        [12] = "Red",       [13] = "Orange",    [14] = "Yellow",   [15] = "White",
    }
    lt.color_names = COLOR_NAMES

    -- ========================================
    -- Persistence
    -- ========================================
    local SAVE_PATH = cfg.save_file

    local function save_data()
        local data = {
            player_themes = lt.player_themes,
            always_on = lt.always_on,
        }
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 5 then return end
        local tmp = SAVE_PATH .. ".tmp"
        local file = fs.open(tmp, "w")
        if file then
            file.write(content)
            file.close()
            if fs.exists(SAVE_PATH) then fs.delete(SAVE_PATH) end
            fs.move(tmp, SAVE_PATH)
        end
    end

    local function load_data()
        if fs.exists(SAVE_PATH) then
            local file = fs.open(SAVE_PATH, "r")
            if file then
                local raw = file.readAll()
                file.close()
                local fn = loadstring("return " .. raw)
                if fn then
                    local ok, data = pcall(fn)
                    if ok and type(data) == "table" then
                        if data.player_themes then
                            lt.player_themes = data.player_themes
                        end
                        if data.always_on ~= nil then
                            lt.always_on = data.always_on
                        end
                    end
                end
            end
        end
    end

    -- ========================================
    -- Player Detector
    -- ========================================
    local function find_detector()
        local det = peripheral.find("playerDetector")
        if det then
            lt.detector = det
            lt.detector_name = peripheral.getName(det)
            return true
        end
        lt.detector = nil
        lt.detector_name = ""
        return false
    end

    local function poll_players()
        if not lt.detector then return end
        local ok, players = pcall(lt.detector.getPlayersInRange, cfg.detection_range)
        if not ok or not players then
            lt.nearby_players = {}
            return
        end
        local new_players = {}
        for _, username in ipairs(players) do
            local ok2, pos = pcall(lt.detector.getPlayerPos, username)
            if ok2 and pos then
                new_players[username] = {
                    x = pos.x,
                    y = pos.y,
                    z = pos.z,
                }
            else
                new_players[username] = {x = 0, y = 0, z = 0}
            end
        end
        lt.nearby_players = new_players
    end

    -- ========================================
    -- Controller Registry
    -- ========================================
    local function register_controller(sender, msg)
        if type(msg) ~= "table" then return end
        lt.controllers[sender] = {
            id = sender,
            x = msg.x or 0,
            y = msg.y or 0,
            z = msg.z or 0,
            side = msg.side or "bottom",
            last_seen = os.clock(),
            online = true,
            current_color = nil,
            current_pattern = nil,
            assigned_player = nil,
        }
        rednet.send(sender, {
            status = "registered",
            id = os.getComputerID(),
        }, proto.status)
    end

    local function handle_heartbeat(sender, msg)
        local ctrl = lt.controllers[sender]
        if ctrl then
            ctrl.last_seen = os.clock()
            ctrl.online = true
        else
            rednet.send(sender, {status = "unknown"}, proto.status)
        end
    end

    local function check_controller_timeouts()
        local now = os.clock()
        for id, ctrl in pairs(lt.controllers) do
            if now - ctrl.last_seen > cfg.heartbeat_timeout then
                ctrl.online = false
            end
        end
    end

    -- ========================================
    -- Proximity Matching
    -- ========================================
    local function distance_3d(x1, y1, z1, x2, y2, z2)
        local dx = x1 - x2
        local dy = y1 - y2
        local dz = z1 - z2
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    local function find_nearby_players_for(ctrl)
        local nearby = {}
        for username, pdata in pairs(lt.nearby_players) do
            local dist = distance_3d(pdata.x, pdata.y, pdata.z, ctrl.x, ctrl.y, ctrl.z)
            if dist <= cfg.proximity_radius then
                table.insert(nearby, {name = username, dist = dist})
            end
        end
        table.sort(nearby, function(a, b) return a.dist < b.dist end)
        return nearby
    end

    -- ========================================
    -- Command Distribution
    -- ========================================
    local cycle_state = {}

    local function distribute_commands()
        local now = os.clock()
        for id, ctrl in pairs(lt.controllers) do
            if not ctrl.online then
                ctrl.assigned_player = nil
                ctrl.current_color = nil
                ctrl.current_pattern = nil
            else
                local nearby = find_nearby_players_for(ctrl)

                if #nearby == 0 then
                    -- No players nearby: use always_on (1=Gray dim) or off (0)
                    local idle_color = lt.always_on and 1 or 0
                    if ctrl.current_color ~= idle_color or ctrl.assigned_player ~= nil then
                        rednet.send(id, {
                            action = "set",
                            colors = {idle_color},
                            pattern = "solid",
                        }, proto.command)
                        ctrl.current_color = idle_color
                        ctrl.current_pattern = "solid"
                        ctrl.assigned_player = nil
                    end
                else
                    -- Determine which player's theme to use
                    local chosen_player = nil
                    if #nearby == 1 then
                        chosen_player = nearby[1].name
                    else
                        if not cycle_state[id] then
                            cycle_state[id] = {idx = 1, last_switch = now}
                        end
                        local cs = cycle_state[id]
                        if now - cs.last_switch >= cfg.multi_player_cycle then
                            cs.idx = (cs.idx % #nearby) + 1
                            cs.last_switch = now
                        end
                        if cs.idx > #nearby then cs.idx = 1 end
                        chosen_player = nearby[cs.idx].name
                    end

                    local theme_data = lt.player_themes[chosen_player]
                    if not theme_data then
                        theme_data = {colors = {15}, pattern = "solid"}
                    end

                    -- For solid/pulse: pick one random color, but keep it
                    -- until the player assignment changes
                    local send_colors = theme_data.colors
                    if (theme_data.pattern == "solid" or theme_data.pattern == "pulse")
                       and #theme_data.colors > 1 then
                        if ctrl.assigned_player == chosen_player and ctrl.current_color then
                            -- Same player still nearby - keep current color
                            send_colors = {ctrl.current_color}
                        else
                            -- New player or first assignment - pick random
                            local pick = theme_data.colors[math.random(#theme_data.colors)]
                            send_colors = {pick}
                        end
                    end

                    ctrl.assigned_player = chosen_player
                    ctrl.current_color = send_colors[1]
                    ctrl.current_pattern = theme_data.pattern

                    rednet.send(id, {
                        action = "set",
                        colors = send_colors,
                        pattern = theme_data.pattern,
                    }, proto.command)
                end
            end
        end
    end

    -- ========================================
    -- Exposed Functions
    -- ========================================
    lt.set_theme = function(username, theme_colors, pattern)
        if type(theme_colors) ~= "table" or #theme_colors == 0 then return false end
        while #theme_colors > cfg.max_colors_per_theme do
            table.remove(theme_colors)
        end
        for i, c in ipairs(theme_colors) do
            theme_colors[i] = math.floor(math.max(0, math.min(15, tonumber(c) or 0)))
        end
        local valid_patterns = {solid = true, pulse = true, strobe = true, fade = true}
        if not valid_patterns[pattern] then pattern = "solid" end
        lt.player_themes[username] = {
            colors = theme_colors,
            pattern = pattern,
        }
        save_data()
        distribute_commands()
        utils.add_notification(state,
            string.format("LIGHTING: Theme set for %s", username), colors.lime)
        return true
    end

    lt.remove_theme = function(username)
        lt.player_themes[username] = nil
        save_data()
        distribute_commands()
        utils.add_notification(state,
            string.format("LIGHTING: Theme removed for %s", username), colors.orange)
    end

    lt.get_theme = function(username)
        return lt.player_themes[username]
    end

    lt.get_controllers = function()
        local list = {}
        for id, ctrl in pairs(lt.controllers) do
            table.insert(list, {
                id = ctrl.id,
                x = ctrl.x, y = ctrl.y, z = ctrl.z,
                online = ctrl.online,
                last_seen = ctrl.last_seen,
                current_color = ctrl.current_color,
                current_pattern = ctrl.current_pattern,
                assigned_player = ctrl.assigned_player,
            })
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end

    lt.get_nearby_players = function()
        local list = {}
        for name, data in pairs(lt.nearby_players) do
            table.insert(list, {
                name = name,
                x = data.x, y = data.y, z = data.z,
                has_theme = lt.player_themes[name] ~= nil,
            })
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list
    end

    lt.remove_controller = function(id)
        lt.controllers[id] = nil
        cycle_state[id] = nil
        utils.add_notification(state,
            string.format("LIGHTING: Controller #%d removed", id), colors.orange)
    end

    lt.toggle_always_on = function()
        lt.always_on = not lt.always_on
        save_data()
        distribute_commands()
        utils.add_notification(state,
            "LIGHTING: Always-on " .. (lt.always_on and "ENABLED" or "DISABLED"),
            lt.always_on and colors.lime or colors.orange)
        return lt.always_on
    end

    -- ========================================
    -- Main Event Loop
    -- ========================================
    load_data()

    if find_detector() then
        utils.add_notification(state, "LIGHTING: Detector found - " .. lt.detector_name, colors.lime)
    else
        utils.set_status(state, "LIGHTING: No player detector", colors.orange, 5)
    end

    lt.ready = true

    local next_poll = os.clock() + 0.5
    local next_command = os.clock() + 1
    local next_timeout_check = os.clock() + 5
    local heartbeat = os.startTimer(1)

    while state.running do
        local ev, p1, p2, p3 = os.pullEvent()
        local now = os.clock()

        -- Always-on set (from app UI — receives explicit value)
        if ev == "lighting:set_always_on" then
            lt.always_on = p1
            save_data()
            distribute_commands()
        end

        -- Handle rednet messages
        if ev == "rednet_message" then
            local sender, msg, protocol = p1, p2, p3
            if protocol == proto.register then
                register_controller(sender, msg)
                utils.add_notification(state,
                    string.format("LIGHTING: Controller #%d registered", sender), colors.lime)
            elseif protocol == proto.heartbeat then
                handle_heartbeat(sender, msg)
            elseif protocol == proto.ping then
                rednet.send(sender, {
                    status = "wraith",
                    id = os.getComputerID(),
                }, proto.status)
            end
        end

        -- Peripheral hotplug
        if ev == "peripheral" or ev == "peripheral_detach" then
            sleep(0.3)
            if not lt.detector then
                if find_detector() then
                    utils.add_notification(state, "LIGHTING: Detector connected", colors.lime)
                end
            else
                if not peripheral.isPresent(lt.detector_name) then
                    lt.detector = nil
                    lt.detector_name = ""
                    utils.add_notification(state, "LIGHTING: Detector disconnected", colors.red)
                end
            end
        end

        -- Poll players
        if now >= next_poll then
            poll_players()
            next_poll = now + cfg.poll_interval
        end

        -- Distribute commands
        if now >= next_command then
            distribute_commands()
            next_command = now + cfg.command_interval
        end

        -- Check timeouts
        if now >= next_timeout_check then
            check_controller_timeouts()
            next_timeout_check = now + 5
        end

        -- Heartbeat timer restart
        if ev == "timer" and p1 == heartbeat then
            heartbeat = os.startTimer(1)
        end
    end
end

return svc
