-- =============================================
-- WRAITH OS - STORAGE APP
-- =============================================
-- Category-based item browser with search, extract, import.

local app = {
    id = "storage",
    name = "Storage",
    icon = "storage",
    default_w = 52,
    default_h = 28,
    singleton = true,
}

-- =============================================
-- Category definitions
-- =============================================
-- Mini blit icons (5w x 3h) for each category
-- Format: {{"chars","fg_hex","bg_hex"}, ...} - same as icon.lua but smaller
local CAT_ICONS = {
    tools = {  -- pickaxe
        {"\131\131\131", "444", "ccc"},
        {" \143 ",       "f4f", "fcf"},
        {"\143  ",       "4ff", "cff"},
    },
    weapons = {  -- sword
        {"  \131", "ff4", "ffc"},
        {" \143 ", "f4f", "fcf"},
        {"\7  ",   "8ff", "fff"},
    },
    armor = {  -- chestplate
        {"\131\131\131", "888", "777"},
        {"\143\143\143", "383", "787"},
        {" \130 ",       "f8f", "fff"},
    },
    food = {  -- apple
        {" \131 ", "fdf", "fff"},
        {"\143\143\143", "eee", "eee"},
        {" \130 ",       "fef", "fff"},
    },
    ores = {  -- diamond
        {" \131 ", "f9f", "f9f"},
        {"\143\143\143", "999", "bbb"},
        {" \130 ",       "f9f", "fff"},
    },
    redstone = {  -- torch/dust
        {" \7 ",         "fef", "fff"},
        {"\131\131\131", "eee", "777"},
        {" \130 ",       "f8f", "fff"},
    },
    colored = {  -- rainbow block
        {"\131\131\131", "e1a", "e1a"},
        {"\143\143\143", "495", "495"},
        {"\130\130\130", "b3d", "fff"},
    },
    nature = {  -- tree
        {" \131 ", "fdf", "fdf"},
        {"\143\143\143", "ddd", "ddd"},
        {" \143 ",       "fcf", "fcf"},
    },
    potions = {  -- bottle
        {" \140 ", "f8f", "fff"},
        {"\149\7\149", "8a8", "8a8"},
        {" \130 ",     "f8f", "fff"},
    },
    building = {  -- brick wall
        {"\131\131\131", "888", "888"},
        {"\149\143\149", "818", "717"},
        {"\130\130\130", "888", "fff"},
    },
    transport = {  -- minecart
        {"\131\131\131", "777", "888"},
        {"\149\4\149",   "747", "787"},
        {"\140\130\140", "878", "fff"},
    },
    decoration = {  -- picture frame
        {"\151\140\148", "111", "fff"},
        {"\149\7\149",   "1d1", "1d1"},
        {"\138\140\133", "111", "fff"},
    },
    mob_drops = {  -- skull
        {"\131\131\131", "000", "888"},
        {"\7 \7",        "f0f", "000"},
        {" \130 ",       "f0f", "fff"},
    },
    enchanting = {  -- glowing book
        {"\131\131 ",    "aaf", "ccf"},
        {"\143\143\143", "a0a", "c0c"},
        {"\130\130 ",    "aaf", "fff"},
    },
    music = {  -- music disc
        {"\131\131\131", "222", "aaa"},
        {"\143\7\143",   "2f2", "afa"},
        {"\130\130\130", "222", "fff"},
    },
    misc = {  -- box
        {"\131\131\131", "888", "777"},
        {"\149\7\149",   "808", "707"},
        {"\130\130\130", "888", "fff"},
    },
}

local CATEGORIES = {
    {id="tools",      name="Tools",         patterns={"pickaxe","shovel","hoe","shears","flint_and_steel","fishing_rod","wrench","hammer","saw","chisel","brush","spyglass"}},
    {id="weapons",    name="Weapons",       patterns={"sword","bow","crossbow","trident","mace","arrow","tipped_arrow"}},
    {id="armor",      name="Armor",         patterns={"helmet","chestplate","leggings","boots","shield","elytra","horse_armor","turtle_helmet"}},
    {id="enchanting", name="Enchanting",    patterns={"enchanted_book","experience_bottle","anvil","enchanting_table","bookshelf","name_tag","book","writable_book","written_book"}},
    {id="food",       name="Food",          patterns={"cooked","raw","bread","apple","carrot","potato","steak","porkchop","chicken","mutton","rabbit","cod","salmon","cake","cookie","pie","melon_slice","sweet_berries","golden_apple","dried_kelp","beef","sugar","egg","milk","mushroom_stew","beetroot","honey","glow_berries","chorus_fruit","suspicious_stew"}},
    {id="ores",       name="Ores & Ingots", patterns={"_ore","ingot","nugget","raw_iron","raw_gold","raw_copper","diamond","emerald","lapis","quartz","amethyst","netherite","coal","charcoal"}},
    {id="transport",  name="Transport",     patterns={"minecart","rail","boat","saddle","lead","carrot_on_a_stick","warped_fungus_on_a_stick"}},
    {id="redstone",   name="Redstone",      patterns={"redstone","piston","lever","repeater","comparator","observer","hopper","dropper","dispenser","daylight","tripwire","target","sculk","note_block","tnt"}},
    {id="music",      name="Music",         patterns={"music_disc","disc_fragment","jukebox","goat_horn"}},
    {id="potions",    name="Potions",       patterns={"potion","splash_potion","lingering_potion","blaze_powder","ghast_tear","magma_cream","phantom_membrane","brewing","nether_wart","glass_bottle","dragon_breath","fermented","glistering","rabbit_foot","spider_eye"}},
    {id="mob_drops",  name="Mob Drops",     patterns={"bone","string","gunpowder","ender_pearl","slime_ball","leather","feather","ink_sac","rotten_flesh","prismarine","shulker_shell","nether_star","wither","echo_shard","disc_fragment","ender_eye","fire_charge","scute","armadillo_scute","nautilus_shell","blaze_rod"}},
    {id="colored",    name="Colored",       patterns={"white_","orange_","magenta_","light_blue_","yellow_","lime_","pink_","gray_","light_gray_","cyan_","purple_","blue_","brown_","green_","red_","black_"}, match_mode="prefix"},
    {id="decoration", name="Decoration",    patterns={"painting","item_frame","flower_pot","armor_stand","candle","sign","bell","chain","end_rod","head","skull","glow_item_frame","hanging_sign","lightning_rod","decorated_pot","mob_head"}},
    {id="nature",     name="Nature",        patterns={"_log","planks","leaves","sapling","flower","_grass","dirt","sand","gravel","moss","vine","fern","bamboo","cactus","seed","wheat","pumpkin","hay","azalea","dripleaf","spore","mangrove","cherry","mushroom"}},
    {id="building",   name="Building",      patterns={"bricks","concrete","terracotta","_glass","slab","stair","wall","fence","_door","gate","trapdoor","lantern","torch","carpet","banner","glazed","polished","smooth_","cut_","chiseled","pillar","tile","_block","deepslate","tuff","calcite","dripstone"}},
}

-- Categorize a single item by its technical name
local function categorize_item(item_name)
    -- Strip namespace prefix (e.g. "minecraft:")
    local short = item_name:gsub("^[^:]+:", "")
    for _, cat in ipairs(CATEGORIES) do
        if cat.match_mode == "prefix" then
            for _, pattern in ipairs(cat.patterns) do
                if short:sub(1, #pattern) == pattern then
                    return cat.id
                end
            end
        else
            for _, pattern in ipairs(cat.patterns) do
                if short:find(pattern, 1, true) then
                    return cat.id
                end
            end
        end
    end
    return "misc"
end

-- Extract mod abbreviation from mod namespace
local function mod_abbrev(mod_id)
    if mod_id == "minecraft" then return "MC" end
    if #mod_id <= 3 then return mod_id:upper() end
    return mod_id:sub(1, 2):upper()
end

-- Build category summary from item list
local function build_categories(items)
    local cats = {}
    for _, cat in ipairs(CATEGORIES) do
        cats[cat.id] = {def = cat, items = {}, count = 0, total_items = 0, mods = {}}
    end
    cats["misc"] = {def = {id="misc", name="Misc"}, items = {}, count = 0, total_items = 0, mods = {}}

    for _, item in ipairs(items) do
        local cid = categorize_item(item.name)
        local c = cats[cid]
        table.insert(c.items, item)
        c.count = c.count + 1
        c.total_items = c.total_items + item.count
        -- Track mod source
        local mod_id = item.name:match("^([^:]+):") or "unknown"
        c.mods[mod_id] = (c.mods[mod_id] or 0) + 1
    end

    -- Build ordered list (only non-empty categories)
    local ordered = {}
    for _, cat in ipairs(CATEGORIES) do
        if cats[cat.id].count > 0 then
            table.insert(ordered, cats[cat.id])
        end
    end
    if cats["misc"].count > 0 then
        table.insert(ordered, cats["misc"])
    end
    return ordered, cats
end

-- Build mod-based categories from item list (group by mod namespace)
local MOD_ICON_POOL = {"tools", "weapons", "armor", "food", "ores", "redstone",
    "nature", "potions", "building", "transport", "decoration", "enchanting",
    "music", "mob_drops", "colored", "misc"}
local MOD_COLOR_POOL = {"warning", "danger", "accent", "success", "info",
    "accent2", "fg_dim"}
local mod_icon_cache = {}  -- {mod_id -> icon_key} persistent within session

local function get_mod_icon(mod_id)
    if mod_icon_cache[mod_id] then return mod_icon_cache[mod_id] end
    -- Deterministic hash from mod name for consistent assignment
    local hash = 0
    for i = 1, #mod_id do hash = hash + string.byte(mod_id, i) * i end
    local icon_key = MOD_ICON_POOL[(hash % #MOD_ICON_POOL) + 1]
    mod_icon_cache[mod_id] = icon_key
    return icon_key
end

local function get_mod_color(mod_id)
    local hash = 0
    for i = 1, #mod_id do hash = hash + string.byte(mod_id, i) * (i + 7) end
    return MOD_COLOR_POOL[(hash % #MOD_COLOR_POOL) + 1]
end

local function mod_display_name(mod_id)
    if mod_id == "minecraft" then return "Minecraft" end
    -- Capitalize first letter, replace underscores with spaces
    local name = mod_id:gsub("_", " ")
    return name:sub(1,1):upper() .. name:sub(2)
end

local function build_mod_categories(items)
    local mods = {}  -- mod_id -> {def, items, count, total_items, mods}

    for _, item in ipairs(items) do
        local mod_id = item.name:match("^([^:]+):") or "unknown"
        if not mods[mod_id] then
            mods[mod_id] = {
                def = {id = "mod:" .. mod_id, name = mod_display_name(mod_id)},
                items = {}, count = 0, total_items = 0,
                mods = {[mod_id] = 0},
                mod_id = mod_id,
            }
        end
        local m = mods[mod_id]
        table.insert(m.items, item)
        m.count = m.count + 1
        m.total_items = m.total_items + item.count
        m.mods[mod_id] = m.mods[mod_id] + 1
    end

    -- Sort by total items descending
    local ordered = {}
    for _, m in pairs(mods) do
        table.insert(ordered, m)
    end
    table.sort(ordered, function(a, b) return a.total_items > b.total_items end)
    return ordered
end

-- =============================================
-- Per-instance state
-- =============================================
local view_mode = "categories"  -- "categories" | "category_detail" | "list"
local current_category = nil
local scroll = 0
local selected = 1
local search_query = ""
local feedback = nil  -- {msg, color, ok, time}
local cat_scroll = 0
local cat_group = "type"  -- "type" | "mod"
local page_cooldown_until = 0 -- os.clock() time when page cooldown expires

-- Hit areas populated by render, consumed by click handler
local hits = {}

-- =============================================
-- Shared render helpers
-- =============================================

-- Render the header (4 rows) - shared across all views
local function render_header(ctx, buf, x, y, w)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage

    local icon_lib = _G._wraith and _G._wraith.icon_lib
    local icon_data = icon_lib and icon_lib.icons and icon_lib.icons.storage

    for r = 0, 3 do
        draw.fill(buf, y + r, x + w, theme.surface2)
    end

    if icon_data and icon_lib then
        icon_lib.draw(buf, icon_data, x + 2, y)
    end

    local sx = x + 11
    draw.put(buf, sx, y, "STORAGE", theme.accent, theme.surface2)
    if st.ready and st.stats then
        local cap = string.format("%d/%d %d%%", st.stats.used_slots, st.stats.total_slots,
            math.floor(st.stats.usage_pct * 100))
        draw.put(buf, x + w - #cap - 1, y, cap, theme.fg_dim, theme.surface2)
    end

    if st.ready and st.stats then
        local pct = st.stats.usage_pct
        local bar_w = w - 13
        local fg = pct > 0.9 and theme.danger or (pct > 0.7 and theme.warning or theme.accent)
        draw.progress(buf, sx, y + 1, bar_w, pct, fg, theme.border)
    else
        draw.put(buf, sx, y + 1, "Scanning storage...", theme.warning, theme.surface2)
    end

    local info_parts = {}
    if st.ready then
        table.insert(info_parts, string.format("%d types", st.type_count or 0))
        table.insert(info_parts, string.format("%s items", utils.format_number(st.item_count or 0)))
    end
    if st.furnace_count and st.furnace_count > 0 then
        table.insert(info_parts, string.format("%dF", st.furnace_count))
    end
    draw.put(buf, sx, y + 2, table.concat(info_parts, "  |  "), theme.fg_dim, theme.surface2)

    local assign = st.get_assignments and st.get_assignments() or {}
    local out_short = assign.output and utils.truncate(assign.output, 14) or "Not set"
    local out_col = assign.output_ok and theme.success or theme.danger
    draw.put(buf, sx, y + 3, "OUT:", theme.fg_dark, theme.surface2)
    draw.put(buf, sx + 4, y + 3, out_short, out_col, theme.surface2)
    local dc = assign.depot_count or 0
    draw.put(buf, sx + 22, y + 3, "DEP:", theme.fg_dark, theme.surface2)
    draw.put(buf, sx + 26, y + 3, tostring(dc), dc > 0 and theme.info or theme.fg_dark, theme.surface2)

    return y + 4
end

-- Render navigation bar (1 row)
local function render_nav_bar(ctx, buf, x, y, w)
    local draw = ctx.draw
    local theme = ctx.theme

    draw.fill(buf, y, x + w, theme.surface)

    -- Search button (left)
    local has_filter = search_query ~= ""
    if has_filter then
        draw.put(buf, x + 1, y, "\16", theme.accent, theme.surface)
        draw.put(buf, x + 3, y, "[", theme.fg_dim, theme.surface)
        local max_q = w - 22
        local sq = search_query
        if #sq > max_q then sq = sq:sub(1, max_q - 2) .. ".." end
        draw.put(buf, x + 4, y, sq, theme.fg, theme.surface)
        draw.put(buf, x + 4 + #sq, y, "]", theme.fg_dim, theme.surface)
        -- Clear button
        draw.button(buf, x + 6 + #sq, y, 3, 1, "X", theme.danger, theme.bg, true)
        hits.clear_btn = {x = 6 + #sq + 1, y = y - hits.oy + 1, w = 3, h = 1}
    else
        draw.put(buf, x + 1, y, "\16", theme.accent, theme.surface)
        draw.put(buf, x + 3, y, "search...", theme.fg_dim, theme.surface)
    end
    hits.search_bar = {x = 1, y = y - hits.oy + 1, w = 14, h = 1}

    -- BACK button (when in category detail)
    if view_mode == "category_detail" then
        draw.button(buf, x + w - 26, y, 8, 1, "\17 BACK", theme.warning, theme.bg, true)
        hits.back_btn = {x = w - 26 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    end

    -- TYPE/MOD toggle (center-right, only in categories/detail views)
    if view_mode ~= "list" then
        local grp_label = cat_group == "type" and "MOD" or "TYPE"
        draw.button(buf, x + w - 17, y, 8, 1, grp_label, theme.info, theme.surface, true)
        hits.group_btn = {x = w - 17 + 1, y = y - hits.oy + 1, w = 8, h = 1}
    end

    -- VIEW toggle (right)
    local view_label = view_mode == "list" and "GRID" or "LIST"
    draw.button(buf, x + w - 8, y, 8, 1, view_label, theme.accent, theme.surface, true)
    hits.view_btn = {x = w - 8 + 1, y = y - hits.oy + 1, w = 8, h = 1}

    return y + 1
end

-- Render action buttons row (shared between detail and list views)
local function render_action_buttons(ctx, buf, x, y, w, has_sel)
    local draw = ctx.draw
    local theme = ctx.theme

    draw.fill(buf, y, x + w, theme.surface2)
    local nb = 5
    local bw = math.floor((w - nb - 1) / nb)
    if bw < 6 then bw = 6 end
    local bx = x + 1

    local function store_btn(id, label, bg, enabled)
        draw.button(buf, bx, y, bw, 1, label, bg, theme.bg, enabled)
        hits.btns[id] = {x = bx - hits.ox + 1, y = y - hits.oy + 1, w = bw, h = 1}
        bx = bx + bw + 1
    end

    store_btn("get1", "GET x1", theme.accent, has_sel)
    store_btn("get64", "GET x64", theme.accent, has_sel)
    store_btn("getall", "GET ALL", theme.accent2, has_sel)
    store_btn("import", "IMPORT", theme.success, true)
    store_btn("smelt", "SMELT", theme.warning, true)
end

-- Render smelting row
local function render_smelting_row(ctx, buf, x, y, w)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage

    if not st.furnace_count or st.furnace_count <= 0 then return y end

    draw.fill(buf, y, x + w, theme.surface)
    local sm = st.get_smelting_stats and st.get_smelting_stats() or {}
    local on = sm.enabled
    draw.put(buf, x + 1, y, "\7", on and theme.accent2 or theme.fg_dim, theme.surface)
    draw.put(buf, x + 3, y, string.format("%dF", st.furnace_count), theme.fg_dim, theme.surface)
    draw.put(buf, x + 7, y, "IN:" .. utils.format_number(sm.items_smelted or 0), theme.fg_dim, theme.surface)
    draw.put(buf, x + 17, y, "OUT:" .. utils.format_number(sm.items_pulled or 0), theme.fg_dim, theme.surface)
    local tl = on and "ON" or "OFF"
    draw.button(buf, x + w - 20, y, 5, 1, tl,
        on and theme.success or theme.danger, theme.btn_text, true)
    hits.smelt_btn = {x = w - 20 + 1, y = y - hits.oy + 1, w = 5, h = 1}
    draw.button(buf, x + w - 14, y, 13, 1, "\7 SMELTING",
        theme.warning, theme.btn_text, true)
    hits.smelt_app_btn = {x = w - 14 + 1, y = y - hits.oy + 1, w = 13, h = 1}
    return y + 1
end

-- Render feedback toast
local function render_feedback(ctx, buf, x, y, w)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils

    if feedback and os.clock() - feedback.time < 4 then
        draw.fill(buf, y, x + w, theme.surface)
        local icon_char = feedback.ok and "\4 " or "\7 "
        local msg = icon_char .. feedback.msg
        if #msg > w - 2 then msg = msg:sub(1, w - 4) .. ".." end
        draw.put(buf, x + 1, y, msg, feedback.color or theme.fg, theme.surface)
        return y + 1
    else
        feedback = nil
        return y
    end
end

-- Render scrollable item list (used by both category_detail and list views)
local function render_item_list(ctx, buf, x, y, w, list_h, filtered)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage

    local max_scroll = math.max(0, #filtered - list_h)
    if scroll > max_scroll then scroll = max_scroll end
    hits.max_scroll = max_scroll
    hits.list_start_y = y - hits.oy + 1
    hits.list_h = list_h

    if #filtered == 0 then
        draw.fillR(buf, y, y + list_h - 1, x + w, theme.surface)
        local msg = st.ready and "No items found" or "Scanning..."
        draw.center(buf, msg, y + math.floor(list_h / 2), x + w, theme.fg_dim, theme.surface)
        y = y + list_h
    else
        for i = 1, list_h do
            local idx = scroll + i
            local item = filtered[idx]
            if item then
                local sel = (idx == selected)
                local rbg = sel and theme.highlight or theme.surface
                local nfg = sel and theme.bg or theme.fg
                draw.fill(buf, y, x + w, rbg)

                if sel then draw.put(buf, x + 1, y, "\16", theme.accent2, rbg) end

                local nw = w - 13
                local dn = item.displayName or ""
                if #dn > nw then dn = dn:sub(1, nw - 2) .. ".." end
                draw.put(buf, x + 3, y, dn, nfg, rbg)

                local cfg
                if sel then
                    cfg = theme.bg
                elseif st.get_stock_color then
                    cfg = st.get_stock_color(item.count)
                else
                    cfg = item.count < 16 and theme.stock_low
                        or item.count < 64 and theme.stock_med
                        or theme.stock_high
                end
                draw.put(buf, x + w - 10, y, utils.pad_left(utils.format_number(item.count), 8), cfg, rbg)
            else
                draw.fill(buf, y, x + w, theme.surface)
            end
            y = y + 1
        end
    end

    -- Scroll bar
    draw.fill(buf, y, x + w, theme.surface)
    if #filtered > list_h then
        local on_cooldown = os.clock() < page_cooldown_until
        local can_up = scroll > 0 and not on_cooldown
        local can_dn = scroll < max_scroll and not on_cooldown
        draw.button(buf, x + 1, y, 3, 1, "\30", can_up and theme.accent or theme.fg_dark, theme.surface, can_up)
        hits.scroll_up = {x = 2, y = y - hits.oy + 1, w = 3, h = 1}
        local info = string.format("%d-%d of %d", scroll + 1,
            math.min(scroll + list_h, #filtered), #filtered)
        draw.center(buf, info, y, x + w, theme.fg_dim, theme.surface)
        draw.button(buf, x + w - 4, y, 3, 1, "\31", can_dn and theme.accent or theme.fg_dark, theme.surface, can_dn)
        hits.scroll_dn = {x = w - 4 + 1, y = y - hits.oy + 1, w = 3, h = 1}
    end
    y = y + 1

    return y
end

-- =============================================
-- Category grid view (with pixel art icons)
-- =============================================
local cat_colors_map = {
    tools = "warning", weapons = "danger", armor = "accent",
    enchanting = "accent2", food = "success", ores = "warning",
    transport = "info", music = "accent2", redstone = "danger",
    potions = "accent2", mob_drops = "fg_dim", colored = "accent",
    decoration = "warning", nature = "success", building = "fg_dim",
    misc = "fg_dim",
}

local function render_category_grid(ctx, buf, x, y, w, h)
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage

    local items = st.items or {}
    local ordered
    if cat_group == "mod" then
        ordered = build_mod_categories(items)
    else
        ordered = build_categories(items)
    end

    if #ordered == 0 then
        draw.fillR(buf, y, y + h - 1, x + w, theme.surface)
        local msg = st.ready and "No items in storage" or "Scanning..."
        draw.center(buf, msg, y + math.floor(h / 2), x + w, theme.fg_dim, theme.surface)
        return
    end

    -- Reserve 1 row at bottom for page indicator
    local grid_h = h - 1
    local page_y = y + grid_h

    -- 2-column grid, 5 rows per card (icon 3h + mod + items), 1 gap
    local col_w = math.floor((w - 3) / 2)
    local CARD_H = 5
    local GAP = 1
    local visible_rows = math.floor((grid_h + GAP) / (CARD_H + GAP))
    if visible_rows < 1 then visible_rows = 1 end
    local cards_per_page = visible_rows * 2
    local total_pages = math.ceil(#ordered / cards_per_page)
    local current_page = math.floor(cat_scroll / visible_rows) + 1
    local max_cat_scroll = math.max(0, math.ceil(#ordered / 2) - visible_rows)
    if cat_scroll > max_cat_scroll then cat_scroll = max_cat_scroll end
    hits.cat_max_scroll = max_cat_scroll
    hits.cat_visible_rows = visible_rows

    -- Clear background
    draw.fillR(buf, y, y + h - 1, x + w, theme.bg)

    hits.cat_cards = {}

    local row_start = cat_scroll * 2
    local drawn = 0
    for i = row_start + 1, #ordered do
        if drawn >= visible_rows * 2 then break end

        local cat = ordered[i]
        local col = drawn % 2
        local row = math.floor(drawn / 2)
        local cx = x + 1 + col * (col_w + 1)
        local cy = y + row * (CARD_H + GAP)

        if cy + CARD_H > y + grid_h then break end

        -- Resolve color and icon (type categories use map, mod categories use hash)
        local ccolor
        local icon_key
        if cat.mod_id then
            -- Mod category
            ccolor = theme[get_mod_color(cat.mod_id)]
            icon_key = get_mod_icon(cat.mod_id)
        else
            ccolor = theme[cat_colors_map[cat.def.id] or "fg_dim"]
            icon_key = cat.def.id
        end

        -- Card background (full card)
        for r = 0, CARD_H - 1 do
            buf.setCursorPos(cx, cy + r)
            buf.setBackgroundColor(theme.surface2)
            buf.write(string.rep(" ", col_w))
        end

        -- Left side: Blit pixel icon (3w x 3h)
        local icon_data = CAT_ICONS[icon_key]
        if icon_data then
            for row_i = 1, #icon_data do
                local r = icon_data[row_i]
                buf.setCursorPos(cx + 1, cy + row_i - 1)
                buf.blit(r[1], r[2], r[3])
            end
        end

        -- Right of icon: Category name (bold color)
        local name_x = cx + 5
        local cat_name = cat.def.name
        local max_name = col_w - 7
        if #cat_name > max_name then cat_name = cat_name:sub(1, max_name - 2) .. ".." end
        draw.put(buf, name_x, cy, cat_name, ccolor, theme.surface2)

        -- Right of icon: Stats line
        local stats_str = string.format("%d types  %s items", cat.count, utils.format_number(cat.total_items))
        if #stats_str > col_w - 7 then stats_str = string.format("%d  %s", cat.count, utils.format_number(cat.total_items)) end
        draw.put(buf, name_x, cy + 1, stats_str, theme.fg_dim, theme.surface2)

        -- Right of icon: Source tags
        if cat.mod_id then
            -- Mod category: show top type categories found within
            local type_counts = {}
            for _, item in ipairs(cat.items) do
                local tid = categorize_item(item.name)
                type_counts[tid] = (type_counts[tid] or 0) + 1
            end
            local tpairs = {}
            for tid, cnt in pairs(type_counts) do
                table.insert(tpairs, {id = tid, count = cnt})
            end
            table.sort(tpairs, function(a, b) return a.count > b.count end)
            local parts = {}
            local avail = col_w - 8
            for _, tp in ipairs(tpairs) do
                local tag = tp.id:sub(1,4) .. ":" .. tp.count
                if avail - #tag - (#parts > 0 and 1 or 0) < 0 then break end
                avail = avail - #tag - (#parts > 0 and 1 or 0)
                table.insert(parts, tag)
                if #parts >= 3 then break end
            end
            draw.put(buf, name_x, cy + 2, table.concat(parts, " "), theme.fg_dark, theme.surface2)
        else
            -- Type category: show mod source tags (e.g. "MC:45 CR:3")
            local mod_pairs = {}
            for mod_id, cnt in pairs(cat.mods) do
                table.insert(mod_pairs, {id = mod_id, count = cnt})
            end
            table.sort(mod_pairs, function(a, b) return a.count > b.count end)
            local mod_str_parts = {}
            local mod_avail = col_w - 8
            for _, mp in ipairs(mod_pairs) do
                local tag = mod_abbrev(mp.id) .. ":" .. mp.count
                if mod_avail - #tag - (#mod_str_parts > 0 and 1 or 0) < 0 then break end
                mod_avail = mod_avail - #tag - (#mod_str_parts > 0 and 1 or 0)
                table.insert(mod_str_parts, tag)
                if #mod_str_parts >= 3 then break end
            end
            draw.put(buf, name_x, cy + 2, table.concat(mod_str_parts, " "), theme.fg_dark, theme.surface2)
        end

        -- Arrow indicator
        draw.put(buf, cx + col_w - 2, cy + 2, "\16", theme.accent, theme.surface2)

        -- Row 4-5: Top 2 items preview
        local preview_y = cy + 3
        for pi = 1, math.min(2, #cat.items) do
            local pitem = cat.items[pi]
            local pname = pitem.displayName or ""
            local pcount = utils.format_number(pitem.count)
            local max_pname = col_w - #pcount - 4
            if #pname > max_pname then pname = pname:sub(1, max_pname - 2) .. ".." end
            draw.put(buf, cx + 1, preview_y + pi - 1, "\7", theme.fg_dark, theme.surface2)
            draw.put(buf, cx + 3, preview_y + pi - 1, pname, theme.fg_dim, theme.surface2)
            draw.put(buf, cx + col_w - #pcount - 1, preview_y + pi - 1, pcount, ccolor, theme.surface2)
        end

        table.insert(hits.cat_cards, {
            x = cx - hits.ox + 1, y = cy - hits.oy + 1,
            w = col_w, h = CARD_H,
            id = cat.def.id,
        })

        drawn = drawn + 1
    end

    -- Page indicator row at bottom
    draw.fill(buf, page_y, x + w, theme.surface)
    if total_pages > 1 then
        local on_cooldown = os.clock() < page_cooldown_until
        local can_prev = cat_scroll > 0 and not on_cooldown
        local can_next = cat_scroll < max_cat_scroll and not on_cooldown
        -- Left arrow
        draw.button(buf, x + math.floor(w / 2) - 10, page_y, 3, 1, "\17",
            can_prev and theme.accent or theme.fg_dark, theme.surface, can_prev)
        hits.cat_prev = {x = math.floor(w / 2) - 10 + 1, y = page_y - hits.oy + 1, w = 3, h = 1}
        -- Page info
        local page_str = string.format("Page %d/%d", current_page, total_pages)
        draw.center(buf, page_str, page_y, x + w, theme.fg_dim, theme.surface)
        -- Right arrow
        draw.button(buf, x + math.floor(w / 2) + 8, page_y, 3, 1, "\16",
            can_next and theme.accent or theme.fg_dark, theme.surface, can_next)
        hits.cat_next = {x = math.floor(w / 2) + 8 + 1, y = page_y - hits.oy + 1, w = 3, h = 1}
    else
        local page_str = string.format("%d categories", #ordered)
        draw.center(buf, page_str, page_y, x + w, theme.fg_dim, theme.surface)
    end
end

-- =============================================
-- Main render
-- =============================================
function app.render(ctx, buf)
    local x = ctx.content_x
    local y = ctx.content_y
    local w = ctx.content_w
    local h = ctx.content_h
    local draw = ctx.draw
    local theme = ctx.theme
    local utils = ctx.utils
    local st = ctx.state.storage

    -- Reset hit areas each frame
    hits = {btns = {}}
    hits.ox = ctx.content_x
    hits.oy = ctx.content_y

    -- Header (4 rows)
    y = render_header(ctx, buf, x, y, w)

    -- Separator
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Navigation bar
    y = render_nav_bar(ctx, buf, x, y, w)

    -- Separator
    draw.put(buf, x, y, string.rep("\140", w), theme.border, theme.surface)
    y = y + 1

    -- Remaining height for body
    local body_start = y
    local rows_above = y - ctx.content_y
    -- Reserve rows for bottom elements
    local rows_below = 1  -- action buttons
    if st.furnace_count and st.furnace_count > 0 then rows_below = rows_below + 1 end
    if feedback and os.clock() - feedback.time < 4 then rows_below = rows_below + 1 end
    local body_h = h - rows_above - rows_below

    if view_mode == "categories" then
        -- Category grid fills the body
        render_category_grid(ctx, buf, x, y, w, body_h)
        y = y + body_h

        -- Smelting row
        y = render_smelting_row(ctx, buf, x, y, w)

        -- Feedback
        y = render_feedback(ctx, buf, x, y, w)

        -- Bottom buttons (no item selection in grid view)
        render_action_buttons(ctx, buf, x, y, w, false)

    elseif view_mode == "category_detail" then
        -- Category header
        local cat_info = nil
        local cat_items = {}
        local items = st.items or {}
        local is_mod_cat = current_category and current_category:sub(1, 4) == "mod:"

        if is_mod_cat then
            -- Mod category: filter by mod namespace
            local mod_id = current_category:sub(5)
            for _, item in ipairs(items) do
                local item_mod = item.name:match("^([^:]+):") or ""
                if item_mod == mod_id then
                    table.insert(cat_items, item)
                end
            end
            cat_info = {id = current_category, name = mod_display_name(mod_id)}
        else
            -- Type category: filter by pattern match
            for _, item in ipairs(items) do
                if categorize_item(item.name) == current_category then
                    table.insert(cat_items, item)
                end
            end
            for _, cat in ipairs(CATEGORIES) do
                if cat.id == current_category then cat_info = cat; break end
            end
        end
        if not cat_info then cat_info = {id="misc", name="Misc"} end

        -- Category title row with blit icon
        draw.fill(buf, y, x + w, theme.surface)
        local ccolor
        local icon_key
        if is_mod_cat then
            local mod_id = current_category:sub(5)
            ccolor = theme[get_mod_color(mod_id)]
            icon_key = get_mod_icon(mod_id)
        else
            ccolor = theme[cat_colors_map[cat_info.id] or "fg_dim"]
            icon_key = cat_info.id
        end
        -- Draw mini icon inline (first row of blit icon)
        local icon_data = CAT_ICONS[icon_key]
        if icon_data and icon_data[1] then
            buf.setCursorPos(x + 1, y)
            buf.blit(icon_data[1][1], icon_data[1][2], icon_data[1][3])
        end
        draw.put(buf, x + 5, y, cat_info.name, ccolor, theme.surface)
        draw.put(buf, x + 6 + #cat_info.name, y,
            string.format(" (%d)", #cat_items), theme.fg_dim, theme.surface)
        -- Column headers
        draw.put(buf, x + w - 10, y, "QTY", theme.accent, theme.surface)
        y = y + 1

        -- Item list (subtract 1 more row for category header, and rows_below includes scroll bar)
        local list_h = body_h - 2  -- -1 category header, -1 scroll bar
        if list_h < 3 then list_h = 3 end

        y = render_item_list(ctx, buf, x, y, w, list_h, cat_items)

        -- Smelting row
        y = render_smelting_row(ctx, buf, x, y, w)

        -- Feedback
        y = render_feedback(ctx, buf, x, y, w)

        -- Action buttons
        local has_sel = #cat_items > 0 and selected >= 1 and selected <= #cat_items
        render_action_buttons(ctx, buf, x, y, w, has_sel)

        -- Store filtered items for click handler
        hits.current_items = cat_items

    else -- "list" view
        -- Column headers
        draw.fill(buf, y, x + w, theme.surface)
        draw.put(buf, x + 2, y, "ITEM", theme.accent, theme.surface)
        draw.put(buf, x + w - 10, y, "QTY", theme.accent, theme.surface)
        y = y + 1

        local filtered = {}
        if st.get_filtered then
            filtered = st.get_filtered(search_query)
        elseif st.items then
            filtered = st.items
        end

        local list_h = body_h - 2  -- -1 column header, -1 scroll bar
        if list_h < 3 then list_h = 3 end

        y = render_item_list(ctx, buf, x, y, w, list_h, filtered)

        -- Smelting row
        y = render_smelting_row(ctx, buf, x, y, w)

        -- Feedback
        y = render_feedback(ctx, buf, x, y, w)

        -- Action buttons
        local has_sel = #filtered > 0 and selected >= 1 and selected <= #filtered
        render_action_buttons(ctx, buf, x, y, w, has_sel)

        hits.current_items = filtered
    end
end

-- =============================================
-- Get current item list for click/key handlers
-- =============================================
local function get_active_items(st)
    if view_mode == "category_detail" then
        local items = st.items or {}
        local cat_items = {}
        local is_mod_cat = current_category and current_category:sub(1, 4) == "mod:"
        if is_mod_cat then
            local mod_id = current_category:sub(5)
            for _, item in ipairs(items) do
                local item_mod = item.name:match("^([^:]+):") or ""
                if item_mod == mod_id then
                    table.insert(cat_items, item)
                end
            end
        else
            for _, item in ipairs(items) do
                if categorize_item(item.name) == current_category then
                    table.insert(cat_items, item)
                end
            end
        end
        return cat_items
    elseif view_mode == "list" then
        if st.get_filtered then
            return st.get_filtered(search_query)
        end
        return st.items or {}
    end
    return {}
end

-- =============================================
-- Withdraw helper
-- =============================================
local function do_withdraw(ctx, item, amount)
    local st = ctx.state.storage
    local utils = ctx.utils
    if not (st.withdraw or st.extract) then return end
    local fn = st.withdraw or st.extract
    local got = fn(item, amount)
    feedback = {
        msg = got > 0 and string.format("Withdrew %sx %s", got, utils.truncate(item.displayName, 14))
            or "Failed!",
        color = got > 0 and ctx.theme.success or ctx.theme.danger,
        ok = got > 0, time = os.clock()
    }
end

-- =============================================
-- Event handler
-- =============================================
function app.main(ctx)
    local st = ctx.state.storage
    local draw = ctx.draw
    local utils = ctx.utils

    while true do
        local ev = {coroutine.yield()}
        local ev_type = ev[1]

        if ev_type == "mouse_click" then
            local tx, ty = ev[3], ev[4]

            -- Clear search filter
            if hits.clear_btn and draw.hit_test(hits.clear_btn, tx, ty) then
                search_query = ""
                scroll = 0
                selected = 1
                if view_mode == "list" and search_query == "" then
                    -- Stay in list mode
                end

            -- Search bar click -> PC input
            elseif hits.search_bar and draw.hit_test(hits.search_bar, tx, ty) then
                local result = utils.pc_input("SEARCH STORAGE", "Type item name to filter.")
                if result and result ~= "" then
                    search_query = result
                    view_mode = "list"
                else
                    search_query = ""
                end
                scroll = 0
                selected = 1

            -- BACK button
            elseif hits.back_btn and draw.hit_test(hits.back_btn, tx, ty) then
                view_mode = "categories"
                current_category = nil
                scroll = 0
                selected = 1

            -- VIEW toggle
            elseif hits.view_btn and draw.hit_test(hits.view_btn, tx, ty) then
                if view_mode == "list" then
                    view_mode = "categories"
                    current_category = nil
                    search_query = ""
                else
                    view_mode = "list"
                end
                scroll = 0
                selected = 1

            -- TYPE/MOD group toggle
            elseif hits.group_btn and draw.hit_test(hits.group_btn, tx, ty) then
                cat_group = cat_group == "type" and "mod" or "type"
                view_mode = "categories"
                current_category = nil
                cat_scroll = 0
                scroll = 0
                selected = 1

            -- Category page navigation (full page per click, 1s clock cooldown)
            elseif hits.cat_prev and draw.hit_test(hits.cat_prev, tx, ty) then
                if os.clock() >= page_cooldown_until then
                    local step = hits.cat_visible_rows or 1
                    cat_scroll = math.max(0, cat_scroll - step)
                    page_cooldown_until = os.clock() + 1
                end

            elseif hits.cat_next and draw.hit_test(hits.cat_next, tx, ty) then
                if os.clock() >= page_cooldown_until then
                    local max_s = hits.cat_max_scroll or 0
                    local step = hits.cat_visible_rows or 1
                    cat_scroll = math.min(max_s, cat_scroll + step)
                    page_cooldown_until = os.clock() + 1
                end

            -- Category card click
            elseif view_mode == "categories" and hits.cat_cards then
                local handled = false
                for _, card in ipairs(hits.cat_cards) do
                    if draw.hit_test(card, tx, ty) then
                        current_category = card.id
                        view_mode = "category_detail"
                        scroll = 0
                        selected = 1
                        handled = true
                        break
                    end
                end
                if not handled then
                    -- Check action buttons even in grid view
                    if hits.btns["import"] and draw.hit_test(hits.btns["import"], tx, ty) then
                        if st.import then
                            local got = st.import()
                            feedback = {
                                msg = got > 0 and string.format("Imported %s items", utils.format_number(got))
                                    or "Nothing to import",
                                color = got > 0 and ctx.theme.success or ctx.theme.fg_dim,
                                ok = got > 0, time = os.clock()
                            }
                        end
                    elseif hits.btns.smelt and draw.hit_test(hits.btns.smelt, tx, ty) then
                        os.queueEvent("wraith:launch_app", "smelting")
                    elseif hits.smelt_btn and draw.hit_test(hits.smelt_btn, tx, ty) then
                        if st.toggle_smelting then st.toggle_smelting() end
                    elseif hits.smelt_app_btn and draw.hit_test(hits.smelt_app_btn, tx, ty) then
                        os.queueEvent("wraith:launch_app", "smelting")
                    end
                end

            -- Scroll up button (1s cooldown)
            elseif hits.scroll_up and draw.hit_test(hits.scroll_up, tx, ty) then
                if os.clock() >= page_cooldown_until then
                    scroll = math.max(0, scroll - 5)
                    page_cooldown_until = os.clock() + 1
                end

            -- Scroll down button (1s cooldown)
            elseif hits.scroll_dn and draw.hit_test(hits.scroll_dn, tx, ty) then
                if os.clock() >= page_cooldown_until then
                    local max_s = hits.max_scroll or 0
                    scroll = math.min(max_s, scroll + 5)
                    page_cooldown_until = os.clock() + 1
                end

            -- Item list click (category_detail or list view)
            elseif hits.list_start_y and ty >= hits.list_start_y and ty < hits.list_start_y + (hits.list_h or 0) then
                local clicked = scroll + (ty - hits.list_start_y + 1)
                local active = get_active_items(st)
                if clicked >= 1 and clicked <= #active then
                    selected = clicked
                end

            -- Smelting toggle
            elseif hits.smelt_btn and draw.hit_test(hits.smelt_btn, tx, ty) then
                if st.toggle_smelting then st.toggle_smelting() end

            -- Smelting app launch
            elseif hits.smelt_app_btn and draw.hit_test(hits.smelt_app_btn, tx, ty) then
                os.queueEvent("wraith:launch_app", "smelting")

            -- Action buttons
            else
                local active = get_active_items(st)
                local has_sel = #active > 0 and selected >= 1 and selected <= #active

                if hits.btns.get1 and draw.hit_test(hits.btns.get1, tx, ty) then
                    if has_sel then do_withdraw(ctx, active[selected], 1) end

                elseif hits.btns.get64 and draw.hit_test(hits.btns.get64, tx, ty) then
                    if has_sel then do_withdraw(ctx, active[selected], math.min(64, active[selected].count)) end

                elseif hits.btns.getall and draw.hit_test(hits.btns.getall, tx, ty) then
                    if has_sel then do_withdraw(ctx, active[selected], active[selected].count) end

                elseif hits.btns["import"] and draw.hit_test(hits.btns["import"], tx, ty) then
                    if st.import then
                        local got = st.import()
                        feedback = {
                            msg = got > 0 and string.format("Imported %s items", utils.format_number(got))
                                or "Nothing to import",
                            color = got > 0 and ctx.theme.success or ctx.theme.fg_dim,
                            ok = got > 0, time = os.clock()
                        }
                    end

                elseif hits.btns.smelt and draw.hit_test(hits.btns.smelt, tx, ty) then
                    os.queueEvent("wraith:launch_app", "smelting")
                end
            end

        elseif ev_type == "mouse_scroll" then
            local dir = ev[2]  -- 1 = down, -1 = up
            if view_mode == "categories" then
                local max_s = hits.cat_max_scroll or 0
                cat_scroll = math.max(0, math.min(max_s, cat_scroll + dir))
            else
                local max_s = hits.max_scroll or 0
                scroll = math.max(0, math.min(max_s, scroll + dir))
            end

        elseif ev_type == "key" then
            local key = ev[2]

            if view_mode == "categories" then
                -- No key navigation in grid view (scroll only)
            else
                local active = get_active_items(st)
                if key == keys.up then
                    selected = math.max(1, selected - 1)
                    if selected <= scroll then scroll = selected - 1 end
                elseif key == keys.down then
                    selected = math.min(#active, selected + 1)
                    local list_h = hits.list_h or 10
                    if selected > scroll + list_h then scroll = selected - list_h end
                elseif key == keys.enter then
                    if #active > 0 and selected >= 1 and selected <= #active then
                        do_withdraw(ctx, active[selected], 1)
                    end
                elseif key == keys.backspace then
                    if view_mode == "category_detail" then
                        view_mode = "categories"
                        current_category = nil
                        scroll = 0
                        selected = 1
                    else
                        search_query = search_query:sub(1, -2)
                        scroll = 0
                        selected = 1
                    end
                end
            end

        elseif ev_type == "char" then
            if view_mode ~= "categories" then
                search_query = search_query .. ev[2]
                if view_mode == "category_detail" then
                    view_mode = "list"
                end
                scroll = 0
                selected = 1
            end
        end
    end
end

return app
