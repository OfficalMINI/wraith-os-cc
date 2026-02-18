-- =============================================
--  _    _ ____  ____ _ ___ _  _
--  |    | |__/  |__| |  |  |__|
--  |_/\_| |  \  |  | |  |  |  |
--
--  W R A I T H   O S
--  Desktop Operating System for CC:Tweaked
-- =============================================

os.setComputerLabel("Wraith")

local base = fs.getDir(shell.getRunningProgram())
if base == "" then base = "." end

_G.WRAITH_ROOT = base

-- =============================================
-- Top-level error handler: catch any crash and reboot
-- =============================================
local CRASH_LOG = base .. "/crash.log"
local MAX_RAPID_CRASHES = 5
local RAPID_WINDOW = 30  -- seconds

-- Check for rapid reboot loop
local crashes = {}
if fs.exists(CRASH_LOG) then
    local f = fs.open(CRASH_LOG, "r")
    if f then
        local data = f.readAll()
        f.close()
        -- Parse timestamps from recent crashes
        for ts in data:gmatch("@(%d+)") do
            table.insert(crashes, tonumber(ts))
        end
    end
end

-- Count crashes within the rapid window
local now = os.epoch("utc") / 1000
local recent = 0
for _, ts in ipairs(crashes) do
    if now - ts < RAPID_WINDOW then
        recent = recent + 1
    end
end

if recent >= MAX_RAPID_CRASHES then
    -- Too many rapid crashes — drop to shell so user can diagnose
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.red) end
    print("WRAITH OS - CRASH LOOP DETECTED")
    print()
    if term.isColor() then term.setTextColor(colors.orange) end
    print(string.format("%d crashes in %ds - halting auto-reboot.", recent, RAPID_WINDOW))
    print()
    if term.isColor() then term.setTextColor(colors.lightGray) end
    print("Check " .. CRASH_LOG .. " for details.")
    print("Type 'reboot' to try again, or fix the issue first.")
    print()
    -- Clear crash log so next manual reboot gets a fresh start
    fs.delete(CRASH_LOG)
    return
end

-- =============================================
-- Self-Update Check (before loading OS)
-- =============================================
local selfupdate_path = base .. "/system/selfupdate.lua"
if fs.exists(selfupdate_path) then
    local su_ok, su_result = pcall(dofile, selfupdate_path)
    if su_ok and type(su_result) == "table" and su_result.updated then
        os.reboot()
    end
end

-- Run Wraith OS with error protection
local ok, err = pcall(dofile, base .. "/system/boot.lua")

if not ok then
    -- Log the crash
    local f = fs.open(CRASH_LOG, "a")
    if f then
        f.write(string.format("@%d [%s] %s\n", math.floor(os.epoch("utc") / 1000), os.date(), tostring(err)))
        f.close()
    end

    -- Show error briefly
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.red) end
    print("WRAITH OS CRASHED")
    print()
    if term.isColor() then term.setTextColor(colors.orange) end
    print(tostring(err))
    print()
    if term.isColor() then term.setTextColor(colors.lightGray) end
    print("Rebooting in 3 seconds...")

    sleep(3)
    os.reboot()
end
