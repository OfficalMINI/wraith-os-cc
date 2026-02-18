-- =============================================
-- WRAITH OS - THEME ENGINE
-- =============================================
-- Catppuccin Mocha-inspired dark theme
-- Overrides the 16-color CC palette for richer colors

local theme = {}

-- Palette overrides: applied to monitor at boot
-- Format: {color_constant, r, g, b} (0-1 floats)
theme.palette = {
    {colors.black,     0.051, 0.051, 0.071},  -- #0D0D12 deep background
    {colors.gray,      0.118, 0.118, 0.180},  -- #1E1E2E dark surface
    {colors.lightGray, 0.271, 0.278, 0.353},  -- #45475A muted
    {colors.white,     0.804, 0.839, 0.957},  -- #CDD6F4 soft white
    {colors.cyan,      0.537, 0.706, 0.980},  -- #89B4FA primary accent
    {colors.blue,      0.345, 0.357, 0.439},  -- #585B70 secondary surface
    {colors.purple,    0.796, 0.651, 0.969},  -- #CBA6F7 highlight
    {colors.red,       0.953, 0.545, 0.659},  -- #F38BA8 danger
    {colors.orange,    0.980, 0.702, 0.529},  -- #FAB387 warning
    {colors.yellow,    0.976, 0.886, 0.686},  -- #F9E2AF caution
    {colors.lime,      0.651, 0.890, 0.631},  -- #A6E3A1 success
    {colors.green,     0.455, 0.780, 0.925},  -- #74C7EC info
    {colors.lightBlue, 0.537, 0.863, 0.922},  -- #89DCEB secondary info
    {colors.magenta,   0.961, 0.761, 0.906},  -- #F5C2E7 tertiary
    {colors.brown,     0.188, 0.176, 0.255},  -- #302D41 card bg
    {colors.pink,      0.961, 0.878, 0.863},  -- #F5E0DC soft highlight
}

-- Apply palette to a monitor/term
function theme.apply_palette(target)
    for _, entry in ipairs(theme.palette) do
        target.setPaletteColor(entry[1], entry[2], entry[3], entry[4])
    end
end

-- Save current palette (for restore after YouCube)
function theme.save_palette(target)
    local saved = {}
    for i = 0, 15 do
        local r, g, b = target.getPaletteColour(2 ^ i)
        saved[i] = {r, g, b}
    end
    return saved
end

-- Restore a saved palette
function theme.restore_palette(target, saved)
    for i = 0, 15 do
        if saved[i] then
            target.setPaletteColor(2 ^ i, saved[i][1], saved[i][2], saved[i][3])
        end
    end
end

-- Semantic color mappings
theme.bg         = colors.black       -- desktop / window body background
theme.surface    = colors.gray        -- window body surface
theme.surface2   = colors.brown       -- card / panel background
theme.border     = colors.blue        -- window borders, dividers
theme.fg         = colors.white       -- primary text
theme.fg_dim     = colors.lightGray   -- secondary / muted text
theme.fg_dark    = colors.blue        -- very dim text
theme.accent     = colors.cyan        -- primary accent (buttons, highlights)
theme.accent2    = colors.purple      -- secondary accent
theme.success    = colors.lime        -- positive / on
theme.warning    = colors.orange      -- caution
theme.danger     = colors.red         -- error / off
theme.info       = colors.green       -- info accent
theme.highlight  = colors.lightBlue   -- selection highlight
theme.subtle     = colors.magenta     -- subtle emphasis

-- UI-specific (macOS-inspired)
theme.titlebar_focused   = colors.lightGray   -- neutral gray title bar
theme.titlebar_unfocused = colors.brown        -- dim unfocused title bar
theme.titlebar_text      = colors.white        -- bright text on dark title bar
theme.titlebar_text_dim  = colors.blue         -- dim text on unfocused title bar
theme.close_btn          = colors.red          -- traffic light: red
theme.minimize_btn       = colors.yellow       -- traffic light: yellow
theme.zoom_btn           = colors.lime         -- traffic light: green
theme.btn_text           = colors.white
theme.btn_bg             = colors.cyan
theme.btn_disabled_bg    = colors.blue         -- visible disabled state
theme.btn_disabled_fg    = colors.lightGray
theme.taskbar_bg         = colors.gray
theme.taskbar_fg         = colors.white
theme.taskbar_accent     = colors.cyan
theme.desktop_bg         = colors.black
theme.desktop_dot        = colors.brown
theme.icon_label         = colors.white
theme.icon_label_shadow  = colors.black

-- Stock colors (for storage)
theme.stock_high     = colors.lime
theme.stock_med      = colors.yellow
theme.stock_low      = colors.red

return theme
