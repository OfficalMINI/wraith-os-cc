-- =============================================
-- WRAITH OS - ICON RENDERER & DEFINITIONS
-- =============================================
-- Icons use blit format: {text, fg_hex, bg_hex} per row
-- Characters 128-159 are teletext/drawing chars in CC:Tweaked

local icon = {}

-- Draw an icon at position (uses blit for efficiency)
function icon.draw(buf, icon_data, cx, cy)
    for row = 1, #icon_data do
        local r = icon_data[row]
        buf.setCursorPos(cx, cy + row - 1)
        buf.blit(r[1], r[2], r[3])
    end
end

-- Get icon dimensions
function icon.size(icon_data)
    if not icon_data or #icon_data == 0 then return 0, 0 end
    return #icon_data[1][1], #icon_data
end

-- =============================================
-- Built-in Icon Definitions
-- =============================================
-- Color hex: 0=white,1=orange,2=magenta,3=lightBlue,4=yellow,5=lime,6=pink,7=gray
--            8=lightGray,9=cyan,a=purple,b=blue,c=brown,d=green,e=red,f=black

icon.icons = {}

-- Storage: treasure chest (7x4) - warm orange/brown tones
icon.icons.storage = {
    {"\131\131\131\131\131\131\131", "1111111", "ccccccc"},   -- lid top
    {"\149 \4\4\4 \149",             "c14441c", "1111111"},   -- body + gold trim
    {"\149 \140\7\140 \149",         "c14841c", "1111111"},   -- latch bar + handle
    {"\130\130\130\130\130\130\130", "1111111", "ccccccc"},   -- base
}

-- Redstone: lightning bolt (7x4) - red/yellow energy
icon.icons.redstone = {
    {"   \131\131  ",               "fff44ff", "fffccff"},    -- bolt top
    {"  \143\143   ",               "ff44fff", "ffccfff"},    -- bolt upper
    {" \131\131\131\131  ",         "f4444ff", "fccccff"},    -- bolt wide bar
    {"   \130\130  ",               "fff44ff", "fffffff"},    -- bolt bottom
}

-- Network: signal bars (7x4) - cyan/green gradient
icon.icons.network = {
    {"      \143",                  "fffffff", "ffffff9"},     -- tallest bar
    {"    \143 \143",               "fffffff", "ffffdfd"},     -- second bar
    {"  \143 \143 \143",            "fffffff", "ffdfdfd"},     -- third bar
    {"\143 \143 \143 \143",         "fffffff", "5fdfdfd"},     -- all bars
}

-- Settings: gear (7x4) - cool gray with cyan center
icon.icons.settings = {
    {" \131\143\131\143\131 ",      "f878787", "f8c8c8f"},    -- gear teeth top
    {"\143  9  \143",               "8ff9ff8", "8cc9cc8"},     -- body + center
    {"\143  9  \143",               "8ff9ff8", "8cc9cc8"},     -- body + center
    {" \130\143\130\143\130 ",      "f878787", "ffcfcff"},     -- gear teeth bottom
}

-- YouCube: play button in red frame (7x4)
icon.icons.youcube = {
    {"\151\140\140\140\140\140\148", "eeeeeee", "ccccccc"},    -- frame top
    {"\149 \16   \149",             "ec0ccce", "eccccce"},     -- play arrow
    {"\149 \16\16  \149",           "ec00cce", "eccccce"},     -- play arrow wider
    {"\138\140\140\140\140\140\133", "eeeeeee", "ccccccc"},    -- frame bottom
}

-- Analytics: bar chart (7x4) - cyan/lime bars
icon.icons.analytics = {
    {"    \131\131 ",                  "fffff9f", "fffff9f"},     -- tallest bar top
    {" \131 \143\143\143 ",           "f5f999f", "f5f999f"},     -- bars mid
    {"\131\131\131\143\143\143\131",  "5559995", "5559995"},     -- bars lower
    {"\143\143\143\143\143\143\143",  "5559995", "fffffff"},     -- bars base
}

-- MasterMine: pickaxe on stone (7x4) - yellow/gray mining theme
icon.icons.mastermine = {
    {"  \131\131\131  ",               "ff444ff", "ff777ff"},     -- pickaxe head (yellow on gray)
    {"   \143   ",                     "fff4fff", "fffcfff"},     -- handle upper
    {"  \143    ",                     "ff4ffff", "ffcffff"},     -- handle mid
    {"\143\143\143\143\143\143\143",   "8484848", "fffffff"},     -- stone base
}

-- Terminal: command prompt (7x4) - dark with green text
icon.icons.terminal = {
    {"\151\140\140\140\140\140\148", "8888888", "ccccccc"},    -- frame top
    {"\149\16_   \149",             "85accc8", "8cccccc"},     -- prompt "> _"
    {"\149     \149",               "8ccccc8", "8cccccc"},     -- empty line
    {"\138\140\140\140\140\140\133", "8888888", "ccccccc"},    -- frame bottom
}

-- AR Goggles: visor/glasses (7x4) - purple/cyan AR theme
icon.icons.ar = {
    {" \131\131\131\131\131 ",       "faaaaaf", "ffcccff"},     -- visor top band
    {"\149\131\131 \131\131\149",    "a99f99a", "accfcca"},     -- lenses (cyan glow)
    {"\149\130\130 \130\130\149",    "a99f99a", "accfcca"},     -- lenses bottom
    {" \130\130\130\130\130 ",       "faaaaaf", "ffcccff"},     -- frame bottom
}

-- Projects: clipboard with checklist (7x4) - green/white
icon.icons.projects = {
    {"\151\140\131\131\140\140\148", "8855888", "fffffff"},     -- clipboard top + clip
    {"\149 \7   \149",              "8f5fff8", "8ffffff"},      -- check + line
    {"\149 \7   \149",              "8f5fff8", "8ffffff"},      -- check + line
    {"\138\140\140\140\140\140\133", "8888888", "fffffff"},     -- clipboard bottom
}

-- Lighting: rainbow lamp (7x4) - multicolor glow
icon.icons.lighting = {
    {"  \131\131\131  ",             "ff4e4ff", "ff1e1ff"},     -- bulb top (yellow/red)
    {" \143\143\143\143\143 ",       "f5a9b5f", "f5a9b5f"},     -- bulb mid (lime/purple/cyan/blue/lime)
    {"  \143\143\143  ",             "ff898ff", "ff8c8ff"},     -- bulb neck
    {"  \130\130\130  ",             "ff888ff", "fffffff"},     -- base (gray)
}

-- Loadouts: armour stand / chestplate silhouette (7x4)
icon.icons.loadouts = {
    {"  \131\131\131  ",             "ff888ff", "ff777ff"},
    {" \143\143\143\143\143 ",       "f38383f", "f78787f"},
    {"  \143\143\143  ",             "ff383ff", "ff787ff"},
    {"  \130\130\130  ",             "ff888ff", "fffffff"},
}

-- Smelting: furnace with flames (7x4)
icon.icons.smelting = {
    {"\131\131\131\131\131\131\131", "8888888", "7777777"},
    {"\149 \135\135\135 \149",       "8e1e1e8", "8777778"},
    {"\149 \139\139\139 \149",       "814141e", "8777778"},
    {"\130\130\130\130\130\130\130", "8888888", "7777777"},
}

-- Farms: wheat crops on soil (7x4)
icon.icons.farms = {
    {" \131 \131 \131 ", "fdfdfdf", "f5f5f5f"},     -- crop tops (green/lime)
    {" \143 \143 \143 ", "fdfdfdf", "f5f5f5f"},     -- stems
    {"\131\131\131\131\131\131\131", "ccccccc", "ccccccc"},  -- soil (brown)
    {"\130\130\130\130\130\130\130", "ccccccc", "fffffff"},   -- soil base
}

-- Crafting: workbench with grid top (7x4)
icon.icons.crafting = {
    {"\131\131\131\131\131\131\131", "8888888", "ccccccc"},     -- table top edge
    {"\149\140 \140 \140\149",       "c8c8c8c", "c1c1c1c"},     -- grid row 1 (orange surface)
    {"\149 \140 \140 \149",          "c8c8c8c", "c1c1c1c"},     -- grid row 2
    {"\130\130\130\130\130\130\130", "ccccccc", "fffffff"},      -- legs/base
}

-- Transport: minecart on rail (7x4) - cyan/gray rail theme
icon.icons.transport = {
    {"  \131\131\131  ",             "ff999ff", "ff777ff"},     -- cart top
    {" \149\131\131\131\149 ",       "f79997f", "f97779f"},     -- cart body (cyan)
    {"\140\140\140\140\140\140\140", "8888888", "7777777"},     -- rail
    {" \143 \143 \143 ",            "f8f8f8f", "fffffff"},     -- rail ties
}

return icon
