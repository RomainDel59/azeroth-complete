-- Progress of each tab and of the whole. A tab counts what it lists for the current view,
-- as its own totals do; the whole is the mean of the tabs' fractions, so that every domain
-- weighs the same whatever its number of entries. A tab without anything to count (an API
-- the client lacks) is left out of the mean.

local _, ns = ...

local Progress = {}
ns.Progress = Progress

Progress.TABS = { "quests", "professions", "dungeons", "raids", "achievements", "collections" }

local counters = {}

function counters.quests(view)
    local done, total = 0, 0
    for _, groups in pairs(ns.Quests:Groups()) do
        for _, group in ipairs(groups) do
            local summary = ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, view)
            done, total = done + summary.done, total + summary.total
        end
    end
    return { done = done, total = total }
end

function counters.professions(view)
    local known = ns.Professions:Known(view.tracking)
    local done, total = 0, 0
    for _, profession in ipairs(ns.Professions:Shown(view)) do
        local summary = ns.Professions:Summary(profession.skillLine, known)
        done, total = done + summary.done, total + summary.total
    end
    return { done = done, total = total }
end

local function instances(kind)
    return function(view)
        local done, total = 0, 0
        for _, instance in ipairs(ns.Instances:List(kind)) do
            local summary = ns.Instances:Summary(instance, view)
            done, total = done + summary.done, total + summary.total
        end
        return { done = done, total = total }
    end
end
counters.dungeons = instances(ns.Const.Instance.DUNGEON)
counters.raids = instances(ns.Const.Instance.RAID)

function counters.achievements(view)
    if not ns.Achievements:Available() then return { done = 0, total = 0 } end
    local categories = ns.Achievements:Categories()
    local hidden = ns.Achievements:OutOfReach(categories, view)
    local done, total = 0, 0
    for _, category in ipairs(categories) do
        if not hidden[category.id] then
            local summary = ns.Achievements:Summary(category, view.tracking)
            done, total = done + summary.done, total + summary.total
        end
    end
    return { done = done, total = total }
end

function counters.collections()
    local done, total = 0, 0
    for _, kind in ipairs(ns.Collections.KINDS) do
        local summary = ns.Collections:Summary(kind)
        done, total = done + summary.done, total + summary.total
    end
    return { done = done, total = total }
end

local cache = {}
local function invalidate() cache = {} end
ns:RegisterMessage("AC_PROGRESS_CHANGED", invalidate)
ns:RegisterMessage("AC_NAMES_UPDATED", invalidate)
ns:RegisterMessage("AC_COLLECTIONS_CHANGED", invalidate)

-- { [tab] = { done, total }, overall = fraction or nil } for the view, computed once until
-- progress changes.
function Progress:Compute(view)
    if cache[view.key] then return cache[view.key] end
    local result = {}
    local sum, counted = 0, 0
    for _, tab in ipairs(self.TABS) do
        local counts = ns:SafeCall("Progress." .. tab, counters[tab], view) or { done = 0, total = 0 }
        result[tab] = counts
        if counts.total > 0 then
            sum, counted = sum + counts.done / counts.total, counted + 1
        end
    end
    result.overall = counted > 0 and sum / counted or nil
    cache[view.key] = result
    return result
end
