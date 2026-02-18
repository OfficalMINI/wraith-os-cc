-- =============================================
-- WRAITH OS - LOADOUTS APP
-- =============================================
-- Save and equip player gear loadouts using
-- Inventory Manager peripherals.

local app = {
    id = "loadouts",
    name = "Loadouts",
    icon = "loadouts",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

local tab = 1       -- 1=Loadouts, 2=Detail, 3=Equip
local TAB_COUNT = 3
local scroll = 0
local hits = {}

-- Selection state
local selected_loadout = nil    -- name of selected loadout
local selected_im = nil         -- periph name of selected IM
local assigning_im = nil        -- IM name when picking a barrel

-- ========================================
-- Render: Loadouts Tab (list)
-- ========================================
local function render_loadouts_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ld = ctx.state.loadouts

    -- Header row
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x + 1, y, "NAME", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 22, y, "ARMOR", theme.fg_dim, theme.surface2)
    draw.put(buf, x + 30, y, "ITEMS", theme.fg_dim, theme.surface2)

    -- NEW button
    draw.button(buf, x + w - 6, y, 5, 1, "+ NEW", theme.accent, theme.btn_text, true)
    hits.new_btn = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    y = y + 1

    -- Build sorted loadout list
    local loadout_list = {}
    for name, data in pairs(ld.saved) do
        table.insert(loadout_list, data)
    end
    table.sort(loadout_list, function(a, b) return a.name < b.name end)

    local area_h = h - 2
    local max_scroll = math.max(0, #loadout_list - area_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.loadout_rows = {}

    for vi = 1, area_h do
        local idx = scroll + vi
        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)
        if idx <= #loadout_list then
            local lo = loadout_list[idx]
            -- Name
            local name_display = lo.name
            if #name_display > 19 then name_display = name_display:sub(1, 17) .. ".." end
            draw.put(buf, x + 1, y, name_display, theme.fg, rbg)
            -- Armor count
            draw.put(buf, x + 22, y, tostring(#(lo.armor or {})), theme.fg_dim, rbg)
            -- Inventory count
            local inv_count = #(lo.inventory or {})
            if lo.hand then inv_count = inv_count + 1 end
            if lo.offhand then inv_count = inv_count + 1 end
            draw.put(buf, x + 30, y, tostring(inv_count), theme.fg_dim, rbg)
            -- Delete button
            draw.button(buf, x + w - 4, y, 3, 1, "X", theme.danger, theme.btn_text, true)
            table.insert(hits.loadout_rows, {
                x = 1, y = y - hits.oy + 1, w = w - 5, h = 1,
                name = lo.name,
                del_btn = {x = w - 4 + 1, y = y - hits.oy + 1, w = 3, h = 1},
            })
        end
        y = y + 1
    end

    -- Empty state
    if #loadout_list == 0 then
        local msg_y = ctx.content_y + 8
        draw.fill(buf, msg_y, x + w, theme.surface)
        draw.center(buf, "No loadouts saved", msg_y, x + w, theme.fg_dim, theme.surface)
        draw.fill(buf, msg_y + 1, x + w, theme.surface)
        draw.center(buf, "Click + NEW to snapshot your gear", msg_y + 1, x + w, theme.fg_dim, theme.surface)
    end

    -- Scroll bar
    draw.fill(buf, y, x + w, theme.surface2)
    if #loadout_list > area_h then
        draw.button(buf, x + 1, y, 5, 1, " \30 ", theme.accent, theme.surface2, scroll > 0)
        hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 5, h = 1}
        local info = string.format("%d-%d of %d", scroll + 1, math.min(scroll + area_h, #loadout_list), #loadout_list)
        draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface2)
        draw.button(buf, x + w - 6, y, 5, 1, " \31 ", theme.accent, theme.surface2, scroll < max_scroll)
        hits.scroll_down = {x = w - 6 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    else
        draw.center(buf, string.format("%d loadouts", #loadout_list), y, x + w, theme.fg_dim, theme.surface2)
    end
end

-- ========================================
-- Render: Detail Tab
-- ========================================
local function render_detail_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ld = ctx.state.loadouts

    if not selected_loadout or not ld.saved[selected_loadout] then
        local msg_y = y + 4
        draw.fill(buf, msg_y, x + w, theme.surface)
        draw.center(buf, "Select a loadout from the Loadouts tab", msg_y, x + w, theme.fg_dim, theme.surface)
        return
    end

    local lo = ld.saved[selected_loadout]

    -- Header
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "Loadout: ", theme.fg_dim, theme.surface)
    draw.put(buf, x + 10, y, lo.name, theme.accent, theme.surface)

    -- Action buttons
    draw.button(buf, x + w - 18, y, 8, 1, "RENAME", theme.accent, theme.btn_text, true)
    hits.detail_rename = {x = w - 18 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    draw.button(buf, x + w - 9, y, 8, 1, "RE-SNAP", theme.warning, theme.btn_text, true)
    hits.detail_resnap = {x = w - 9 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Armor section
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "ARMOR", theme.accent, theme.surface)
    y = y + 1

    if #(lo.armor or {}) == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "(none)", theme.fg_dim, theme.surface)
        y = y + 1
    else
        for _, item in ipairs(lo.armor) do
            draw.fill(buf, y, x + w, theme.surface)
            local display = item.displayName or item.name
            if #display > w - 4 then display = display:sub(1, w - 6) .. ".." end
            draw.put(buf, x + 2, y, "\7 ", theme.success, theme.surface)
            draw.put(buf, x + 4, y, display, theme.fg, theme.surface)
            y = y + 1
        end
    end
    y = y + 1

    -- Hand items
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "HANDS", theme.accent, theme.surface)
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    if lo.hand then
        local display = lo.hand.displayName or lo.hand.name
        if #display > w - 16 then display = display:sub(1, w - 18) .. ".." end
        draw.put(buf, x + 2, y, "Main: ", theme.fg_dim, theme.surface)
        draw.put(buf, x + 8, y, display, theme.fg, theme.surface)
    else
        draw.put(buf, x + 2, y, "Main: (empty)", theme.fg_dim, theme.surface)
    end
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    if lo.offhand then
        local display = lo.offhand.displayName or lo.offhand.name
        if #display > w - 16 then display = display:sub(1, w - 18) .. ".." end
        draw.put(buf, x + 2, y, "Off:  ", theme.fg_dim, theme.surface)
        draw.put(buf, x + 8, y, display, theme.fg, theme.surface)
    else
        draw.put(buf, x + 2, y, "Off:  (empty)", theme.fg_dim, theme.surface)
    end
    y = y + 2

    -- Inventory section
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, string.format("INVENTORY (%d items)", #(lo.inventory or {})), theme.accent, theme.surface)
    y = y + 1

    local inv = lo.inventory or {}
    local remaining_h = h - (y - ctx.content_y) - 1

    -- Aggregate same items
    local aggregated = {}
    local agg_order = {}
    for _, item in ipairs(inv) do
        local nbt_key = item.nbt and tostring(item.nbt) or ""
        local key = item.name .. "|" .. nbt_key
        if aggregated[key] then
            aggregated[key].count = aggregated[key].count + item.count
        else
            aggregated[key] = {
                name = item.name,
                displayName = item.displayName or item.name,
                count = item.count,
            }
            table.insert(agg_order, key)
        end
    end

    local detail_max_scroll = math.max(0, #agg_order - remaining_h)
    if scroll > detail_max_scroll then scroll = detail_max_scroll end
    hits.detail_max_scroll = detail_max_scroll

    for vi = 1, remaining_h do
        local idx = scroll + vi
        local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
        draw.fill(buf, y, x + w, rbg)
        if idx <= #agg_order then
            local agg = aggregated[agg_order[idx]]
            local display = agg.displayName
            if #display > w - 10 then display = display:sub(1, w - 12) .. ".." end
            draw.put(buf, x + 2, y, display, theme.fg, rbg)
            draw.put(buf, x + w - 6, y, string.format("x%d", agg.count), theme.fg_dim, rbg)
        end
        y = y + 1
    end
end

-- ========================================
-- Render: Equip Tab
-- ========================================
local function render_barrel_picker(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ld = ctx.state.loadouts

    -- Header
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "SELECT BARREL FOR:", theme.fg_dim, theme.surface)
    y = y + 1
    draw.fill(buf, y, x + w, theme.surface)
    local im_display = assigning_im or ""
    if #im_display > w - 4 then im_display = ".." .. im_display:sub(-(w - 6)) end
    draw.put(buf, x + 2, y, im_display, theme.accent, theme.surface)
    draw.button(buf, x + w - 8, y, 7, 1, "CANCEL", theme.danger, theme.btn_text, true)
    hits.barrel_cancel = {x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1}
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- List available barrels
    local barrels = {}
    if ld.list_available_barrels then barrels = ld.list_available_barrels() end
    hits.barrel_pick_rows = {}

    if #barrels == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "No unassigned barrels found", theme.fg_dim, theme.surface)
        y = y + 1
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "on the wired network", theme.fg_dim, theme.surface)
    else
        local area_h = h - (y - ctx.content_y) - 1
        for vi = 1, area_h do
            local idx = scroll + vi
            local rbg = (vi % 2 == 0) and theme.surface2 or theme.surface
            draw.fill(buf, y, x + w, rbg)
            if idx <= #barrels then
                local bname = barrels[idx]
                local display = bname
                if #display > w - 4 then display = ".." .. display:sub(-(w - 6)) end
                draw.put(buf, x + 2, y, display, theme.fg, rbg)
                draw.put(buf, x + w - 3, y, "\16", theme.accent, rbg)
                table.insert(hits.barrel_pick_rows, {
                    x = 1, y = y - hits.oy + 1, w = w, h = 1,
                    barrel_name = bname,
                })
            end
            y = y + 1
        end

        -- Scroll info
        draw.fill(buf, y, x + w, theme.surface2)
        draw.center(buf, string.format("%d barrel(s) available", #barrels), y, x + w, theme.fg_dim, theme.surface2)
    end
end

local function render_equip_tab(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local ld = ctx.state.loadouts

    -- Barrel picker mode
    if assigning_im then
        render_barrel_picker(ctx, buf, x, y, w, h)
        return
    end

    -- IM selector
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "INVENTORY MANAGER", theme.accent, theme.surface)
    y = y + 1

    local managers = {}
    if ld.list_managers then managers = ld.list_managers() end
    hits.im_rows = {}
    hits.barrel_btns = {}

    if #managers == 0 then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "No Inventory Managers detected", theme.fg_dim, theme.surface)
        y = y + 2
    else
        for i, mgr in ipairs(managers) do
            local rbg = (selected_im == mgr.name) and theme.highlight or theme.surface
            local rfg = (selected_im == mgr.name) and theme.bg or theme.fg
            draw.fill(buf, y, x + w, rbg)
            if selected_im == mgr.name then
                draw.put(buf, x + 1, y, "\16", theme.accent, rbg)
            end
            -- Owner
            local owner_display = mgr.owner or "?"
            if #owner_display > 16 then owner_display = owner_display:sub(1, 14) .. ".." end
            draw.put(buf, x + 3, y, owner_display, rfg, rbg)
            -- Peripheral name
            local pname = mgr.name
            if #pname > 20 then pname = ".." .. pname:sub(-18) end
            draw.put(buf, x + 22, y, pname, (selected_im == mgr.name) and theme.bg or theme.fg_dim, rbg)
            -- Status
            local status_col = mgr.online and theme.success or theme.danger
            draw.put(buf, x + w - 7, y, mgr.online and "ONLINE" or "OFFLINE",
                status_col, rbg)
            table.insert(hits.im_rows, {
                x = 1, y = y - hits.oy + 1, w = w, h = 1,
                name = mgr.name,
            })
            y = y + 1

            -- Buffer barrel row (indented under the IM)
            local bbg = theme.surface2
            draw.fill(buf, y, x + w, bbg)
            draw.put(buf, x + 3, y, "Barrel:", theme.fg_dim, bbg)
            if mgr.buffer then
                local bname = mgr.buffer
                if #bname > 24 then bname = ".." .. bname:sub(-22) end
                draw.put(buf, x + 11, y, bname, theme.fg, bbg)
                draw.button(buf, x + w - 7, y, 6, 1, "CLEAR", theme.danger, theme.btn_text, true)
                hits.barrel_btns[mgr.name] = {
                    x = w - 7 + 1, y = y - hits.oy + 1, w = 6, h = 1,
                    im_name = mgr.name, action = "clear",
                }
            else
                draw.put(buf, x + 11, y, "(none)", theme.fg_dim, bbg)
                draw.button(buf, x + w - 8, y, 7, 1, "ASSIGN", theme.accent, theme.btn_text, true)
                hits.barrel_btns[mgr.name] = {
                    x = w - 8 + 1, y = y - hits.oy + 1, w = 7, h = 1,
                    im_name = mgr.name, action = "assign",
                }
            end
            y = y + 1
        end
        y = y + 1
    end

    -- Separator
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Loadout selector
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "LOADOUT", theme.accent, theme.surface)

    -- Show selected loadout or prompt
    if selected_loadout and ld.saved[selected_loadout] then
        draw.put(buf, x + 10, y, selected_loadout, theme.fg, theme.surface)
    else
        draw.put(buf, x + 10, y, "(select from Loadouts tab)", theme.fg_dim, theme.surface)
    end
    y = y + 2

    -- Action buttons
    draw.fill(buf, y, x + w, theme.surface)
    local has_im = selected_im ~= nil
    local has_barrel = has_im and ld.buffer_barrels[selected_im] ~= nil
    local has_loadout = selected_loadout ~= nil and ld.saved[selected_loadout] ~= nil
    local can_strip = has_im and has_barrel
    local can_equip = can_strip and has_loadout

    draw.button(buf, x + 2, y, 14, 1, "STRIP GEAR", can_strip and theme.warning or theme.surface2,
        can_strip and theme.btn_text or theme.fg_dim, can_strip)
    hits.strip_btn = {x = 3, y = y - hits.oy + 1, w = 14, h = 1}

    draw.button(buf, x + 18, y, 14, 1, "EQUIP LOADOUT", can_equip and theme.success or theme.surface2,
        can_equip and theme.btn_text or theme.fg_dim, can_equip)
    hits.equip_btn = {x = 19, y = y - hits.oy + 1, w = 14, h = 1}
    y = y + 2

    -- Status info
    draw.fill(buf, y, x + w, theme.surface)
    if not has_im then
        draw.put(buf, x + 2, y, "\7 Select an Inventory Manager above", theme.fg_dim, theme.surface)
    elseif not has_barrel then
        draw.put(buf, x + 2, y, "\7 Assign a buffer barrel first", theme.warning, theme.surface)
    elseif not has_loadout then
        draw.put(buf, x + 2, y, "\7 Select a loadout from tab 1", theme.fg_dim, theme.surface)
    else
        draw.put(buf, x + 2, y, "\7 Ready to equip", theme.success, theme.surface)
    end
end

-- ========================================
-- Main Render
-- ========================================
function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme
    local ld = ctx.state.loadouts

    hits = {}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Header (4 rows)
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.loadouts
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data and icon_lib then icon_lib.draw(buf, icon_data, x + 2, y) end

    local sx = x + 11
    draw.put(buf, sx, y, "LOADOUTS", theme.accent, theme.surface2)

    -- Manager count
    local mgr_count = 0
    for _ in pairs(ld.managers) do mgr_count = mgr_count + 1 end
    draw.put(buf, sx, y + 1,
        string.format("Managers: %d", mgr_count),
        mgr_count > 0 and theme.success or theme.danger, theme.surface2)

    -- Loadout count
    local lo_count = 0
    for _ in pairs(ld.saved) do lo_count = lo_count + 1 end
    draw.put(buf, sx, y + 2,
        string.format("Saved loadouts: %d", lo_count),
        theme.fg_dim, theme.surface2)

    -- Selected loadout
    if selected_loadout then
        draw.put(buf, sx, y + 3,
            string.format("Selected: %s", selected_loadout),
            theme.fg_dim, theme.surface2)
    end

    y = y + 4

    -- Tab bar
    draw.fill(buf, y, x + w, theme.surface)
    local tab_labels = {"LOADOUTS", "DETAIL", "EQUIP"}
    local tw = math.floor(w / TAB_COUNT)
    hits.tabs = {}
    for ti = 1, TAB_COUNT do
        local tx = x + (ti - 1) * tw
        local sel = (ti == tab)
        local tbg = sel and theme.accent or theme.surface
        local tfg = sel and theme.bg or theme.fg_dim
        buf.setCursorPos(tx, y)
        buf.setBackgroundColor(tbg)
        buf.setTextColor(tfg)
        buf.write(ctx.utils.pad_center(tab_labels[ti], tw))
        hits.tabs[ti] = {x = tx - hits.ox + 1, y = y - hits.oy + 1, w = tw, h = 1}
    end
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Content
    local content_h = h - (y - ctx.content_y)
    if tab == 1 then
        render_loadouts_tab(ctx, buf, x, y, w, content_h)
    elseif tab == 2 then
        render_detail_tab(ctx, buf, x, y, w, content_h)
    elseif tab == 3 then
        render_equip_tab(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local ld = ctx.state.loadouts
    local draw = ctx.draw
    local utils = ctx.utils

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3] - 1, ev[4]

            -- Tab clicks
            local tab_clicked = false
            for ti, area in ipairs(hits.tabs or {}) do
                if draw.hit_test(area, tx, ty) then
                    if ti ~= tab then
                        tab = ti
                        scroll = 0
                    end
                    tab_clicked = true
                    break
                end
            end

            if not tab_clicked then
                if tab == 1 then
                    -- NEW button
                    if hits.new_btn and draw.hit_test(hits.new_btn, tx, ty) then
                        -- Pick an IM first
                        local managers = ld.list_managers and ld.list_managers() or {}
                        if #managers == 0 then
                            utils.set_status(ctx.state, "No Inventory Managers found", colors.red, 3)
                        else
                            local name = utils.pc_input("NEW LOADOUT", "Enter loadout name:")
                            if name and name ~= "" then
                                if ld.saved[name] then
                                    utils.set_status(ctx.state, "Name already exists", colors.red, 3)
                                else
                                    -- Use nearest player's IM, fall back to selected or first
                                    local im_name = (ld.find_best_im and ld.find_best_im())
                                        or selected_im or managers[1].name
                                    local data, err = ld.snapshot(im_name)
                                    if data then
                                        ld.save_loadout(name, data)
                                        selected_loadout = name
                                        utils.set_status(ctx.state,
                                            string.format("Loadout '%s' saved", name), colors.lime, 3)
                                    else
                                        utils.set_status(ctx.state,
                                            "Snapshot failed: " .. (err or "unknown"), colors.red, 3)
                                    end
                                end
                            end
                        end
                    end

                    -- Loadout row clicks
                    local row_handled = false
                    for _, row in ipairs(hits.loadout_rows or {}) do
                        -- Delete button
                        if row.del_btn and draw.hit_test(row.del_btn, tx, ty) then
                            if ld.delete_loadout then
                                ld.delete_loadout(row.name)
                                if selected_loadout == row.name then
                                    selected_loadout = nil
                                end
                            end
                            row_handled = true
                            break
                        end
                        -- Row select -> detail tab
                        if draw.hit_test(row, tx, ty) then
                            selected_loadout = row.name
                            tab = 2
                            scroll = 0
                            row_handled = true
                            break
                        end
                    end

                    -- Scroll
                    if not row_handled then
                        if hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                            if scroll > 0 then scroll = scroll - 1 end
                        elseif hits.scroll_down and draw.hit_test(hits.scroll_down, tx, ty) then
                            if scroll < (hits.max_scroll or 0) then scroll = scroll + 1 end
                        end
                    end

                elseif tab == 2 then
                    -- Rename
                    if hits.detail_rename and draw.hit_test(hits.detail_rename, tx, ty) then
                        if selected_loadout then
                            local new_name = utils.pc_input("RENAME", "New name:", selected_loadout)
                            if new_name and new_name ~= "" and new_name ~= selected_loadout then
                                if ld.rename_loadout and ld.rename_loadout(selected_loadout, new_name) then
                                    selected_loadout = new_name
                                    utils.set_status(ctx.state, "Renamed to " .. new_name, colors.lime, 3)
                                else
                                    utils.set_status(ctx.state, "Rename failed", colors.red, 3)
                                end
                            end
                        end
                    end

                    -- Re-snap
                    if hits.detail_resnap and draw.hit_test(hits.detail_resnap, tx, ty) then
                        if selected_loadout then
                            local managers = ld.list_managers and ld.list_managers() or {}
                            if #managers == 0 then
                                utils.set_status(ctx.state, "No Inventory Managers", colors.red, 3)
                            else
                                local im_name = (ld.find_best_im and ld.find_best_im())
                                    or selected_im or managers[1].name
                                local data, err = ld.snapshot(im_name)
                                if data then
                                    ld.save_loadout(selected_loadout, data)
                                    utils.set_status(ctx.state,
                                        string.format("Re-snapped '%s'", selected_loadout), colors.lime, 3)
                                else
                                    utils.set_status(ctx.state,
                                        "Snapshot failed: " .. (err or "unknown"), colors.red, 3)
                                end
                            end
                        end
                    end

                elseif tab == 3 then
                    if assigning_im then
                        -- Barrel picker mode
                        local handled = false
                        -- Cancel button
                        if hits.barrel_cancel and draw.hit_test(hits.barrel_cancel, tx, ty) then
                            assigning_im = nil
                            scroll = 0
                            handled = true
                        end
                        -- Barrel row clicks
                        if not handled then
                            for _, row in ipairs(hits.barrel_pick_rows or {}) do
                                if draw.hit_test(row, tx, ty) then
                                    if ld.assign_buffer then
                                        ld.assign_buffer(assigning_im, row.barrel_name)
                                    end
                                    assigning_im = nil
                                    scroll = 0
                                    break
                                end
                            end
                        end
                    else
                        -- IM selection
                        for _, row in ipairs(hits.im_rows or {}) do
                            if draw.hit_test(row, tx, ty) then
                                selected_im = row.name
                                break
                            end
                        end

                        -- Barrel assign/clear buttons
                        for im_name, btn in pairs(hits.barrel_btns or {}) do
                            if draw.hit_test(btn, tx, ty) then
                                if btn.action == "assign" then
                                    assigning_im = btn.im_name
                                    scroll = 0
                                elseif btn.action == "clear" then
                                    if ld.clear_buffer then
                                        ld.clear_buffer(btn.im_name)
                                    end
                                end
                                break
                            end
                        end

                        -- Strip button
                        if hits.strip_btn and draw.hit_test(hits.strip_btn, tx, ty) then
                            if selected_im and ld.strip then
                                ld.strip(selected_im)
                            end
                        end

                        -- Equip button
                        if hits.equip_btn and draw.hit_test(hits.equip_btn, tx, ty) then
                            if selected_im and selected_loadout and ld.equip then
                                ld.equip(selected_im, selected_loadout)
                            end
                        end
                    end
                end
            end

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if tab == 1 then
                scroll = math.max(0, math.min(hits.max_scroll or 0, scroll + dir))
            elseif tab == 2 then
                scroll = math.max(0, math.min(hits.detail_max_scroll or 0, scroll + dir))
            end

        elseif ev[1] == "key" then
            if ev[2] == keys.tab then
                tab = (tab % TAB_COUNT) + 1
                scroll = 0
            elseif tab == 1 then
                if ev[2] == keys.up and scroll > 0 then
                    scroll = scroll - 1
                elseif ev[2] == keys.down and scroll < (hits.max_scroll or 0) then
                    scroll = scroll + 1
                end
            elseif tab == 2 then
                if ev[2] == keys.up and scroll > 0 then
                    scroll = scroll - 1
                elseif ev[2] == keys.down and scroll < (hits.detail_max_scroll or 0) then
                    scroll = scroll + 1
                end
            end
        end
    end
end

return app
