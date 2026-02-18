-- =============================================
-- WRAITH OS - PROJECTS APP
-- =============================================
-- Block shopping lists with storage coverage.

local app = {
    id = "projects",
    name = "Projects",
    icon = "projects",
    default_w = 46,
    default_h = 26,
    singleton = true,
}

local tab = 1       -- 1=list, 2=details
local scroll = 0
local sel_proj = 1   -- selected project index
local sel_item = 1   -- selected item index in detail view
local hits = {}

-- ========================================
-- Render: Tab bar
-- ========================================
local function draw_tabs(buf, x, y, w, draw, theme)
    draw.fill(buf, y, x + w, theme.surface2)
    local tabs = {"PROJECTS", "DETAILS"}
    local tx = x + 1
    for i, label in ipairs(tabs) do
        local active = (tab == i)
        local fg = active and theme.accent or theme.fg_dim
        local bg = active and theme.surface or theme.surface2
        draw.put(buf, tx, y, " " .. label .. " ", fg, bg)
        local tw = #label + 2
        hits["tab_" .. i] = {x = tx - hits.ox, y = y - hits.oy, w = tw, h = 1}
        tx = tx + tw + 1
    end
end

-- ========================================
-- Render: Project List (Tab 1)
-- ========================================
local function render_project_list(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local proj = ctx.state.projects
    local list = proj.list or {}

    -- Stats line
    local active_name = proj.active_idx and proj.list[proj.active_idx] and proj.list[proj.active_idx].name or "none"
    draw.put(buf, x + 1, y, string.format("%d projects | Active: %s", #list, active_name), theme.fg_dim, theme.surface)
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Column headers
    draw.put(buf, x + 1, y, "  NAME", theme.fg_dim, theme.surface)
    draw.put(buf, x + w - 12, y, "DONE", theme.fg_dim, theme.surface)
    draw.put(buf, x + w - 5, y, "ACT", theme.fg_dim, theme.surface)
    y = y + 1

    -- Scrollable list
    local list_h = h - 5  -- header + stats + sep + cols + buttons
    local max_scroll = math.max(0, #list - list_h)
    hits.max_scroll = max_scroll
    hits.project_rows = {}

    for i = 1 + scroll, math.min(#list, scroll + list_h) do
        local project = list[i]
        local is_sel = (i == sel_proj)
        local bg = is_sel and theme.accent or theme.surface
        local fg = is_sel and theme.bg or theme.fg

        draw.fill(buf, y, x + w, bg)

        -- Completion %
        local cov = proj.coverage[i] or {}
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
        local pct = total_need > 0 and math.floor(total_have / total_need * 100) or (#project.items > 0 and 100 or 0)
        local pct_col = pct >= 100 and theme.success or (pct >= 50 and theme.warning or theme.danger)
        if is_sel then pct_col = theme.bg end

        -- Name
        local name = project.name
        if #name > w - 18 then name = name:sub(1, w - 21) .. "..." end
        draw.put(buf, x + 1, y, " " .. name, fg, bg)

        -- % done
        draw.put(buf, x + w - 12, y, string.format("%3d%%", pct), pct_col, bg)

        -- Active star
        local is_active = (proj.active_idx == i)
        draw.put(buf, x + w - 4, y, is_active and "[*]" or "[ ]",
            is_active and theme.warning or theme.fg_dim, bg)
        hits["star_" .. i] = {x = (x + w - 4) - hits.ox, y = y - hits.oy, w = 3, h = 1}

        -- Row click area
        table.insert(hits.project_rows, {x = 1 - hits.ox + x, y = y - hits.oy, w = w - 6, h = 1, idx = i})
        y = y + 1
    end

    -- Scroll indicators
    if scroll > 0 then
        draw.put(buf, x + w - 2, y - list_h, "\30", theme.accent, theme.surface)
        hits.scroll_up = {x = (x + w - 2) - hits.ox, y = (y - list_h) - hits.oy, w = 1, h = 1}
    end
    if scroll < max_scroll then
        draw.put(buf, x + w - 2, y - 1, "\31", theme.accent, theme.surface)
        hits.scroll_down = {x = (x + w - 2) - hits.ox, y = (y - 1) - hits.oy, w = 1, h = 1}
    end

    -- Buttons row
    local btn_y = y + (list_h - (#list - scroll)) -- fill to bottom
    btn_y = math.max(y, y)
    -- Use a fixed button row at the bottom
    local by = ctx.content_y + h - 2
    draw.fill(buf, by, x + w, theme.surface2)
    local bx = x + 1
    draw.button(buf, bx, by, 7, 1, "NEW", theme.success, theme.btn_text, true)
    hits.btn_new = {x = bx - hits.ox, y = by - hits.oy, w = 7, h = 1}
    bx = bx + 8
    draw.button(buf, bx, by, 8, 1, "DELETE", theme.danger, theme.btn_text, sel_proj <= #list)
    hits.btn_delete = {x = bx - hits.ox, y = by - hits.oy, w = 8, h = 1}
    bx = bx + 9
    draw.button(buf, bx, by, 8, 1, "RENAME", theme.accent, theme.btn_text, sel_proj <= #list)
    hits.btn_rename = {x = bx - hits.ox, y = by - hits.oy, w = 8, h = 1}
end

-- ========================================
-- Render: Project Details (Tab 2)
-- ========================================
local function render_project_details(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local proj = ctx.state.projects

    if sel_proj < 1 or sel_proj > #proj.list then
        draw.center(buf, "No project selected", y + 4, w, theme.fg_dim, theme.surface)
        draw.center(buf, "Select one in PROJECTS tab", y + 5, w, theme.fg_dim, theme.surface)
        return
    end

    local project = proj.list[sel_proj]
    local cov = proj.coverage[sel_proj] or {}

    -- Project header
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
    local pct = total_need > 0 and math.floor(total_have / total_need * 100) or 0
    local pct_col = pct >= 100 and theme.success or (pct >= 50 and theme.warning or theme.danger)

    draw.put(buf, x + 1, y, project.name, theme.fg, theme.surface)
    draw.put(buf, x + w - 10, y, string.format("%3d%% done", pct), pct_col, theme.surface)
    y = y + 1

    -- Progress bar
    local bar_w = w - 2
    local filled = math.floor(pct / 100 * bar_w)
    buf.setCursorPos(x + 1, y)
    buf.setBackgroundColor(pct_col)
    buf.write(string.rep(" ", math.min(filled, bar_w)))
    buf.setBackgroundColor(theme.border)
    buf.write(string.rep(" ", math.max(0, bar_w - filled)))
    y = y + 1

    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Column headers
    draw.put(buf, x + 1, y, "ITEM", theme.fg_dim, theme.surface)
    draw.put(buf, x + w - 22, y, "HAVE", theme.fg_dim, theme.surface)
    draw.put(buf, x + w - 16, y, "NEED", theme.fg_dim, theme.surface)
    draw.put(buf, x + w - 9, y, " %", theme.fg_dim, theme.surface)
    y = y + 1

    -- Scrollable item list
    local list_h = h - 7  -- header + bar + sep + cols + buttons + margin
    local items = project.items
    local max_scroll = math.max(0, #items - list_h)
    hits.max_scroll = max_scroll
    hits.item_rows = {}

    for i = 1 + scroll, math.min(#items, scroll + list_h) do
        local item = items[i]
        local c = cov[item.name] or {have = 0, need = item.need, pct = 0}
        local is_sel = (i == sel_item)
        local bg = is_sel and theme.accent or theme.surface
        local fg = is_sel and theme.bg or theme.fg

        draw.fill(buf, y, x + w, bg)

        -- Item name (truncated)
        local dname = item.displayName or utils.clean_name(item.name)
        if #dname > w - 26 then dname = dname:sub(1, w - 29) .. "..." end
        draw.put(buf, x + 1, y, dname, fg, bg)

        -- Have / Need / %
        local have_col = is_sel and theme.bg or (c.pct >= 1 and theme.success or (c.pct >= 0.5 and theme.warning or theme.danger))
        draw.put(buf, x + w - 22, y, string.format("%4d", c.have), have_col, bg)
        draw.put(buf, x + w - 16, y, string.format("%4d", c.need), fg, bg)
        local ipct = math.floor(c.pct * 100)
        draw.put(buf, x + w - 9, y, string.format("%3d%%", ipct), have_col, bg)

        -- Status
        local status = c.pct >= 1 and "\4" or ""  -- checkmark or empty
        draw.put(buf, x + w - 3, y, status, theme.success, bg)

        table.insert(hits.item_rows, {x = 1 - hits.ox + x, y = y - hits.oy, w = w - 2, h = 1, idx = i})
        y = y + 1
    end

    -- Scroll indicators
    if scroll > 0 then
        hits.scroll_up = {x = (x + w - 2) - hits.ox, y = (ctx.content_y + 5) - hits.oy, w = 1, h = 1}
    end
    if scroll < max_scroll then
        hits.scroll_down = {x = (x + w - 2) - hits.ox, y = (ctx.content_y + 4 + list_h) - hits.oy, w = 1, h = 1}
    end

    -- Buttons row
    local by = ctx.content_y + h - 2
    draw.fill(buf, by, x + w, theme.surface2)
    local bx = x + 1
    draw.button(buf, bx, by, 9, 1, "ADD ITEM", theme.success, theme.btn_text, true)
    hits.btn_add = {x = bx - hits.ox, y = by - hits.oy, w = 9, h = 1}
    bx = bx + 10
    draw.button(buf, bx, by, 8, 1, "SET QTY", theme.accent, theme.btn_text, sel_item <= #items)
    hits.btn_qty = {x = bx - hits.ox, y = by - hits.oy, w = 8, h = 1}
    bx = bx + 9
    draw.button(buf, bx, by, 8, 1, "REMOVE", theme.danger, theme.btn_text, sel_item <= #items)
    hits.btn_remove = {x = bx - hits.ox, y = by - hits.oy, w = 8, h = 1}
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

    hits = {}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Header
    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.projects
    for r = 0, 3 do draw.fill(buf, y + r, x + w, theme.surface2) end
    if icon_data then icon_lib.draw(buf, icon_data, x + 1, y) end
    draw.put(buf, x + 9, y, "PROJECTS", theme.fg, theme.surface2)
    draw.put(buf, x + 9, y + 1, "Block shopping lists", theme.fg_dim, theme.surface2)
    y = y + 4

    -- Tab bar
    draw_tabs(buf, x, y, w, draw, theme)
    y = y + 1
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Content
    local content_h = h - 6  -- header(4) + tabs(1) + sep(1)
    if tab == 1 then
        render_project_list(ctx, buf, x, y, w, content_h)
    else
        render_project_details(ctx, buf, x, y, w, content_h)
    end
end

-- ========================================
-- Event Handler
-- ========================================
function app.main(ctx)
    local proj = ctx.state.projects
    local utils = ctx.utils
    local draw = ctx.draw
    local keys = keys

    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3] - 1, ev[4]

            -- Tab clicks
            for i = 1, 2 do
                if hits["tab_" .. i] and draw.hit_test(hits["tab_" .. i], tx, ty) then
                    tab = i
                    scroll = 0
                end
            end

            -- Scroll
            if hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                if scroll > 0 then scroll = scroll - 1 end
            elseif hits.scroll_down and draw.hit_test(hits.scroll_down, tx, ty) then
                if scroll < (hits.max_scroll or 0) then scroll = scroll + 1 end
            end

            if tab == 1 then
                -- Project list interactions
                for _, row in ipairs(hits.project_rows or {}) do
                    if draw.hit_test(row, tx, ty) then
                        sel_proj = row.idx
                    end
                end

                -- Star toggles (set active)
                for i = 1, #(proj.list or {}) do
                    local star = hits["star_" .. i]
                    if star and draw.hit_test(star, tx, ty) then
                        if proj.active_idx == i then
                            if proj.set_active then proj.set_active(nil) end
                        else
                            if proj.set_active then proj.set_active(i) end
                        end
                    end
                end

                -- NEW button
                if hits.btn_new and draw.hit_test(hits.btn_new, tx, ty) then
                    local result = utils.pc_input("NEW PROJECT", "Enter project name:")
                    if result and #result > 0 and proj.create then
                        local idx = proj.create(result)
                        sel_proj = idx
                        tab = 2
                        scroll = 0
                    end
                end

                -- DELETE button
                if hits.btn_delete and draw.hit_test(hits.btn_delete, tx, ty) then
                    if proj.list[sel_proj] and proj.delete then
                        proj.delete(sel_proj)
                        if sel_proj > #proj.list then sel_proj = #proj.list end
                        if sel_proj < 1 then sel_proj = 1 end
                    end
                end

                -- RENAME button
                if hits.btn_rename and draw.hit_test(hits.btn_rename, tx, ty) then
                    if proj.list[sel_proj] and proj.rename then
                        local result = utils.pc_input("RENAME PROJECT", "New name:", proj.list[sel_proj].name)
                        if result and #result > 0 then
                            proj.rename(sel_proj, result)
                        end
                    end
                end

            elseif tab == 2 then
                -- Detail view interactions
                for _, row in ipairs(hits.item_rows or {}) do
                    if draw.hit_test(row, tx, ty) then
                        sel_item = row.idx
                    end
                end

                -- ADD ITEM button
                if hits.btn_add and draw.hit_test(hits.btn_add, tx, ty) then
                    if proj.list[sel_proj] and proj.add_item then
                        local query = utils.pc_input("ADD ITEM", "Type item name to search:")
                        if query and #query > 0 then
                            -- Fuzzy match against storage items
                            local best_match = nil
                            local best_display = nil
                            local q_lower = query:lower()
                            for _, item in ipairs(ctx.state.storage.items or {}) do
                                local dn = (item.displayName or ""):lower()
                                local n = (item.name or ""):lower()
                                if dn:find(q_lower, 1, true) or n:find(q_lower, 1, true) then
                                    best_match = item.name
                                    best_display = item.displayName
                                    break
                                end
                            end
                            if not best_match then
                                -- Use raw input as item name
                                best_match = query
                                best_display = utils.clean_name(query)
                            end
                            local qty_str = utils.pc_input("QUANTITY", "How many " .. best_display .. "?", "64")
                            local qty = tonumber(qty_str)
                            if qty and qty > 0 then
                                proj.add_item(sel_proj, best_match, best_display, qty)
                            end
                        end
                    end
                end

                -- SET QTY button
                if hits.btn_qty and draw.hit_test(hits.btn_qty, tx, ty) then
                    local project = proj.list[sel_proj]
                    if project and project.items[sel_item] and proj.set_item_count then
                        local item = project.items[sel_item]
                        local result = utils.pc_input("SET QUANTITY", item.displayName .. " - new count:", tostring(item.need))
                        local qty = tonumber(result)
                        if qty and qty > 0 then
                            proj.set_item_count(sel_proj, sel_item, qty)
                        end
                    end
                end

                -- REMOVE button
                if hits.btn_remove and draw.hit_test(hits.btn_remove, tx, ty) then
                    local project = proj.list[sel_proj]
                    if project and project.items[sel_item] and proj.remove_item then
                        proj.remove_item(sel_proj, sel_item)
                        if sel_item > #project.items then sel_item = #project.items end
                        if sel_item < 1 then sel_item = 1 end
                    end
                end
            end

        elseif ev[1] == "mouse_scroll" then
            local dir = ev[2]
            if dir == 1 and scroll < (hits.max_scroll or 0) then
                scroll = scroll + 1
            elseif dir == -1 and scroll > 0 then
                scroll = scroll - 1
            end

        elseif ev[1] == "key" then
            local max_s = hits.max_scroll or 0
            if ev[2] == keys.up then
                if tab == 1 and sel_proj > 1 then
                    sel_proj = sel_proj - 1
                    if sel_proj <= scroll then scroll = sel_proj - 1 end
                elseif tab == 2 and sel_item > 1 then
                    sel_item = sel_item - 1
                    if sel_item <= scroll then scroll = sel_item - 1 end
                end
            elseif ev[2] == keys.down then
                if tab == 1 and sel_proj < #(proj.list or {}) then
                    sel_proj = sel_proj + 1
                elseif tab == 2 then
                    local project = proj.list[sel_proj]
                    if project and sel_item < #project.items then
                        sel_item = sel_item + 1
                    end
                end
            elseif ev[2] == keys.tab then
                tab = tab == 1 and 2 or 1
                scroll = 0
            elseif ev[2] == keys.enter then
                if tab == 1 then
                    tab = 2
                    scroll = 0
                    sel_item = 1
                end
            end
        end
    end
end

return app
