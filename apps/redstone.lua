-- =============================================
-- WRAITH OS - REDSTONE APP
-- =============================================
-- Toggle switches for redstone outputs + armour sets.

local app = {
    id = "redstone",
    name = "Redstone",
    icon = "redstone",
    default_w = 40,
    default_h = 24,
    singleton = true,
}

function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x, y, " REDSTONE CONTROL ", theme.fg, theme.surface2)
    y = y + 1

    local outputs = {}
    if ctx.state.redstone.get_all_outputs then
        outputs = ctx.state.redstone.get_all_outputs()
    end

    if #outputs == 0 then
        draw.fill(buf, y + 1, x + w, theme.surface)
        draw.put(buf, x + 2, y + 1, "No redstone outputs configured", theme.fg_dim, theme.surface)
        draw.fill(buf, y + 2, x + w, theme.surface)
        draw.put(buf, x + 2, y + 2, "Edit config.lua to add outputs", theme.fg_dark, theme.surface)
        y = y + 4
    else
        local bw = math.min(w - 4, 30)
        local bh = h >= 20 and 3 or 2
        local bxo = x + math.floor((w - bw) / 2)

        for _, o in ipairs(outputs) do
            if y + bh + 2 > ctx.content_y + h - 6 then break end

            draw.fill(buf, y, x + w, theme.surface)
            y = y + 1
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 1, y, o.label, theme.fg_dim, theme.surface)
            draw.put(buf, x + w - #o.side - 1, y, o.side, theme.fg_dark, theme.surface)
            y = y + 1

            local obg = o.on and theme.success or theme.danger
            local olbl = o.on and " ON " or " OFF "
            draw.button(buf, bxo, y, bw, bh, o.label .. "  " .. olbl, obg, theme.btn_text, true)
            y = y + bh
        end
    end

    -- Armour sets section
    y = y + 1
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x, y, " ARMOUR SETS ", theme.fg, theme.surface2)
    y = y + 1

    local sets = {}
    if ctx.state.storage.get_armour_sets then
        sets = ctx.state.storage.get_armour_sets()
    end

    if #sets == 0 then
        draw.fill(buf, y + 1, x + w, theme.surface)
        draw.put(buf, x + 2, y + 1, "No armour sets configured", theme.fg_dim, theme.surface)
        y = y + 3
    else
        local aw = math.floor((w - 6) / math.max(1, #sets))
        if aw < 10 then aw = 10 end
        local ah = h >= 20 and 3 or 2
        local ax = x + 1
        draw.fill(buf, y, x + w, theme.surface)
        y = y + 1
        for _, s in ipairs(sets) do
            if ax + aw > x + w then break end
            local lbl = s.label .. " (" .. s.piece_count .. "pc)"
            draw.button(buf, ax, y, aw, ah, lbl, theme.accent2, theme.btn_text, true)
            ax = ax + aw + 2
        end
        y = y + ah
    end
end

function app.main(ctx)
    while true do
        local ev = {coroutine.yield()}

        if ev[1] == "mouse_click" then
            local tx, ty = ev[3], ev[4]
            local w = ctx.content_w

            -- Find which button was clicked by checking outputs
            local outputs = {}
            if ctx.state.redstone.get_all_outputs then
                outputs = ctx.state.redstone.get_all_outputs()
            end

            local bw = math.min(w - 4, 30)
            local bh = ctx.content_h >= 20 and 3 or 2
            local bxo = math.floor((w - bw) / 2) + 1

            local btn_y = 3  -- starting y for first button
            for _, o in ipairs(outputs) do
                if ty >= btn_y and ty < btn_y + bh then
                    if tx >= bxo and tx < bxo + bw then
                        if ctx.state.redstone.toggle_output then
                            ctx.state.redstone.toggle_output(o.name)
                        end
                        break
                    end
                end
                btn_y = btn_y + bh + 2
            end

            -- Check armour set buttons
            local sets = ctx.state.storage.get_armour_sets and ctx.state.storage.get_armour_sets() or {}
            if #sets > 0 then
                local aw = math.floor((w - 6) / math.max(1, #sets))
                if aw < 10 then aw = 10 end
                local ah = ctx.content_h >= 20 and 3 or 2
                -- armour buttons y is after all redstone buttons + header
                local armour_y = btn_y + 3
                local ax = 2
                for _, s in ipairs(sets) do
                    if ty >= armour_y and ty < armour_y + ah and
                       tx >= ax and tx < ax + aw then
                        if ctx.state.storage.equip_armour then
                            ctx.state.storage.equip_armour(s.name)
                        end
                        break
                    end
                    ax = ax + aw + 2
                end
            end
        end
    end
end

return app
