-- Minimal internal MIST compatibility layer for Skynet IADS
-- Provides only the functions and tables Skynet uses from MIST.

if not mist then
    mist = {}
end

-- Utils subtable
mist.utils = mist.utils or {}

-- Rounding with optional decimals (defaults to 0)
function mist.utils.round(value, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    if value >= 0 then
        return math.floor(value * mult + 0.5) / mult
    else
        return math.ceil(value * mult - 0.5) / mult
    end
end

-- Converts meters to nautical miles
function mist.utils.metersToNM(meters)
    return meters / 1852
end

-- Converts meters to feet
function mist.utils.metersToFeet(meters)
    return meters * 3.280839895
end

-- Convert radians to degrees
function mist.utils.toDegree(rad)
    return rad * (180 / math.pi)
end

-- 2D distance (XZ-plane)
function mist.utils.get2DDist(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dz * dz)
end

-- 3D distance
function mist.utils.get3DDist(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Heading from point a to point b in radians (0..2*pi), 0 = north
function mist.utils.getHeadingPoints(a, b)
    local dx = (b.x or 0) - (a.x or 0)
    local dz = (b.z or 0) - (a.z or 0)
    local heading = math.atan2(dx, dz)
    if heading < 0 then heading = heading + 2 * math.pi end
    return heading
end

-- Heading of a DCS Unit in radians (0..2*pi), 0 = north
function mist.getHeading(dcsObject)
    if not dcsObject or not dcsObject.getPosition then return 0 end
    local pos = dcsObject:getPosition()
    if not pos or not pos.x then return 0 end
    local fwd = pos.x -- forward vector of the object in world space
    local heading = math.atan2(fwd.x or 0, fwd.z or 0)
    if heading < 0 then heading = heading + 2 * math.pi end
    return heading
end

-- Random integer between a and b inclusive
function mist.random(a, b)
    if a == nil and b == nil then
        return math.random()
    end
    if b == nil then
        return math.random(1, a)
    end
    return math.random(a, b)
end

-- Minimal DBs with groupsByName and unitsByName populated from env.mission
mist.DBs = mist.DBs or {}
mist.DBs.unitsByName = mist.DBs.unitsByName or {}
mist.DBs.groupsByName = mist.DBs.groupsByName or {}

-- Removal helpers for keeping DBs in sync with runtime
function mist.DBs.removeUnitByName(name)
    if name and mist.DBs.unitsByName then
        mist.DBs.unitsByName[name] = nil
    end
end

local function _allGroupUnitsRemoved(groupName)
    local grp = mist.DBs.groupsByName and mist.DBs.groupsByName[groupName]
    if not grp or not grp.units then return true end
    for _, u in ipairs(grp.units) do
        if u and u.name and mist.DBs.unitsByName[u.name] ~= nil then
            return false
        end
    end
    return true
end

function mist.DBs.removeGroupIfEmpty(groupName)
    if groupName and mist.DBs.groupsByName and _allGroupUnitsRemoved(groupName) then
        mist.DBs.groupsByName[groupName] = nil
    end
end

local function _skynet_iads_build_dbs()
    if not env or not env.mission or not env.mission.coalition then
        return
    end
    local coalitions = { 'blue', 'red', 'neutrals' }
    local categories = { 'plane', 'helicopter', 'vehicle', 'ship', 'static' }
    for _, coalName in ipairs(coalitions) do
        local coalTbl = env.mission.coalition[coalName]
        if coalTbl and coalTbl.country then
            for _, country in ipairs(coalTbl.country) do
                for _, cat in ipairs(categories) do
                    local catTbl = country[cat]
                    if catTbl and catTbl.group then
                        for _, grp in ipairs(catTbl.group) do
                            if grp and grp.name then
                                mist.DBs.groupsByName[grp.name] = grp
                                if grp.units then
                                    for _, unit in ipairs(grp.units) do
                                        if unit and unit.name then
                                            mist.DBs.unitsByName[unit.name] = unit
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Build DBs immediately on load (mission start)
_skynet_iads_build_dbs()

-- Safe accessors that prune DB when DCS returns nil
function mist.safeGetUnitByName(name)
    if not name then return nil end
    local u = Unit.getByName and Unit.getByName(name) or nil
    if not u then
        mist.DBs.removeUnitByName(name)
    end
    return u
end

function mist.safeGetGroupByName(name)
    if not name then return nil end
    local g = Group.getByName and Group.getByName(name) or nil
    if not g then
        -- if group no longer resolves, try pruning if its units are gone
        mist.DBs.removeGroupIfEmpty(name)
    end
    return g
end

-- Scheduling wrappers
-- Schedules a function after startDelay seconds and repeats every interval seconds if provided.
-- Returns a timer id that can be passed to mist.removeFunction.
function mist.scheduleFunction(fn, args, startDelay, interval)
    args = args or {}
    startDelay = startDelay or 0
    local startTime = (timer and timer.getTime and timer.getTime()) or 0
    local function wrapper(_, t)
        fn(unpack(args))
        if interval and interval > 0 then
            return t + interval
        end
        return nil
    end
    if timer and timer.scheduleFunction then
        return timer.scheduleFunction(wrapper, {}, startTime + startDelay)
    else
        -- Fallback no-op when timer is unavailable (e.g. during static analysis)
        return nil
    end
end

function mist.removeFunction(id)
    if timer and timer.removeFunction and id then
        timer.removeFunction(id)
    end
end

-- Runtime pruning via world event handler: S_EVENT_DEAD (id = 8)
if world and world.addEventHandler and world.event and world.event.S_EVENT_DEAD then
    local _mist_db_event_handler = {}
    function _mist_db_event_handler:onEvent(event)
        if not event then return end
        if event.id == world.event.S_EVENT_DEAD and event.initiator and event.initiator.getName then
            local unitName = event.initiator:getName()
            if unitName and unitName ~= '' then
                mist.DBs.removeUnitByName(unitName)
                -- attempt to prune empty group
                local ok, groupObj = pcall(function() return event.initiator:getGroup() end)
                if ok and groupObj and groupObj.getName then
                    local groupName = groupObj:getName()
                    mist.DBs.removeGroupIfEmpty(groupName)
                end
            end
        end
    end
    world.addEventHandler(_mist_db_event_handler)
end
