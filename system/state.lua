-- =============================================
-- WRAITH OS - GLOBAL SHARED STATE
-- =============================================

local state = {}

-- System
state.running = true
state.boot_time = os.clock()

-- Monitor
state.monitor = nil
state.monitor_name = ""
state.mon_w = 0
state.mon_h = 0

-- Window manager
state.windows = {}          -- ordered list (back to front z-order)
state.focused_id = nil      -- ID of focused window
state.next_window_id = 1    -- auto-incrementing window ID

-- Desktop
state.app_registry = {}     -- {id -> app_def}
state.app_order = {}        -- ordered list of app IDs for icon grid

-- Storage state
state.storage = {
    peripherals = {},
    names = {},
    output_peripheral = nil,
    depot_peripherals = {},
    items = {},
    item_count = 0,
    type_count = 0,
    ready = false,
    last_scan_time = 0,
    labels = {},
    stats = nil,
    available_peripherals = {},
    output_as_depot = false,
    extract_buffer = {},
    -- Smelting
    furnace_peripherals = {},
    smelting_enabled = false,
    furnace_count = 0,
    items_smelted = 0,
    items_pulled = 0,
    smelt_errors = 0,
    fuel_peripheral = nil,
    fuel_chest_target = 128,
    fuel_chest_level = 0,
    cached_fuel_total = 0,
    cached_smeltable_total = 0,
    -- Smelt rules & tasks
    smelt_rules = {},       -- {[idx] = {input, output, threshold, enabled, input_display, output_display}}
    smelt_tasks = {},       -- {[idx] = {input, target, smelted, active, input_display}}
    output_stock = {},      -- {[item_name] = count} for threshold checks
    -- Functions (set by storage service)
    extract = nil,
    import = nil,
    get_filtered = nil,
    get_stats = nil,
    get_stock_color = nil,
    toggle_smelting = nil,
    set_smelting = nil,
    get_smelting_stats = nil,
    setup_output = nil,
    clear_output = nil,
    add_depot = nil,
    remove_depot = nil,
    get_assignments = nil,
    toggle_output_depot = nil,
    setup_fuel = nil,
    clear_fuel = nil,
    list_peripherals = nil,
    set_label = nil,
    get_label = nil,
    get_all_labels = nil,
    get_armour_sets = nil,
    equip_armour = nil,
    -- Smelt rules/tasks functions
    add_smelt_rule = nil,
    remove_smelt_rule = nil,
    update_smelt_rule = nil,
    get_smelt_rules = nil,
    add_smelt_task = nil,
    cancel_smelt_task = nil,
    get_smelt_tasks = nil,
    clear_completed_tasks = nil,
}

-- Redstone state
state.redstone = {
    states = {},
    -- Functions (set by redstone service)
    set_output = nil,
    toggle_output = nil,
    get_output = nil,
    get_all_outputs = nil,
}

-- Network state
state.network = {
    modem_side = nil,
    ws_connection = nil,
    ws_connected = false,
    connected_clients = {},
    ready = false,
}

-- Analytics (populated by storage service)
state.analytics = {
    buckets = {},          -- minute-indexed: {extracted, imported, smelted_in, smelted_out, fuel_pushed}
    current_minute = 0,
    totals = {extracted = 0, imported = 0, smelted_in = 0, smelted_out = 0, fuel_pushed = 0},
    top_extracted = {},    -- {item_display_name -> count}
    top_imported = {},     -- {item_display_name -> count}
    top_craft_used = {},   -- {item_display_name -> count} ingredients consumed by crafting
    top_smelt_used = {},   -- {item_display_name -> count} ores consumed by smelting
    farm_items_supplied = {},  -- {item_name -> count}
    farm_items_harvested = {}, -- {item_name -> count}
    capacity_log = {},     -- {{time, pct}, ...}
    peak_items_min = 0,
}

-- MasterMine integration
state.mastermine = {
    hub_id = nil,
    hub_connected = false,
    hub_last_seen = 0,
    mining_on = false,
    turtles = {},
    mine_levels = {},
    ore_table = {},
    auto_mode = true,
    last_sync = 0,
    -- Map data (received from hub on demand)
    mine_data = {},
    available_levels = {},
    hub_config = nil,
    -- Map view state
    map_location = nil,
    map_zoom = 0,
    map_level_idx = 1,
    -- Functions (set by mastermine service)
    send_command = nil,
    set_hub = nil,
    toggle_auto = nil,
    update_ore = nil,
    force_sync = nil,
    set_ore_enabled = nil,
    set_ore_threshold = nil,
    set_ore_best_y = nil,
    request_mine_data = nil,
}

-- AR Goggles
state.ar = {
    controller = nil,
    controller_name = "",
    connected = false,
    enabled = true,
    ready = false,
    -- HUD section toggles
    hud = {
        show_storage = true,
        show_fuel = true,
        show_smelting = true,
        show_mining = true,
        show_projects = true,
        show_alerts = true,
        show_clock = true,
    },
    -- 3D world marker toggles
    world = {
        show_mine_entrance = true,
        show_turtles = true,
        show_project_blocks = false,
        show_pois = true,
    },
    -- Points of interest (user-defined 3D markers)
    pois = {},  -- {{name, x, y, z, color}, ...}
    -- Alert system
    alerts = {},
    alert_count = 0,
    max_alerts = 50,
    -- Functions (set by AR service)
    add_alert = nil,
    clear_alerts = nil,
    toggle_hud = nil,
    toggle_world = nil,
    add_poi = nil,
    remove_poi = nil,
    set_enabled = nil,
}

-- Projects
state.projects = {
    list = {},
    active_idx = nil,
    ready = false,
    -- Computed by projects service
    coverage = {},      -- {[proj_idx] = {[item_name] = {have, need, pct}}}
    needed_items = {},  -- {[item_name] = total_deficit}
    -- Functions (set by projects service)
    create = nil,
    delete = nil,
    rename = nil,
    add_item = nil,
    remove_item = nil,
    set_item_count = nil,
    set_active = nil,
    get_coverage = nil,
    recalculate = nil,
}

-- Lighting Controller
state.lighting = {
    -- Player detection
    detector = nil,
    detector_name = "",
    nearby_players = {},    -- {[username] = {x, y, z, distance}}
    -- Player themes: {[username] = {colors = {0-15, ...}, pattern = "solid"|"pulse"|"strobe"|"fade"}}
    player_themes = {},
    -- Controller registry: {[id] = {id, x, y, z, side, last_seen, online, current_color, current_pattern, assigned_player}}
    controllers = {},
    always_on = true,        -- keep lights at 15 when no player nearby (mob spawn prevention)
    ready = false,
    -- Functions (set by lighting service)
    set_theme = nil,
    remove_theme = nil,
    get_theme = nil,
    get_controllers = nil,
    get_nearby_players = nil,
    remove_controller = nil,
    toggle_always_on = nil,
}

-- Loadouts
state.loadouts = {
    managers = {},          -- {[periph_name] = {name, owner, online, buffer}}
    saved = {},             -- {[loadout_name] = {name, armor, inventory, hand, offhand}}
    buffer_barrels = {},    -- {[im_periph_name] = barrel_periph_name}
    ready = false,
    -- Functions (set by loadouts service)
    snapshot = nil,
    save_loadout = nil,
    delete_loadout = nil,
    rename_loadout = nil,
    equip = nil,
    strip = nil,
    get_inventory = nil,
    list_managers = nil,
    assign_buffer = nil,
    clear_buffer = nil,
    list_available_barrels = nil,
    quick_deposit = nil,
    has_depot_ready = nil,
    give_to_player = nil,
}

-- Farms
state.farms = {
    plots = {},
    ready = false,
    add_farm = nil,
    remove_farm = nil,
    update_farm = nil,
    get_farms = nil,
    add_supply = nil,
    remove_supply = nil,
    update_supply = nil,
    toggle_farm = nil,
    list_available_chests = nil,
    -- Tree farm clients
    tree_clients = {},          -- {[computer_id] = {id, label, fuel, fuel_limit, rounds, state, saplings, last_seen}}
    send_tree_command = nil,    -- function(client_id, cmd)
}

-- Crafting
state.crafting = {
    turtles = {},           -- {[idx] = {id, name, label, state, last_seen}}
    craft_rules = {},       -- {[idx] = {output, output_threshold, grid, ingredients, yield, enabled}}
    craft_tasks = {},       -- {[idx] = {rule_idx, target, crafted, active}}
    crafting_enabled = false,
    items_crafted = 0,
    ready = false,
    -- Functions (set by crafting service)
    add_rule = nil,
    remove_rule = nil,
    update_rule = nil,
    toggle_rule = nil,
    add_task = nil,
    cancel_task = nil,
    clear_completed_tasks = nil,
    toggle_crafting = nil,
    get_stats = nil,
}

-- Transport
state.transport = {
    stations = {},          -- {[id] = {id, label, x, y, z, is_hub, online, last_seen, rules, switches, storage_bays, rail_side, has_train, detector_side}}
    dispatches = {},        -- {{from_id, to_id, status, started}, ...} active dispatches
    hub_id = nil,
    ready = false,
    -- Logistics
    buffer_chest = nil,         -- peripheral name of trapped chest (Wraith side)
    buffer_periph = nil,        -- wrapped peripheral object
    allowed_items = {},         -- {[idx] = {item, display_name, min_keep}}
    fuel_item = nil,            -- override fuel item (nil = use config default)
    fuel_per_trip = nil,        -- override fuel count (nil = use config default)
    station_schedules = {},     -- {[station_id] = {[idx] = {type, items, period, last_run, enabled}}}
    last_trip_log = {},         -- recent trip log entries
    trip_durations = {},        -- {[station_id] = {duration_ms, ...}} last 5 per station
    -- Functions (set by transport service)
    register_station = nil,
    set_hub = nil,
    dispatch_train = nil,
    set_switch = nil,
    add_station_rule = nil,
    remove_station_rule = nil,
    update_station_rule = nil,
    get_route_map = nil,
    send_station_cmd = nil,
    remove_station = nil,
    -- Logistics functions
    set_buffer_chest = nil,
    clear_buffer_chest = nil,
    add_allowed_item = nil,
    remove_allowed_item = nil,
    update_allowed_item = nil,
    add_schedule = nil,
    remove_schedule = nil,
    update_schedule = nil,
    toggle_schedule = nil,
    execute_trip = nil,
    get_buffer_contents = nil,
    list_trapped_chests = nil,
}

-- Notifications / alerts
state.notifications = {}
state.status_msg = ""
state.status_color = nil
state.status_timeout = 0

return state
