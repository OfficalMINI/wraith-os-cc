-- =============================================
-- WRAITH OS - NETWORK SERVICE
-- =============================================
-- Rednet communication + WebSocket + status broadcasting.
-- Ported from JARVIS modules/network.lua

local svc = {}

function svc.main(state, config, utils)
    -- WebSocket helpers
    local function connect_websocket()
        if not config.network.websocket.enabled then return false end
        if not config.network.websocket.url then return false end

        local ok, ws = pcall(http.websocket, config.network.websocket.url)
        if ok and ws then
            state.network.ws_connection = ws
            state.network.ws_connected = true
            utils.add_notification(state, "WS: Connected to server", colors.lime)
            return true
        else
            state.network.ws_connected = false
            utils.add_notification(state, "WS: Connection failed", colors.red)
            return false
        end
    end

    local function ws_send(msg_type, data)
        if not state.network.ws_connected or not state.network.ws_connection then return false end

        local payload = textutils.serialiseJSON({
            type = msg_type,
            source = config.name,
            computer_id = os.getComputerID(),
            time = os.clock(),
            data = data,
        })

        local ok = pcall(state.network.ws_connection.send, payload)
        if not ok then
            state.network.ws_connected = false
            state.network.ws_connection = nil
            utils.add_notification(state, "WS: Send failed, disconnected", colors.orange)
        end
        return ok
    end

    local function ws_close()
        if state.network.ws_connection then
            pcall(state.network.ws_connection.close)
            state.network.ws_connection = nil
            state.network.ws_connected = false
        end
    end

    -- Status broadcasting
    local function build_status_payload()
        local stats = state.storage.stats
        return {
            base_name = config.name,
            computer_id = os.getComputerID(),
            uptime = os.clock() - state.boot_time,
            storage = stats,
            redstone = state.redstone.states,
        }
    end

    local function broadcast_status()
        local payload = build_status_payload()
        if state.network.modem_side then
            rednet.broadcast(payload, config.network.protocols.base_status)
        end
        if state.network.ws_connected then
            ws_send("status", payload)
        end
    end

    -- Command handler
    local function handle_command(sender, msg, protocol)
        if protocol == config.network.protocols.base_command then
            if type(msg) == "table" then
                if msg.action == "extract" and msg.item and msg.amount then
                    if state.storage.extract then
                        state.storage.extract(msg.item, msg.amount)
                    end
                    utils.add_notification(state, string.format("NET: Extract req from #%d", sender), colors.cyan)
                elseif msg.action == "import" then
                    if state.storage.import then
                        state.storage.import()
                    end
                    utils.add_notification(state, string.format("NET: Import req from #%d", sender), colors.cyan)
                elseif msg.action == "redstone" and msg.name then
                    if state.redstone.toggle_output then
                        state.redstone.toggle_output(msg.name)
                    end
                elseif msg.action == "query_items" then
                    local items_data = state.storage.items or {}
                    rednet.send(sender, items_data, config.network.protocols.base_storage)
                end
            elseif msg == "ping" then
                rednet.send(sender, {
                    name = config.name,
                    id = os.getComputerID(),
                    version = config.version,
                }, config.network.protocols.base_ping)
            end

            state.network.connected_clients[sender] = {
                last_seen = os.clock(),
                label = tostring(sender),
            }
        end
    end

    -- Listener loops
    local function listen_loop()
        while state.running do
            local sender, msg, protocol = rednet.receive(nil, config.network.discovery_interval)
            if sender then
                handle_command(sender, msg, protocol)
            end
        end
    end

    local function ws_receive_loop()
        while state.running do
            if not state.network.ws_connected then
                sleep(config.network.websocket.reconnect_interval)
                connect_websocket()
            else
                local ok, data = pcall(state.network.ws_connection.receive, config.network.websocket.heartbeat_interval)
                if ok and data then
                    local parsed = textutils.unserialiseJSON(data)
                    if parsed and parsed.action then
                        handle_command(-1, parsed, config.network.protocols.base_command)
                    end
                elseif not ok then
                    state.network.ws_connected = false
                    state.network.ws_connection = nil
                    utils.add_notification(state, "WS: Connection lost", colors.orange)
                end
            end
        end
    end

    local function broadcast_loop()
        while state.running do
            sleep(config.network.discovery_interval)
            broadcast_status()
            -- Clean stale clients
            local now = os.clock()
            for id, client in pairs(state.network.connected_clients) do
                if now - client.last_seen > 60 then
                    state.network.connected_clients[id] = nil
                end
            end
        end
    end

    -- Init
    state.network.ready = true

    if config.network.websocket.enabled then
        connect_websocket()
    end

    local has_modem = state.network.modem_side ~= nil
    if has_modem and config.network.websocket.enabled then
        parallel.waitForAll(listen_loop, broadcast_loop, ws_receive_loop)
    elseif has_modem then
        parallel.waitForAll(listen_loop, broadcast_loop)
    elseif config.network.websocket.enabled then
        parallel.waitForAll(ws_receive_loop, broadcast_loop)
    else
        while state.running do sleep(5) end
    end
end

return svc
