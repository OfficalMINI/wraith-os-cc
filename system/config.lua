-- =============================================
-- WRAITH OS - SYSTEM CONFIGURATION
-- =============================================

local config = {}

---==[ IDENTITY ]==---
config.name = "Wraith OS"
config.version = "1.0.0"

---==[ MONITOR ]==---
config.monitor = {
    text_scale = 0.5,
    refresh_rate = 0.15,
}

---==[ DESKTOP ]==---
config.desktop = {
    icon_cell_w = 14,
    icon_cell_h = 6,
    icon_cols = 5,
    icon_rows = 4,
    icon_margin_x = 2,
    icon_margin_y = 2,
}

---==[ WINDOW DEFAULTS ]==---
config.window = {
    titlebar_h = 1,
    min_w = 20,
    min_h = 8,
    default_w = 45,
    default_h = 22,
}

---==[ STORAGE ]==---
config.storage = {
    output_chest = nil,
    input_depots = {},
    auto_import_interval = 1,
    storage_types = {
        "minecraft:chest",
        "minecraft:shulker_box",
    },
    excluded_types = {
        "minecraft:trapped_chest",  -- reserved for transport buffer
    },
    storage_patterns = { "chest", "shulker", "crate", "drawer" },
    bridge_types = { "meBridge", "rsBridge" },
    scan_interval = 1,
    import_interval = 0.2,
    low_stock_threshold = 64,
    critical_stock_threshold = 16,
}

---==[ SMELTING ]==---
config.smelting = {
    enabled = false,
    furnace_patterns = { "furnace", "smoker", "blast" },
    smelt_interval = 2,
    auto_pull_output = true,
    auto_push_input = true,
    auto_push_fuel = true,
    batch_size = 8,
    fuel_threshold = 32,
    fuel_reserve = 128,         -- keep at least this many fuel items in main storage
    fuel_items = {
        "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block",
        "minecraft:dried_kelp_block", "minecraft:blaze_rod", "minecraft:lava_bucket",
    },
    smeltable_items = {
        "minecraft:raw_iron", "minecraft:raw_gold",
        "minecraft:raw_copper", "minecraft:ancient_debris",
    },
}

---==[ REDSTONE ]==---
config.redstone_outputs = {}

---==[ DROPPERS / ARMOUR ]==---
config.armour_sets = {}

---==[ NETWORK ]==---
config.network = {
    protocols = {
        base_command  = "wraith_cmd",
        base_status   = "wraith_status",
        base_storage  = "wraith_storage",
        base_ping     = "wraith_ping",
    },
    websocket = {
        enabled = false,
        url = nil,
        reconnect_interval = 10,
        heartbeat_interval = 5,
    },
    discovery_interval = 10,
}

---==[ MASTERMINE ]==---
config.mastermine = {
    protocols = {
        ping   = "wraith_mine_ping",
        status = "wraith_mine_status",
        config_msg = "wraith_mine_config",
        command = "wraith_mine_cmd",
        ack    = "wraith_mine_ack",
        data_req  = "wraith_mine_data",
        data_resp = "wraith_mine_data_resp",
    },
    status_interval = 5,
    sync_interval = 30,
    hub_timeout = 15,
    default_ore_table = {
        {name = "Iron",     item = "minecraft:raw_iron",       smelts_to = "minecraft:iron_ingot",   best_y = 16,   min_y = -64, max_y = 256, threshold = 256, enabled = true},
        {name = "Diamond",  item = "minecraft:diamond",        best_y = -59,  min_y = -64, max_y = 16,  threshold = 64,  enabled = true},
        {name = "Gold",     item = "minecraft:raw_gold",       smelts_to = "minecraft:gold_ingot",   best_y = -16,  min_y = -64, max_y = 32,  threshold = 128, enabled = true},
        {name = "Copper",   item = "minecraft:raw_copper",     smelts_to = "minecraft:copper_ingot", best_y = 48,   min_y = -16, max_y = 112, threshold = 256, enabled = true},
        {name = "Redstone", item = "minecraft:redstone",       best_y = -59,  min_y = -64, max_y = 16,  threshold = 256, enabled = true},
        {name = "Lapis",    item = "minecraft:lapis_lazuli",   best_y = 0,    min_y = -64, max_y = 64,  threshold = 128, enabled = true},
        {name = "Coal",     item = "minecraft:coal",           best_y = 96,   min_y = 0,   max_y = 256, threshold = 512, enabled = true},
        {name = "Emerald",  item = "minecraft:emerald",        best_y = 235,  min_y = -16, max_y = 256, threshold = 64,  enabled = true},
    },
}

---==[ AR GOGGLES ]==---
config.ar = {
    refresh_interval = 1,
    alert_display_count = 3,
    alert_duration = 30,
    hud_x_offset = 5,
    hud_y_offset = 5,
    hud_line_spacing = 12,
    -- Ribbon layout
    hud_panel_width = 450,  -- ribbon width (px)
    hud_bottom_y = 210,     -- bottom ribbon Y position (tune to your resolution)
    -- ARGB colors (Catppuccin Mocha)
    hud_color   = 0xFFCDD6F4,   -- default text
    hud_accent  = 0xFF89B4FA,   -- primary accent (blue)
    hud_accent2 = 0xFFCBA6F7,   -- secondary accent (lavender)
    hud_success = 0xFFA6E3A1,   -- green
    hud_warning = 0xFFFAB387,   -- orange
    hud_danger  = 0xFFF38BA8,   -- red
    hud_dim     = 0xFF45475A,   -- muted gray
    -- Sci-fi panel colors
    hud_bg_color      = 0xB0181825, -- semi-transparent dark background
    hud_frame_color   = 0xFF313244, -- subtle frame/divider
    hud_section_color = 0xFFCBA6F7, -- lavender section headers
    hud_scan_color    = 0x30899BF4, -- very subtle scan line
    -- 3D marker config
    marker_text_size = 0.5,
    marker_size = 1,
    beam_height = 8,
    turtle_marker_color  = 0xFFF9E2AF,
    mine_marker_color    = 0xFF89B4FA,
    poi_default_color    = 0xFFCBA6F7,
    project_block_color  = 0xFFA6E3A1,
    beam_color           = 0x6089B4FA, -- semi-transparent beam
}

---==[ PROJECTS ]==---
config.projects = {
    save_file = "wraith/projects_data.lua",
    recalc_interval = 5,
}

---==[ LIGHTING ]==---
config.lighting = {
    protocols = {
        ping      = "wraith_light_ping",
        status    = "wraith_light_status",
        register  = "wraith_light_register",
        command   = "wraith_light_cmd",
        heartbeat = "wraith_light_hb",
    },
    detection_range = 32,
    poll_interval = 1,
    command_interval = 0.5,
    heartbeat_timeout = 15,
    proximity_radius = 20,
    max_colors_per_theme = 3,
    multi_player_cycle = 3,     -- seconds between player cycling
    save_file = "wraith/lighting_data.lua",
}

---==[ LOADOUTS ]==---
config.loadouts = {
    save_file = "wraith/loadouts_data.lua",
    scan_interval = 5,
    equip_delay = 0.05,
    buffer_direction = "bottom",  -- barrel sits below IM
}

---==[ FARMS ]==---
config.farms = {
    enabled = true,
    cycle_interval = 2,
    chest_patterns = {"chest", "shulker", "crate", "drawer", "barrel"},
    tree_channels = {
        ping    = 7401,
        status  = 7402,
        command = 7403,
        result  = 7404,
    },
    tree_heartbeat_timeout = 30,
}

---==[ CRAFTING ]==---
config.crafting = {
    enabled = false,
    tick_interval = 3,
    max_batch = 64,
    protocols = {
        ping    = "wraith_craft_ping",
        status  = "wraith_craft_status",
        command = "wraith_craft_cmd",
        result  = "wraith_craft_result",
    },
    save_file = "wraith/crafting_config.lua",
}

---==[ TRANSPORT ]==---
config.transport = {
    enabled = true,
    protocols = {
        station_ping      = "wraith_rail_st_ping",
        station_status    = "wraith_rail_st_status",
        station_register  = "wraith_rail_st_register",
        station_command   = "wraith_rail_st_cmd",
        station_heartbeat = "wraith_rail_st_hb",
    },
    heartbeat_timeout = 15,
    status_interval = 5,
    dispatch_pulse_duration = 1.5,
    save_file = "wraith/transport_data.lua",
    -- Logistics
    fuel_item = "minecraft:coal",
    fuel_per_trip = 8,
    period_presets = {
        {label = "5 min",   seconds = 300},
        {label = "15 min",  seconds = 900},
        {label = "30 min",  seconds = 1800},
        {label = "Hourly",  seconds = 3600},
        {label = "4 Hours", seconds = 14400},
        {label = "Daily",   seconds = 86400},
    },
}

---==[ CLIENT UPDATER ]==---
config.updater = {
    enabled = true,
    client_dir = "wraith/clients",
    protocols = {
        update_ping = "wraith_update_ping",
        update_push = "wraith_update_push",
        update_ack  = "wraith_update_ack",
    },
}

return config
