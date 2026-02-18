-- =============================================
-- WRAITH OS - NETWORK APP
-- =============================================
-- Network status, clients, WebSocket info.

local app = {
    id = "network",
    name = "Network",
    icon = "network",
    default_w = 42,
    default_h = 22,
    singleton = true,
}

function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local net = ctx.state.network
    local config = ctx.config

    -- Header
    draw.fill(buf, y, x + w, theme.surface2)
    draw.put(buf, x, y, " NETWORK STATUS ", theme.fg, theme.surface2)
    y = y + 2

    -- Modem info
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "MODEM", theme.fg_dim, theme.surface)
    if net.modem_side then
        draw.put(buf, x + 9, y, net.modem_side .. "  ONLINE", theme.success, theme.surface)
    else
        draw.put(buf, x + 9, y, "NOT FOUND", theme.danger, theme.surface)
    end
    y = y + 1

    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "ID", theme.fg_dim, theme.surface)
    draw.put(buf, x + 9, y, "#" .. tostring(os.getComputerID()), theme.accent, theme.surface)
    draw.put(buf, x + 18, y, "LABEL", theme.fg_dim, theme.surface)
    draw.put(buf, x + 24, y, os.getComputerLabel() or "unlabeled", theme.fg, theme.surface)
    y = y + 2

    -- WebSocket
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1
    draw.fill(buf, y, x + w, theme.surface)
    draw.put(buf, x + 1, y, "WEBSOCKET", theme.fg_dim, theme.surface)
    if not config.network.websocket.enabled then
        draw.put(buf, x + 12, y, "DISABLED", theme.fg_dark, theme.surface)
    elseif net.ws_connected then
        draw.put(buf, x + 12, y, "CONNECTED", theme.success, theme.surface)
    else
        draw.put(buf, x + 12, y, "DISCONNECTED", theme.danger, theme.surface)
    end
    y = y + 1

    if config.network.websocket.url then
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "URL", theme.fg_dim, theme.surface)
        local url = config.network.websocket.url
        if #url > w - 6 then url = url:sub(1, w - 8) .. ".." end
        draw.put(buf, x + 5, y, url, theme.fg_dim, theme.surface)
    end
    y = y + 2

    -- Clients
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1
    draw.fill(buf, y, x + w, theme.surface)
    local cc = utils.table_size(net.connected_clients)
    draw.put(buf, x + 1, y, "CLIENTS", theme.fg_dim, theme.surface)
    draw.put(buf, x + 9, y, tostring(cc), cc > 0 and theme.accent or theme.fg_dim, theme.surface)
    y = y + 1

    for id, c in pairs(net.connected_clients) do
        if y >= ctx.content_y + h - 4 then break end
        draw.fill(buf, y, x + w, theme.surface)
        local age = math.floor(os.clock() - c.last_seen)
        draw.put(buf, x + 3, y, string.format("#%-4d  %s ago", id, utils.format_uptime(age)), theme.fg_dim, theme.surface)
        y = y + 1
    end
    y = y + 1

    -- Protocols
    if y < ctx.content_y + h - 3 then
        draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
        y = y + 1
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 1, y, "PROTOCOLS", theme.fg_dim, theme.surface)
        y = y + 1
        for name, proto in pairs(config.network.protocols) do
            if y >= ctx.content_y + h - 1 then break end
            draw.fill(buf, y, x + w, theme.surface)
            draw.put(buf, x + 3, y, utils.pad_right(name, 16), theme.fg_dim, theme.surface)
            draw.put(buf, x + 19, y, proto, theme.accent, theme.surface)
            y = y + 1
        end
    end
end

function app.main(ctx)
    -- Network app is mostly display-only, just idle
    while true do
        coroutine.yield("timer")
    end
end

return app
