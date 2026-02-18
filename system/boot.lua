-- =============================================
-- WRAITH OS - BOOT SEQUENCE
-- =============================================

local root = _G.WRAITH_ROOT or "."

-- =============================================
-- Boot Splash (on terminal)
-- =============================================

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)

-- Animated Wraith logo using blit for colored block text
local logo_data = {
    -- {text_pattern, fg_color_char}   (space=' ', block='#')
    {" #   # ###   ##  # ##### #  #",  "9"},
    {" #   # #  # #  # #   #   #  #",  "9"},
    {" # # # ###  ####  #   #   ####",  "3"},
    {" ## ## #  # #  #  #   #   #  #",  "3"},
    {" #   # #  # #  # #    #   #  #",  "0"},
}

print()
for i, entry in ipairs(logo_data) do
    local pattern = entry[1]
    local fc = entry[2]
    local text = ""
    local fg = ""
    local bg = ""
    for c = 1, #pattern do
        local ch = pattern:sub(c, c)
        if ch == "#" then
            text = text .. " "
            fg = fg .. fc
            bg = bg .. fc  -- colored background = solid block
        else
            text = text .. " "
            fg = fg .. "f"
            bg = bg .. "f"  -- black background
        end
    end
    term.setCursorPos(3, i + 1)
    if term.isColor() then
        term.blit(text, fg, bg)
    else
        term.write(pattern)
    end
    sleep(0.05)
end

if term.isColor() then term.setTextColor(colors.gray) end
term.setCursorPos(1, 8)
print("     Desktop Operating System for CC:Tweaked")
print()

-- Progress bar
local pw = 40
local function draw_progress(pct, label)
    local filled = math.floor(pct * pw)
    term.setCursorPos(5, 10)
    if term.isColor() then term.setTextColor(colors.white) end
    term.write(label .. string.rep(" ", 30 - #label))
    term.setCursorPos(5, 11)
    if term.isColor() then term.setTextColor(colors.cyan) end
    term.write("[")
    if term.isColor() then term.setTextColor(colors.lightBlue) end
    term.write(string.rep("\127", filled))
    if term.isColor() then term.setTextColor(colors.gray) end
    term.write(string.rep("\183", math.max(0, pw - filled)))
    if term.isColor() then term.setTextColor(colors.cyan) end
    term.write("] " .. math.floor(pct * 100) .. "%")
end

draw_progress(0, "Initializing...")

local boot_y = 13
local function boot_msg(msg, ok)
    if term.isColor() then
        term.setTextColor(ok and colors.lime or colors.red)
    end
    term.setCursorPos(3, boot_y)
    term.write(string.format("[%s] %s", ok and " OK " or "FAIL", msg))
    boot_y = boot_y + 1
end

-- =============================================
-- Load Libraries
-- =============================================

draw_progress(0.05, "Loading core libraries...")

local function load_mod(path, name)
    local full = root .. "/" .. path
    if not fs.exists(full) then
        boot_msg(name .. " not found: " .. full, false)
        return nil
    end
    local mod = dofile(full)
    boot_msg(name, true)
    return mod
end

-- Phase 1: Core libraries
local utils  = load_mod("lib/utils.lua",    "Utilities")
local config = load_mod("system/config.lua", "Configuration")
local state  = load_mod("system/state.lua",  "Shared State")
local theme  = load_mod("system/theme.lua",  "Theme Engine")
local draw   = load_mod("lib/draw.lua",      "Drawing Primitives")

if not (utils and config and state and theme and draw) then
    boot_msg("FATAL: Core libraries failed", false)
    return
end

_G._wraith = {draw = draw, utils = utils, theme = theme, state = state, config = config}

draw_progress(0.20, "Loading UI components...")

-- Phase 2: Widgets and icons
local widget   = load_mod("lib/widget.lua",   "Widget Library")
local icon_lib = load_mod("lib/icon.lua",     "Icon Engine")

draw_progress(0.35, "Loading system components...")

-- Phase 3: System components
local wm          = load_mod("system/wm.lua",          "Window Manager")
local desktop     = load_mod("system/desktop.lua",      "Desktop")
local taskbar_mod = load_mod("system/taskbar.lua",      "Taskbar")
local event_mod   = load_mod("system/event.lua",        "Event Router")
local compositor  = load_mod("system/compositor.lua",   "Compositor")
local kernel      = load_mod("system/kernel.lua",       "Kernel")

if not (wm and desktop and taskbar_mod and event_mod and compositor and kernel) then
    boot_msg("FATAL: System components failed", false)
    return
end

-- =============================================
-- Detect Peripherals
-- =============================================

draw_progress(0.50, "Detecting peripherals...")

local mon = peripheral.find("monitor")
if not mon then
    boot_msg("No monitor found - waiting...", false)
    while not mon do
        sleep(2)
        mon = peripheral.find("monitor")
    end
end

mon.setTextScale(config.monitor.text_scale)
state.monitor = mon
state.monitor_name = peripheral.getName(mon)
state.mon_w, state.mon_h = mon.getSize()

theme.apply_palette(mon)
boot_msg("Monitor: " .. state.monitor_name .. " (" .. state.mon_w .. "x" .. state.mon_h .. ")", true)

local modem_side = utils.find_modem()
if modem_side then
    rednet.open(modem_side)
    state.network.modem_side = modem_side
    boot_msg("Modem: " .. modem_side, true)
else
    boot_msg("No modem found", false)
end

-- =============================================
-- Initialize System
-- =============================================

draw_progress(0.65, "Initializing system...")

wm.init(state, config, theme, draw)
desktop.init(state, config, theme, draw, icon_lib)
taskbar_mod.init(state, config, theme, draw, utils)
event_mod.init(state, wm, desktop, taskbar_mod)
compositor.init(state, config, theme, draw, wm, desktop, taskbar_mod)
compositor.setup(mon)

kernel.init({
    state = state, config = config, theme = theme,
    draw = draw, utils = utils, wm = wm,
    desktop = desktop, taskbar = taskbar_mod,
    compositor = compositor, event = event_mod,
})

boot_msg("System initialized", true)

-- =============================================
-- Register Apps
-- =============================================

draw_progress(0.75, "Loading apps...")

local function register_app(path, name)
    local full = root .. "/" .. path
    if fs.exists(full) then
        local ok, app_def = pcall(dofile, full)
        if ok and app_def and app_def.id then
            state.app_registry[app_def.id] = app_def
            table.insert(state.app_order, app_def.id)
            boot_msg("App: " .. (app_def.name or app_def.id), true)
            return true
        elseif not ok then
            boot_msg("App: " .. name .. " ERROR: " .. tostring(app_def):sub(1, 40), false)
            return false
        end
    end
    boot_msg("App: " .. name .. " (not found)", false)
    return false
end

register_app("apps/storage.lua",  "Storage")
register_app("apps/smelting.lua", "Smelting")
register_app("apps/redstone.lua", "Redstone")
register_app("apps/network.lua",  "Network")
register_app("apps/settings.lua", "Settings")
register_app("apps/youcube.lua",  "YouCube")
register_app("apps/analytics.lua", "Analytics")
register_app("apps/mastermine.lua", "MasterMine")
register_app("apps/terminal.lua", "Terminal")
register_app("apps/ar.lua",       "AR Goggles")
register_app("apps/projects.lua", "Projects")
register_app("apps/lighting.lua", "Lighting")
register_app("apps/loadouts.lua", "Loadouts")
register_app("apps/farms.lua",    "Farms")
register_app("apps/crafting.lua", "Crafting")
register_app("apps/transport.lua", "Transport")

-- =============================================
-- Launch Services
-- =============================================

draw_progress(0.90, "Starting services...")

local function start_service(path, id, name)
    local full = root .. "/" .. path
    if fs.exists(full) then
        local ok, svc = pcall(dofile, full)
        if ok and svc and svc.main then
            kernel.add_service(id, name, svc.main)
            boot_msg("Service: " .. name, true)
            return true
        elseif not ok then
            boot_msg("Service: " .. name .. " LOAD ERROR: " .. tostring(svc):sub(1, 35), false)
            utils.add_notification(state, "SVC LOAD FAIL [" .. name .. "]: " .. tostring(svc), colors.red)
            return false
        end
    end
    boot_msg("Service: " .. name .. " (skipped)", false)
    return false
end

start_service("services/storage_svc.lua",  "storage",  "Storage Engine")
start_service("services/redstone_svc.lua", "redstone", "Redstone Control")
start_service("services/network_svc.lua",  "network",  "Network Manager")
start_service("services/dropper_svc.lua",  "dropper",  "Dropper System")
start_service("services/mastermine_svc.lua", "mastermine", "MasterMine Link")
start_service("services/projects_svc.lua",  "projects",   "Projects Engine")
start_service("services/ar_svc.lua",        "ar",          "AR Goggles")
start_service("services/lighting_svc.lua",  "lighting",    "Lighting Controller")
start_service("services/loadouts_svc.lua", "loadouts",    "Loadouts Manager")
start_service("services/farms_svc.lua",   "farms",       "Farms Manager")
start_service("services/crafting_svc.lua", "crafting",   "Crafting Engine")
start_service("services/transport_svc.lua", "transport",  "Transport Manager")
start_service("services/updater_svc.lua",  "updater",    "Client Updater")

-- =============================================
-- Boot Complete
-- =============================================

draw_progress(1.0, "Boot complete!")
sleep(0.3)

term.setCursorPos(1, boot_y + 1)
if term.isColor() then term.setTextColor(colors.cyan) end
print("  ================================================")
print(string.format("    Wraith OS v%s | Computer #%d", config.version, os.getComputerID()))
print("  ================================================")
print()
if term.isColor() then term.setTextColor(colors.lightGray) end
print("  Desktop is live on the monitor.")
print("  Terminal is free for commands.")
print()

-- Add boot notification
utils.add_notification(state, "Wraith OS booted successfully", theme.success)

-- Run the kernel (blocks forever until shutdown)
kernel.run()

-- Shutdown
if term.isColor() then term.setTextColor(colors.cyan) end
print("  Wraith OS shutdown complete.")
