-- =============================================
-- WRAITH OS - SELF UPDATE
-- =============================================
-- Pre-boot auto-updater. Fetches manifest from GitHub,
-- compares file hashes, downloads changed files.
-- Returns {updated=bool, count=number} to startup.lua.

local REPO_BASE = "https://raw.githubusercontent.com/OfficalMINI/wraith-os-cc/main/"
local MANIFEST_URL = REPO_BASE .. "manifest.lua"
local CHECK_TIMEOUT = 5
local DOWNLOAD_TIMEOUT = 10

local root = _G.WRAITH_ROOT or "."
local result = {updated = false, count = 0, errors = 0}

-- No HTTP API = no updates
if not http then return result end

-- Same hash used throughout Wraith OS
local function compute_hash(content)
    local sum = 0
    for i = 1, #content do
        sum = (sum * 31 + string.byte(content, i)) % 2147483647
    end
    return tostring(sum)
end

local function local_hash(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    if not content then return nil end
    return compute_hash(content)
end

-- Async HTTP fetch with timeout
local function fetch(url, timeout)
    http.request(url)
    local deadline = os.startTimer(timeout or CHECK_TIMEOUT)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "http_success" and ev[2] == url then
            local body = ev[3].readAll()
            ev[3].close()
            return body
        elseif ev[1] == "http_failure" and ev[2] == url then
            return nil
        elseif ev[1] == "timer" and ev[2] == deadline then
            return nil
        end
    end
end

-- Atomic file write
local function safe_write(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local tmp = path .. ".tmp"
    local f = fs.open(tmp, "w")
    if not f then return false end
    f.write(content)
    f.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

-- Fetch manifest
local manifest_raw = fetch(MANIFEST_URL, CHECK_TIMEOUT)
if not manifest_raw then return result end

-- Parse manifest (Lua table literal)
local parse_fn = load("return " .. manifest_raw, "manifest", "t", {})
if not parse_fn then return result end

local ok, manifest = pcall(parse_fn)
if not ok or type(manifest) ~= "table" then return result end

-- Compare local files against manifest
local to_update = {}
for rel_path, expected_hash in pairs(manifest) do
    local local_path = root .. "/" .. rel_path
    if local_hash(local_path) ~= expected_hash then
        table.insert(to_update, rel_path)
    end
end

if #to_update == 0 then return result end

-- Show update UI
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 2)
if term.isColor() then term.setTextColor(colors.cyan) end
term.write("  WRAITH OS - Auto-Update")
term.setCursorPos(1, 4)
if term.isColor() then term.setTextColor(colors.white) end
term.write(string.format("  %d file(s) to update", #to_update))

-- Download and write each file
for i, rel_path in ipairs(to_update) do
    term.setCursorPos(1, 6)
    if term.isColor() then term.setTextColor(colors.lightGray) end
    term.clearLine()
    term.write(string.format("  [%d/%d] %s", i, #to_update, rel_path))

    local content = fetch(REPO_BASE .. rel_path, DOWNLOAD_TIMEOUT)

    if content and #content > 0 then
        if safe_write(root .. "/" .. rel_path, content) then
            result.count = result.count + 1
        else
            result.errors = result.errors + 1
        end
    else
        result.errors = result.errors + 1
    end
end

if result.count > 0 then
    result.updated = true
    term.setCursorPos(1, 8)
    if term.isColor() then term.setTextColor(colors.lime) end
    term.write(string.format("  Updated %d file(s)!", result.count))
    if result.errors > 0 then
        term.setCursorPos(1, 9)
        if term.isColor() then term.setTextColor(colors.orange) end
        term.write(string.format("  %d error(s)", result.errors))
    end
    term.setCursorPos(1, 11)
    if term.isColor() then term.setTextColor(colors.lightGray) end
    term.write("  Rebooting to apply updates...")
    sleep(2)
end

return result
