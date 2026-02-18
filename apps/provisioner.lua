-- =============================================
-- WRAITH OS - PROVISIONER APP
-- =============================================
-- Write client startup files to floppy disks
-- for one-click provisioning of new computers
-- and turtles. Downloads latest code from GitHub.

local app = {
    id = "provisioner",
    name = "Provisioner",
    icon = "provisioner",
    default_w = 46,
    default_h = 24,
    singleton = true,
}

-- ========================================
-- Client definitions (GitHub raw URLs)
-- ========================================
local CLIENTS = {
    {id = "crafting_client",  label = "Crafting Turtle",  url = "https://raw.githubusercontent.com/OfficalMINI/cc_wraith_clients/refs/heads/main/crafting_client.lua"},
    {id = "lighting_client",  label = "Lighting Client",  url = "https://raw.githubusercontent.com/OfficalMINI/cc_wraith_clients/refs/heads/main/lighting_client.lua"},
    {id = "station_client",   label = "Station Client",   url = "https://raw.githubusercontent.com/OfficalMINI/cc_wraith_clients/refs/heads/main/station_client.lua"},
    {id = "train_client",     label = "Train Client",     url = "https://raw.githubusercontent.com/OfficalMINI/cc_wraith_clients/refs/heads/main/train_client.lua"},
    {id = "tree_client",      label = "Tree Farm Turtle", url = "https://raw.githubusercontent.com/OfficalMINI/cc_wraith_tree_client/refs/heads/main/tree_client.lua"},
}

-- Generate bootstrapper script with embedded label
local function make_bootstrapper(label)
    return '-- Wraith OS Provisioner - Auto-install\n'
        .. '-- This floppy installs a client to any computer placed on this drive\n'
        .. 'local mount = fs.getDir(shell.getRunningProgram())\n'
        .. 'local src = "/" .. mount .. "/client.lua"\n'
        .. 'if not fs.exists(src) then\n'
        .. '    printError("No client.lua on this disk!")\n'
        .. '    print("Re-provision this floppy from the Wraith Provisioner app.")\n'
        .. '    return\n'
        .. 'end\n'
        .. 'local f = fs.open(src, "r")\n'
        .. 'local code = f.readAll()\n'
        .. 'f.close()\n'
        .. 'local out = fs.open("/startup.lua", "w")\n'
        .. 'out.write(code)\n'
        .. 'out.close()\n'
        .. 'os.setComputerLabel("' .. label .. ' #" .. os.getComputerID())\n'
        .. 'term.setBackgroundColor(colors.black)\n'
        .. 'term.clear()\n'
        .. 'term.setCursorPos(1, 1)\n'
        .. 'term.setTextColor(colors.lime)\n'
        .. 'print("Wraith OS - ' .. label .. ' Installed!")\n'
        .. 'term.setTextColor(colors.white)\n'
        .. 'print("Rebooting...")\n'
        .. 'sleep(1)\n'
        .. 'os.reboot()\n'
end

-- ========================================
-- State
-- ========================================
local hits = {}
local drives = {}          -- {{name, drive, present, has_data, label, mount}, ...}
local selected_drive = nil -- peripheral name
local selected_client = 1  -- index into CLIENTS
local status_msg = ""
local status_color = nil
local provisioned = 0      -- session counter
local busy = false         -- true during download/write

-- ========================================
-- Drive scanning
-- ========================================
local function scan_drives()
    drives = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ok, ptype = pcall(peripheral.getType, name)
        if ok and ptype == "drive" then
            local d = peripheral.wrap(name)
            if d then
                local info = {
                    name = name,
                    drive = d,
                    present = false,
                    has_data = false,
                    label = nil,
                    mount = nil,
                }
                pcall(function()
                    info.present = d.isDiskPresent()
                    info.has_data = d.hasData()
                    info.label = d.getDiskLabel()
                    info.mount = d.getMountPath()
                end)
                table.insert(info, name) -- for sorting
                table.insert(drives, info)
            end
        end
    end
    table.sort(drives, function(a, b) return a.name < b.name end)

    -- Auto-select first drive if current selection is gone
    if selected_drive then
        local found = false
        for _, d in ipairs(drives) do
            if d.name == selected_drive then found = true; break end
        end
        if not found then selected_drive = nil end
    end
    if not selected_drive and #drives > 0 then
        selected_drive = drives[1].name
    end
end

-- ========================================
-- Get selected drive info
-- ========================================
local function get_drive_info()
    for _, d in ipairs(drives) do
        if d.name == selected_drive then return d end
    end
    return nil
end

-- ========================================
-- Provision: download + write to floppy
-- ========================================
local function provision(client)
    local info = get_drive_info()
    if not info then return false, "No drive selected" end
    if not info.present then return false, "No disk in drive" end
    if not info.has_data then return false, "Disk has no filesystem" end

    -- Download latest client code from GitHub
    if not http then return false, "HTTP API disabled" end
    local ok, resp = pcall(http.get, client.url)
    if not ok or not resp then
        return false, "Download failed"
    end
    local code = resp.readAll()
    resp.close()
    if not code or #code < 10 then
        return false, "Empty download"
    end

    local mount = info.mount
    if not mount then return false, "No mount path" end

    -- Write bootstrapper startup.lua (sets computer label to client type + ID)
    local f = fs.open("/" .. mount .. "/startup.lua", "w")
    if not f then return false, "Cannot write startup.lua" end
    f.write(make_bootstrapper(client.label))
    f.close()

    -- Write actual client code
    f = fs.open("/" .. mount .. "/client.lua", "w")
    if not f then return false, "Cannot write client.lua" end
    f.write(code)
    f.close()

    -- Label the disk
    pcall(info.drive.setDiskLabel, "wraith_" .. client.id)

    provisioned = provisioned + 1
    return true, client.label .. " ready"
end

-- ========================================
-- Render
-- ========================================
function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme

    hits = {}
    hits.oy = y

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "PROVISIONER", theme.accent, theme.surface2)
    if provisioned > 0 then
        local cnt = tostring(provisioned) .. " done"
        draw.put(buf, x + w - #cnt - 1, y, cnt, theme.success, theme.surface2)
    end
    y = y + 1

    -- Status bar
    if status_msg ~= "" then
        draw.fill(buf, y, x + w, theme.surface)
        local sc = status_color or theme.fg_dim
        draw.put(buf, x + 1, y, status_msg:sub(1, w - 2), sc, theme.surface)
        y = y + 1
    end

    -- Divider
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- ==============================
    -- Drive selector
    -- ==============================
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "DRIVE", theme.fg_dim, theme.surface2)
    draw.button(buf, x + w - 9, y, 8, 1, "RESCAN", theme.accent, theme.btn_text, true)
    hits.rescan_btn = {x = w - 9 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    y = y + 1

    hits.drive_rows = {}
    if #drives == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "No disk drives found on network", theme.fg_dim, theme.surface)
        y = y + 1
    else
        for di, d in ipairs(drives) do
            local sel = (d.name == selected_drive)
            local bg = sel and theme.accent2 or ((di % 2 == 0) and theme.surface2 or theme.surface)
            local fg = sel and theme.bg or theme.fg
            draw.fill(buf, y, x + w, bg)

            local marker = sel and "\16 " or "  "
            local disk_status
            if d.present and d.has_data then
                disk_status = d.label or "floppy"
            elseif d.present then
                disk_status = "no data"
            else
                disk_status = "empty"
            end
            local status_col = (d.present and d.has_data) and (sel and theme.bg or theme.success)
                or (sel and theme.bg or theme.fg_dim)

            draw.put(buf, x + 1, y, marker .. d.name:sub(1, w - 18), fg, bg)
            draw.put(buf, x + w - #disk_status - 2, y, disk_status, status_col, bg)
            hits.drive_rows[di] = {x = 1, y = y - hits.oy + 1, w = w, h = 1, name = d.name}
            y = y + 1
            if di >= 5 then break end -- max 5 drives shown
        end
    end

    -- Divider
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- ==============================
    -- Client selector
    -- ==============================
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "CLIENT TYPE", theme.fg_dim, theme.surface2)
    y = y + 1

    hits.client_rows = {}
    for ci, c in ipairs(CLIENTS) do
        if y >= ctx.content_y + h - 3 then break end
        local sel = (ci == selected_client)
        local bg = sel and theme.accent2 or ((ci % 2 == 0) and theme.surface2 or theme.surface)
        local fg = sel and theme.bg or theme.fg
        draw.fill(buf, y, x + w, bg)

        local marker = sel and "\16 " or "  "
        draw.put(buf, x + 1, y, marker .. c.label, fg, bg)
        hits.client_rows[ci] = {x = 1, y = y - hits.oy + 1, w = w, h = 1}
        y = y + 1
    end

    -- Fill remaining
    while y < ctx.content_y + h - 2 do
        draw.fill(buf, y, x + w, theme.surface)
        y = y + 1
    end

    -- Divider
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- ==============================
    -- Provision button
    -- ==============================
    local di = get_drive_info()
    local can_provision = di and di.present and di.has_data and not busy
    local btn_label = busy and " WRITING... " or " PROVISION "
    local btn_bg = can_provision and theme.success or theme.btn_disabled_bg
    local btn_fg = can_provision and theme.btn_text or theme.btn_disabled_fg
    local btn_w = #btn_label + 2
    local btn_x = x + math.floor((w - btn_w) / 2)
    draw.fill(buf, y, x + w, theme.surface)
    draw.button(buf, btn_x, y, btn_w, 1, btn_label, btn_bg, btn_fg, can_provision)
    hits.provision_btn = {x = btn_x - x + 1, y = y - hits.oy + 1, w = btn_w, h = 1, enabled = can_provision}
end

-- ========================================
-- Event loop
-- ========================================
function app.main(ctx)
    local draw = ctx.draw
    scan_drives()

    while true do
        local ev = {coroutine.yield()}

        -- Auto-rescan on disk/peripheral events
        if ev[1] == "disk" or ev[1] == "disk_eject"
           or ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            scan_drives()
        end

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3] - 1, ev[4]

            -- Rescan button
            if hits.rescan_btn and draw.hit_test(hits.rescan_btn, tx, ty) then
                scan_drives()
                status_msg = "Drives rescanned"
                status_color = ctx.theme.info
            end

            -- Drive selection
            if hits.drive_rows then
                for _, row in pairs(hits.drive_rows) do
                    if draw.hit_test(row, tx, ty) then
                        selected_drive = row.name
                        status_msg = "Drive: " .. row.name
                        status_color = ctx.theme.accent
                        break
                    end
                end
            end

            -- Client selection
            if hits.client_rows then
                for ci, area in pairs(hits.client_rows) do
                    if draw.hit_test(area, tx, ty) then
                        selected_client = ci
                        break
                    end
                end
            end

            -- Provision button
            if hits.provision_btn and hits.provision_btn.enabled
               and draw.hit_test(hits.provision_btn, tx, ty) then
                busy = true
                status_msg = "Downloading " .. CLIENTS[selected_client].label .. "..."
                status_color = ctx.theme.info

                -- Yield once to let UI update before blocking HTTP call
                coroutine.yield()

                local ok, msg = provision(CLIENTS[selected_client])
                busy = false
                status_msg = msg
                status_color = ok and ctx.theme.success or ctx.theme.danger
                -- Re-scan to update label
                if ok then scan_drives() end
            end
        end
    end
end

return app
