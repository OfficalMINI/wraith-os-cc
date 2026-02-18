-- =============================================
-- WRAITH OS - AR GOGGLES SERVICE
-- =============================================
-- Drives the ar_controller peripheral, renders
-- HUD overlay and 3D world markers, manages alerts.

local svc = {}

function svc.main(state, config, utils)
    local ar = state.ar
    local cfg = config.ar
    local SAVE_PATH = "wraith/ar_config.lua"

    -- ========================================
    -- Persistence
    -- ========================================
    local function load_config()
        if fs.exists(SAVE_PATH) then
            local f = fs.open(SAVE_PATH, "r")
            if f then
                local data = f.readAll()
                f.close()
                local fn = loadstring("return " .. data)
                if fn then
                    local ok, saved = pcall(fn)
                    if ok and type(saved) == "table" then
                        if saved.hud then
                            for k, v in pairs(saved.hud) do ar.hud[k] = v end
                        end
                        if saved.world then
                            for k, v in pairs(saved.world) do ar.world[k] = v end
                        end
                        if saved.pois then ar.pois = saved.pois end
                        if saved.enabled ~= nil then ar.enabled = saved.enabled end
                    end
                end
            end
        end
    end

    local function save_config()
        local data = {
            hud = ar.hud,
            world = ar.world,
            pois = ar.pois,
            enabled = ar.enabled,
        }
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 5 then return end
        local tmp = SAVE_PATH .. ".tmp"
        local f = fs.open(tmp, "w")
        if f then
            f.write(content)
            f.close()
            if fs.exists(SAVE_PATH) then fs.delete(SAVE_PATH) end
            fs.move(tmp, SAVE_PATH)
        end
    end

    -- ========================================
    -- Alert System
    -- ========================================
    ar.add_alert = function(msg, level, source)
        table.insert(ar.alerts, 1, {
            msg = msg,
            level = level or "info",
            source = source or "system",
            time = os.clock(),
            read = false,
        })
        while #ar.alerts > ar.max_alerts do
            table.remove(ar.alerts)
        end
        ar.alert_count = 0
        for _, a in ipairs(ar.alerts) do
            if not a.read then ar.alert_count = ar.alert_count + 1 end
        end
    end

    ar.clear_alerts = function()
        for _, a in ipairs(ar.alerts) do a.read = true end
        ar.alert_count = 0
    end

    -- ========================================
    -- Toggle Functions
    -- ========================================
    ar.toggle_hud = function(key)
        if ar.hud[key] ~= nil then
            ar.hud[key] = not ar.hud[key]
            save_config()
        end
    end

    ar.toggle_world = function(key)
        if ar.world[key] ~= nil then
            ar.world[key] = not ar.world[key]
            save_config()
        end
    end

    ar.set_enabled = function(on)
        ar.enabled = on
        save_config()
        if not on and ar.controller then
            pcall(function()
                ar.controller.clear()
                ar.controller.update()
            end)
        end
    end

    ar.add_poi = function(name, x, y, z, color)
        table.insert(ar.pois, {
            name = name, x = x, y = y, z = z,
            color = color or cfg.poi_default_color,
        })
        save_config()
    end

    ar.remove_poi = function(idx)
        if ar.pois[idx] then
            table.remove(ar.pois, idx)
            save_config()
            return true
        end
        return false
    end

    -- ========================================
    -- Peripheral Discovery
    -- ========================================
    local function find_controller()
        local ctrl = peripheral.find("ar_controller")
        if ctrl then
            ar.controller = ctrl
            ar.controller_name = peripheral.getName(ctrl)
            ar.connected = true
            return true
        end
        ar.controller = nil
        ar.controller_name = ""
        ar.connected = false
        return false
    end

    -- ========================================
    -- Alert Generation (threshold monitoring)
    -- ========================================
    local prev = {
        storage_pct = 0,
        storage_high = false,
        storage_crit = false,
        fuel_low = false,
        mining_on = false,
        hub_connected = false,
    }

    local function check_alerts()
        local st = state.storage

        -- Storage capacity
        if st.stats then
            local pct = st.stats.usage_pct or 0
            if pct > 0.95 and not prev.storage_crit then
                ar.add_alert("Storage CRITICAL: " .. math.floor(pct * 100) .. "%", "critical", "storage")
                prev.storage_crit = true
            elseif pct > 0.85 and not prev.storage_high then
                ar.add_alert("Storage HIGH: " .. math.floor(pct * 100) .. "%", "warning", "storage")
                prev.storage_high = true
            end
            if pct <= 0.85 then prev.storage_high = false; prev.storage_crit = false end
            if pct <= 0.95 then prev.storage_crit = false end
            prev.storage_pct = pct
        end

        -- Fuel level
        if st.fuel_peripheral then
            local fl = st.fuel_chest_level or 0
            local ft = st.fuel_chest_target or 128
            local low = ft > 0 and (fl / ft < 0.25)
            if low and not prev.fuel_low then
                ar.add_alert(string.format("Fuel LOW: %d/%d", fl, ft), "warning", "storage")
            end
            prev.fuel_low = low
        end

        -- Mining state changes
        local mm = state.mastermine
        if mm.mining_on ~= prev.mining_on then
            ar.add_alert("Mining " .. (mm.mining_on and "STARTED" or "STOPPED"), "info", "mining")
            prev.mining_on = mm.mining_on
        end

        -- Hub connection
        if mm.hub_connected ~= prev.hub_connected then
            if not mm.hub_connected and prev.hub_connected then
                ar.add_alert("MasterMine hub DISCONNECTED", "warning", "mining")
            end
            prev.hub_connected = mm.hub_connected
        end

        -- Halted turtles
        for tid, t in pairs(mm.turtles or {}) do
            if t.state == "halt" then
                local key = "turtle_halt_" .. tostring(tid)
                if not prev[key] then
                    ar.add_alert("Turtle #" .. tostring(tid) .. " HALTED", "warning", "mining")
                    prev[key] = true
                end
            else
                prev["turtle_halt_" .. tostring(tid)] = nil
            end
        end
    end

    -- ========================================
    -- HUD Renderer (Top + Bottom Ribbons)
    -- ========================================
    local function render_hud()
        local ctrl = ar.controller
        local x = cfg.hud_x_offset
        local sp = cfg.hud_line_spacing
        local pw = cfg.hud_panel_width
        local now = os.clock()
        local id_n = 0

        local function nid(prefix)
            id_n = id_n + 1
            return prefix .. "_" .. id_n
        end

        -- Helper: inline progress bar, returns next cx position
        local function draw_bar(bx, by, pct, col, w)
            w = w or 60
            local filled = math.max(math.floor(pct / 100 * w), 0)
            ctrl.drawText2D(nid("bl"), cfg.hud_dim, bx, by - 3, "[", false)
            if filled > 0 then
                ctrl.drawHorizontalLine2D(nid("bf"), col, bx + 6, by, bx + 6 + filled)
            end
            if filled < w then
                ctrl.drawHorizontalLine2D(nid("be"), cfg.hud_frame_color,
                    bx + 6 + filled, by, bx + 6 + w)
            end
            ctrl.drawText2D(nid("br"), cfg.hud_dim, bx + w + 8, by - 3, "]", false)
            return bx + w + 16
        end

        -- Helper: vertical separator, returns next cx
        local function sep(cx, cy)
            ctrl.drawText2D(nid("sep"), cfg.hud_frame_color, cx, cy, "|", false)
            return cx + 8
        end

        -- Helper: draw ribbon background + accent border lines
        local function ribbon(ry, rh)
            ctrl.drawRect2D(nid("rbg"), cfg.hud_bg_color,
                x - 2, ry - 2, x + pw + 2, ry + rh + 2)
            ctrl.drawHorizontalLine2D(nid("rt"), cfg.hud_accent, x, ry - 2, x + pw)
            ctrl.drawHorizontalLine2D(nid("rb"), cfg.hud_accent, x, ry + rh + 2, x + pw)
        end

        -- ═══════════════════════════════════════
        -- TOP RIBBON — identity, clock, storage, fuel, smelting
        -- ═══════════════════════════════════════
        local ty = cfg.hud_y_offset
        ribbon(ty, sp)

        -- Scan line animation (vertical sweep across ribbon)
        local scan_period = 4
        local scan_x = x + ((now % scan_period) / scan_period) * pw
        ctrl.drawVerticalLine2D(nid("scan"), cfg.hud_scan_color,
            scan_x, ty - 2, ty + sp + 2)

        local cx = x + 4

        -- Logo
        ctrl.drawText2D(nid("logo"), cfg.hud_accent, cx, ty,
            "\4 WRAITH", false)
        cx = cx + 52

        -- Clock + uptime
        if ar.hud.show_clock then
            cx = sep(cx, ty)
            local day = os.day()
            local time = textutils.formatTime(os.time(), true)
            ctrl.drawText2D(nid("clk"), cfg.hud_color, cx, ty,
                string.format("D%d %s", day, time), false)
            cx = cx + 62

            if ar.boot_time then
                local up = now - ar.boot_time
                local h = math.floor(up / 3600)
                local m = math.floor((up % 3600) / 60)
                ctrl.drawText2D(nid("up"), cfg.hud_dim, cx, ty,
                    string.format("UP%dh%02dm", h, m), false)
                cx = cx + 50
            end
        end

        -- Storage bar
        if ar.hud.show_storage and state.storage.ready and state.storage.stats then
            cx = sep(cx, ty)
            local pct = math.floor(state.storage.stats.usage_pct * 100)
            local col = pct > 90 and cfg.hud_danger
                or (pct > 70 and cfg.hud_warning or cfg.hud_success)
            ctrl.drawText2D(nid("sl"), cfg.hud_section_color, cx, ty, "STOR", false)
            cx = cx + 28
            cx = draw_bar(cx, ty + 3, pct, col, 50)
            ctrl.drawText2D(nid("spct"), col, cx, ty,
                string.format("%d%%", pct), false)
            cx = cx + 22
        end

        -- Fuel bar
        if ar.hud.show_fuel and state.storage.fuel_peripheral then
            cx = sep(cx, ty)
            local fl = state.storage.fuel_chest_level or 0
            local ft = state.storage.fuel_chest_target or 128
            local fpct = ft > 0 and math.floor(fl / ft * 100) or 0
            local col = fpct < 25 and cfg.hud_danger
                or (fpct < 50 and cfg.hud_warning or cfg.hud_success)
            ctrl.drawText2D(nid("fl"), cfg.hud_section_color, cx, ty, "FUEL", false)
            cx = cx + 28
            cx = draw_bar(cx, ty + 3, fpct, col, 40)
            ctrl.drawText2D(nid("fv"), col, cx, ty,
                string.format("%d/%d", fl, ft), false)
            cx = cx + 36
        end

        -- Smelting status (compact)
        if ar.hud.show_smelting and state.storage.furnace_count
                and state.storage.furnace_count > 0 then
            cx = sep(cx, ty)
            local on = state.storage.smelting_enabled
            local col = on and cfg.hud_success or cfg.hud_danger
            -- Animated dot
            local dot_vis = on and (math.floor(now * 2) % 2 == 0)
            ctrl.drawText2D(nid("sdot"),
                dot_vis and cfg.hud_success or col, cx, ty, "\7", false)
            cx = cx + 8
            ctrl.drawText2D(nid("sst"), col, cx, ty,
                on and "SMELT" or "OFF", false)
            cx = cx + (on and 32 or 22)
            ctrl.drawText2D(nid("sfc"), cfg.hud_dim, cx, ty,
                string.format("%dF", state.storage.furnace_count), false)
        end

        -- Computer ID (right-aligned)
        ctrl.drawText2D(nid("cid"), cfg.hud_dim, x + pw - 24, ty,
            string.format("#%d", os.getComputerID()), false)

        -- ═══════════════════════════════════════
        -- BOTTOM RIBBON — mining, project, alerts
        -- ═══════════════════════════════════════
        local by = cfg.hud_bottom_y
        ribbon(by, sp)

        cx = x + 4

        -- Mining status
        if ar.hud.show_mining and state.mastermine.hub_id then
            local mm = state.mastermine
            local mine_col = mm.mining_on and cfg.hud_success or cfg.hud_danger
            -- Animated dot
            local dot_vis = mm.mining_on and (math.floor(now * 2) % 2 == 0)
            ctrl.drawText2D(nid("mdot"),
                dot_vis and cfg.hud_success or mine_col, cx, by, "\7", false)
            cx = cx + 8
            ctrl.drawText2D(nid("mst"), mine_col, cx, by,
                mm.mining_on and "MINE" or "IDLE", false)
            cx = cx + 30

            -- Hub
            local hub_col = mm.hub_connected and cfg.hud_success or cfg.hud_danger
            ctrl.drawText2D(nid("hub"), hub_col, cx, by,
                "HUB:" .. (mm.hub_connected and "OK" or "DN"), false)
            cx = cx + 38

            -- Turtle count
            local tc = 0
            local halted = 0
            for _, t in pairs(mm.turtles or {}) do
                tc = tc + 1
                if t.state == "halt" then halted = halted + 1 end
            end
            ctrl.drawText2D(nid("tc"), cfg.hud_color, cx, by,
                string.format("%dT", tc), false)
            cx = cx + 16

            -- Halted warning (blinking)
            if halted > 0 then
                local blink = math.floor(now * 3) % 2 == 0
                ctrl.drawText2D(nid("thalt"),
                    blink and cfg.hud_danger or cfg.hud_warning,
                    cx, by, string.format("%dH!", halted), false)
                cx = cx + 22
            end
        end

        -- Active project (compact)
        if ar.hud.show_projects and state.projects.active_idx then
            local proj = state.projects
            local project = proj.list[proj.active_idx]
            if project then
                cx = sep(cx, by)
                local cov = proj.coverage[proj.active_idx] or {}
                local total_have, total_need = 0, 0
                for _, item in ipairs(project.items) do
                    local c = cov[item.name]
                    if c then
                        total_have = total_have + math.min(c.have, c.need)
                        total_need = total_need + c.need
                    else
                        total_need = total_need + item.need
                    end
                end
                local pct = total_need > 0
                    and math.floor(total_have / total_need * 100) or 100
                local col = pct >= 100 and cfg.hud_success
                    or (pct >= 50 and cfg.hud_warning or cfg.hud_danger)

                -- Truncated project name
                local pname = project.name
                if #pname > 12 then pname = pname:sub(1, 10) .. ".." end
                ctrl.drawText2D(nid("pn"), cfg.hud_color, cx, by, pname, false)
                cx = cx + #pname * 6 + 4

                cx = draw_bar(cx, by + 3, math.min(pct, 100), col, 45)
                ctrl.drawText2D(nid("ppct"), col, cx, by,
                    string.format("%d%%", pct), false)
                cx = cx + 22
            end
        end

        -- Alerts (latest 1-2, compact inline)
        if ar.hud.show_alerts and #ar.alerts > 0 then
            local shown = 0
            for _, alert in ipairs(ar.alerts) do
                if shown >= 2 then break end
                if now - alert.time < cfg.alert_duration then
                    if shown == 0 then cx = sep(cx, by) end

                    local col, prefix
                    if alert.level == "critical" then
                        local pulse = math.floor(now * 3) % 2 == 0
                        col = pulse and cfg.hud_danger or cfg.hud_warning
                        prefix = "!! "
                    elseif alert.level == "warning" then
                        col = cfg.hud_warning
                        prefix = "! "
                    else
                        col = cfg.hud_accent
                        prefix = "> "
                    end

                    -- Truncated message + time ago
                    local msg = alert.msg
                    if #msg > 20 then msg = msg:sub(1, 18) .. ".." end
                    local ago = math.floor(now - alert.time)
                    local ago_str = ago < 60 and (ago .. "s")
                        or (math.floor(ago / 60) .. "m")

                    ctrl.drawText2D(nid("alrt"), col, cx, by,
                        prefix .. msg, false)
                    cx = cx + (#prefix + #msg) * 6 + 4
                    ctrl.drawText2D(nid("aago"), cfg.hud_dim, cx, by,
                        ago_str, false)
                    cx = cx + 20
                    shown = shown + 1
                end
            end
        end
    end

    -- ========================================
    -- World Renderer (3D markers with beams)
    -- ========================================
    local function render_world()
        local ctrl = ar.controller
        local now = os.clock()
        local id_n = 1000
        local bh = cfg.beam_height

        local function nid(prefix)
            id_n = id_n + 1
            return prefix .. "_" .. id_n
        end

        -- Mine entrance with vertical beacon beam
        if ar.world.show_mine_entrance then
            local mm = state.mastermine
            if mm.hub_config and mm.hub_config.mine_entrance then
                local me = mm.hub_config.mine_entrance
                -- Vertical beam
                ctrl.drawLine3D(nid("mbeam"), cfg.beam_color,
                    me.x + 0.5, me.y, me.z + 0.5,
                    me.x + 0.5, me.y + bh, me.z + 0.5)
                -- Label
                ctrl.drawText3D(nid("ment"), cfg.mine_marker_color,
                    me.x + 0.5, me.y + 3, me.z + 0.5,
                    0, 0, cfg.marker_text_size, "MINE ENTRANCE", true)
                -- Coordinates
                ctrl.drawText3D(nid("mcoord"), cfg.hud_dim,
                    me.x + 0.5, me.y + 2, me.z + 0.5,
                    0, 0, cfg.marker_text_size * 0.8,
                    string.format("[%d, %d, %d]", me.x, me.y, me.z), true)
                -- Pickaxe icon
                ctrl.drawItemIcon3D(nid("mico"), me.x + 0.5, me.y + 1, me.z + 0.5,
                    0, 0, cfg.marker_size, "minecraft:diamond_pickaxe")
            end
        end

        -- Turtles with state-based coloring and fuel indicators
        if ar.world.show_turtles then
            local mm = state.mastermine
            for tid, t in pairs(mm.turtles or {}) do
                if t.location and t.location.x then
                    local loc = t.location

                    -- Color based on turtle state
                    local col
                    if t.state == "halt" then
                        -- Blink red/yellow for halted
                        col = (math.floor(now * 2) % 2 == 0)
                            and cfg.hud_danger or cfg.hud_warning
                    elseif t.state == "mine" or t.state == "dig" then
                        col = cfg.hud_success
                    elseif t.state == "nav" or t.state == "move" then
                        col = cfg.turtle_marker_color
                    else
                        col = cfg.hud_dim
                    end

                    -- ID + state label
                    local label = string.format("#%s %s",
                        tostring(tid), t.state or "?")
                    ctrl.drawText3D(nid("trt"), col,
                        loc.x + 0.5, loc.y + 1.5, loc.z + 0.5,
                        0, 0, cfg.marker_text_size, label, true)

                    -- Fuel level indicator (if available)
                    if t.fuel_level then
                        local fuel_col
                        if t.fuel_level < 100 then
                            fuel_col = cfg.hud_danger
                        elseif t.fuel_level < 500 then
                            fuel_col = cfg.hud_warning
                        else
                            fuel_col = cfg.hud_success
                        end
                        ctrl.drawText3D(nid("trf"), fuel_col,
                            loc.x + 0.5, loc.y + 0.8, loc.z + 0.5,
                            0, 0, cfg.marker_text_size * 0.7,
                            string.format("F:%d", t.fuel_level), true)
                    end

                    -- Vertical distress beam for halted turtles
                    if t.state == "halt" then
                        local beam_col = (math.floor(now * 2) % 2 == 0)
                            and cfg.hud_danger or cfg.hud_warning
                        ctrl.drawLine3D(nid("thl"), beam_col,
                            loc.x + 0.5, loc.y, loc.z + 0.5,
                            loc.x + 0.5, loc.y + 5, loc.z + 0.5)
                    end
                end
            end
        end

        -- Points of interest with beacon beams and coordinates
        if ar.world.show_pois then
            for _, poi in ipairs(ar.pois) do
                local col = poi.color or cfg.poi_default_color
                -- Vertical beam
                ctrl.drawLine3D(nid("poib"), col,
                    poi.x + 0.5, poi.y, poi.z + 0.5,
                    poi.x + 0.5, poi.y + bh * 0.6, poi.z + 0.5)
                -- Name label
                ctrl.drawText3D(nid("poi"), col,
                    poi.x + 0.5, poi.y + 2.5, poi.z + 0.5,
                    0, 0, cfg.marker_text_size, poi.name, true)
                -- Coordinates
                ctrl.drawText3D(nid("poic"), cfg.hud_dim,
                    poi.x + 0.5, poi.y + 1.5, poi.z + 0.5,
                    0, 0, cfg.marker_text_size * 0.7,
                    string.format("[%d,%d,%d]", poi.x, poi.y, poi.z), true)
            end
        end

        -- Project blocks summary
        if ar.world.show_project_blocks and state.projects.active_idx then
            local proj = state.projects
            local project = proj.list[proj.active_idx]
            if project and #project.items > 0 then
                local cov = proj.coverage[proj.active_idx] or {}
                local count = 0
                for _, item in ipairs(project.items) do
                    local c = cov[item.name]
                    if c and c.pct < 1 then
                        count = count + 1
                    end
                end
                if count > 0 then
                    ctrl.drawText3D(nid("pblk"), cfg.project_block_color,
                        0.5, 2, 0.5, 0, 0, cfg.marker_text_size,
                        string.format("%s: %d items needed", project.name, count), true)
                end
            end
        end
    end

    -- ========================================
    -- Full Render Cycle
    -- ========================================
    local function render()
        if not ar.connected or not ar.enabled then return end
        local ok, err = pcall(function()
            ar.controller.clear()
            render_hud()
            render_world()
            ar.controller.update()
        end)
        if not ok then
            -- Controller may have been disconnected
            if not peripheral.isPresent(ar.controller_name) then
                ar.connected = false
                ar.controller = nil
            end
        end
    end

    -- ========================================
    -- Init & Main Loop
    -- ========================================
    load_config()
    ar.boot_time = os.clock()
    ar.ready = true

    if find_controller() then
        utils.add_notification(state, "AR: Controller found - " .. ar.controller_name, colors.lime)
    else
        utils.set_status(state, "AR: No controller (waiting...)", colors.orange, 5)
    end

    -- Clock-based scheduling
    local next_render = os.clock() + 1
    local next_alert_check = os.clock() + 3
    local heartbeat = os.startTimer(1)

    while state.running do
        local ev, p1 = os.pullEvent()
        local now = os.clock()

        -- Peripheral hotplug
        if ev == "peripheral" or ev == "peripheral_detach" then
            sleep(0.3)
            if not ar.connected then
                if find_controller() then
                    utils.add_notification(state, "AR: Controller connected", colors.lime)
                end
            else
                if not peripheral.isPresent(ar.controller_name) then
                    ar.connected = false
                    ar.controller = nil
                    utils.add_notification(state, "AR: Controller disconnected", colors.red)
                end
            end
        end

        -- Render cycle
        if now >= next_render then
            render()
            next_render = now + cfg.refresh_interval
        end

        -- Alert check
        if now >= next_alert_check then
            check_alerts()
            next_alert_check = now + 5
        end

        -- Heartbeat
        if ev == "timer" and p1 == heartbeat then
            heartbeat = os.startTimer(1)
        end
    end

    -- Cleanup
    if ar.controller then
        pcall(function()
            ar.controller.clear()
            ar.controller.update()
        end)
    end
end

return svc
