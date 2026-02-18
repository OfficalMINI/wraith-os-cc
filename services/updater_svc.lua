-- =============================================
-- WRAITH OS - CLIENT UPDATER SERVICE
-- =============================================
-- Reads client scripts from wraith/clients/ and pushes
-- updated versions to remote computers/turtles over rednet.
-- Clients check in on boot with their version hash;
-- if it differs, the server sends the new file content.

local svc = {}

function svc.main(state, config, utils)
    local cfg = config.updater
    if not cfg or not cfg.enabled then
        utils.add_notification(state, "UPDATER: Disabled", colors.lightGray)
        while state.running do coroutine.yield() end
        return
    end

    local proto = cfg.protocols
    local client_dir = (_G.WRAITH_ROOT or ".") .. "/clients"

    -- ========================================
    -- File Cache & Version Hashing
    -- ========================================

    local file_cache = {}   -- {[client_type] = {content, version, filename}}

    -- Simple hash: sum of all bytes mod large prime
    local function compute_hash(content)
        local sum = 0
        for i = 1, #content do
            sum = (sum * 31 + string.byte(content, i)) % 2147483647
        end
        return tostring(sum)
    end

    local function load_client_files()
        local old_versions = {}
        for ctype, cached in pairs(file_cache) do
            old_versions[ctype] = cached.version
        end

        file_cache = {}
        if not fs.exists(client_dir) or not fs.isDir(client_dir) then
            utils.add_notification(state, "UPDATER: No clients/ directory", colors.orange)
            return 0, 0
        end

        local files = fs.list(client_dir)
        local count = 0
        local changed = 0
        for _, filename in ipairs(files) do
            if filename:match("%.lua$") then
                local path = client_dir .. "/" .. filename
                local f = fs.open(path, "r")
                if f then
                    local content = f.readAll()
                    f.close()
                    if content and #content > 0 then
                        local client_type = filename:gsub("%.lua$", "")
                        local new_version = compute_hash(content)
                        file_cache[client_type] = {
                            content = content,
                            version = new_version,
                            filename = filename,
                        }
                        count = count + 1
                        if old_versions[client_type] and old_versions[client_type] ~= new_version then
                            changed = changed + 1
                            utils.add_notification(state,
                                string.format("UPDATER: %s changed (will push on next check-in)", client_type),
                                colors.lime)
                        end
                    end
                end
            end
        end
        return count, changed
    end

    -- ========================================
    -- Initialize
    -- ========================================

    local count = load_client_files()
    utils.add_notification(state,
        string.format("UPDATER: %d client scripts cached", count),
        colors.cyan)

    -- ========================================
    -- Main Event Loop
    -- ========================================

    -- Periodically reload files in case they were updated
    local RELOAD_INTERVAL = 60
    local reload_timer = os.startTimer(RELOAD_INTERVAL)

    while state.running do
        local ev = {coroutine.yield()}

        if ev[1] == "rednet_message" then
            local sender = ev[2]
            local msg = ev[3]
            local protocol = ev[4]

            if protocol == proto.update_ping and type(msg) == "table" then
                local client_type = msg.client_type
                local client_version = msg.version

                if client_type and file_cache[client_type] then
                    local cached = file_cache[client_type]

                    if client_version ~= cached.version then
                        -- Client needs update — send new file content
                        rednet.send(sender, {
                            filename = "startup.lua",  -- always write as startup.lua on client
                            content = cached.content,
                            version = cached.version,
                        }, proto.update_push)

                        utils.add_notification(state,
                            string.format("UPDATER: Pushed %s to #%d", client_type, sender),
                            colors.lime)
                    end
                    -- If versions match, don't respond (client continues boot)
                end

            elseif protocol == proto.update_ack and type(msg) == "table" then
                -- Client acknowledged update
                utils.add_notification(state,
                    string.format("UPDATER: #%d acked update (%s)",
                        ev[2], msg.client_type or "?"),
                    colors.cyan)
            end

        elseif ev[1] == "timer" and ev[2] == reload_timer then
            -- Reload client files in case they were modified
            local _, changed = load_client_files()
            if changed > 0 then
                utils.add_notification(state,
                    string.format("UPDATER: %d file(s) updated, waiting for client check-in", changed),
                    colors.lime)
            end
            reload_timer = os.startTimer(RELOAD_INTERVAL)
        end
    end
end

return svc
