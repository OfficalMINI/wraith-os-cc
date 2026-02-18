-- =============================================
-- WRAITH OS - PROJECTS SERVICE
-- =============================================
-- Manages project shopping lists and computes
-- item coverage against storage inventory.

local svc = {}

function svc.main(state, config, utils)
    local proj = state.projects
    local cfg = config.projects
    local SAVE_PATH = cfg.save_file or "wraith/projects_data.lua"

    -- ========================================
    -- Persistence
    -- ========================================
    local function load_projects()
        if fs.exists(SAVE_PATH) then
            local f = fs.open(SAVE_PATH, "r")
            if f then
                local data = f.readAll()
                f.close()
                local fn = loadstring("return " .. data)
                if fn then
                    local ok, saved = pcall(fn)
                    if ok and type(saved) == "table" then
                        proj.list = saved.list or {}
                        proj.active_idx = saved.active_idx
                        return true
                    end
                end
            end
        end
        return false
    end

    local function save_projects()
        local data = {
            list = proj.list,
            active_idx = proj.active_idx,
        }
        local ok, content = pcall(textutils.serialise, data)
        if not ok or not content or #content < 5 then return false end
        local tmp = SAVE_PATH .. ".tmp"
        local f = fs.open(tmp, "w")
        if f then
            f.write(content)
            f.close()
            if fs.exists(SAVE_PATH) then fs.delete(SAVE_PATH) end
            fs.move(tmp, SAVE_PATH)
            return true
        end
        return false
    end

    -- ========================================
    -- Coverage Calculation
    -- ========================================
    local function recalculate_coverage()
        local st = state.storage
        if not st.ready or not st.items then return end

        -- Build fast stock lookup: {item_name -> total_count}
        local stock = {}
        for _, item in ipairs(st.items) do
            stock[item.name] = (stock[item.name] or 0) + item.count
        end

        local needed = {}
        proj.coverage = {}

        for pi, project in ipairs(proj.list) do
            local cov = {}
            for _, pitem in ipairs(project.items) do
                local have = stock[pitem.name] or 0
                local need = pitem.need or 0
                local pct = need > 0 and math.min(1, have / need) or 1
                cov[pitem.name] = {
                    have = have,
                    need = need,
                    pct = pct,
                    displayName = pitem.displayName,
                }
                local deficit = math.max(0, need - have)
                if deficit > 0 then
                    needed[pitem.name] = (needed[pitem.name] or 0) + deficit
                end
            end
            proj.coverage[pi] = cov

            -- Check completion
            local all_met = true
            for _, c in pairs(cov) do
                if c.pct < 1 then all_met = false; break end
            end
            if all_met and #project.items > 0 and not project.completed then
                project.completed = true
                if state.ar and state.ar.add_alert then
                    state.ar.add_alert("Project complete: " .. project.name, "info", "projects")
                end
                utils.add_notification(state, "PROJECT COMPLETE: " .. project.name, colors.lime)
            elseif not all_met then
                project.completed = false
            end
        end

        proj.needed_items = needed
    end

    -- ========================================
    -- Exposed Functions
    -- ========================================
    proj.create = function(name)
        table.insert(proj.list, {
            name = name,
            created = os.clock(),
            items = {},
            completed = false,
        })
        save_projects()
        recalculate_coverage()
        return #proj.list
    end

    proj.delete = function(idx)
        if not proj.list[idx] then return false end
        table.remove(proj.list, idx)
        if proj.active_idx == idx then
            proj.active_idx = nil
        elseif proj.active_idx and proj.active_idx > idx then
            proj.active_idx = proj.active_idx - 1
        end
        save_projects()
        recalculate_coverage()
        return true
    end

    proj.rename = function(idx, name)
        if not proj.list[idx] then return false end
        proj.list[idx].name = name
        save_projects()
        return true
    end

    proj.add_item = function(proj_idx, item_name, display_name, count)
        local project = proj.list[proj_idx]
        if not project then return false end
        -- Merge if item already exists
        for _, existing in ipairs(project.items) do
            if existing.name == item_name then
                existing.need = existing.need + (count or 1)
                save_projects()
                recalculate_coverage()
                return true
            end
        end
        table.insert(project.items, {
            name = item_name,
            displayName = display_name or utils.clean_name(item_name),
            need = count or 1,
        })
        save_projects()
        recalculate_coverage()
        return true
    end

    proj.remove_item = function(proj_idx, item_idx)
        local project = proj.list[proj_idx]
        if project and project.items[item_idx] then
            table.remove(project.items, item_idx)
            save_projects()
            recalculate_coverage()
            return true
        end
        return false
    end

    proj.set_item_count = function(proj_idx, item_idx, count)
        local project = proj.list[proj_idx]
        if project and project.items[item_idx] then
            project.items[item_idx].need = math.max(1, count)
            save_projects()
            recalculate_coverage()
            return true
        end
        return false
    end

    proj.set_active = function(idx)
        proj.active_idx = idx
        save_projects()
    end

    proj.get_coverage = function(proj_idx)
        return proj.coverage[proj_idx] or {}
    end

    proj.recalculate = recalculate_coverage

    -- ========================================
    -- Init & Main Loop
    -- ========================================
    load_projects()
    proj.ready = true

    -- Wait for storage to be ready
    while not state.storage.ready and state.running do
        sleep(1)
    end

    recalculate_coverage()
    utils.add_notification(state,
        string.format("PROJECTS: %d projects loaded", #proj.list), colors.cyan)

    -- Periodic recalculation
    local recalc_timer = os.startTimer(cfg.recalc_interval or 5)

    while state.running do
        local ev, p1 = os.pullEvent()
        if ev == "timer" and p1 == recalc_timer then
            recalculate_coverage()
            recalc_timer = os.startTimer(cfg.recalc_interval or 5)
        end
    end
end

return svc
