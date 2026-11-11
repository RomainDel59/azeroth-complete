-- Quest progress.
--
-- The completed quests of the logged-in character are read from the client at login and
-- after every turn-in, and stored in its record, so that the account view can merge the
-- progress of every character. A "view" (tracking mode + faction) decides which quests
-- are visible and which completions count; statuses and totals are computed for a view
-- and cached until the progress changes.

local _, ns = ...

local Quests = ns:RegisterModule("Quests")

local Q, Flag, Status = ns.Const.Quest, ns.Const.QuestFlag, ns.Const.Status
local Tracking = ns.Const.Tracking
local NOT_COUNTED = Flag.REPEATABLE + Flag.DAILY + Flag.WEEKLY

local revision = 0 -- bumped on every progress change, invalidates the caches
local statsCache = {}
local mergedCompleted, mergedRevision

-------------------------------------------------------------------------------
-- Snapshot of the character's progress
-------------------------------------------------------------------------------

local function changed()
    revision = revision + 1
    statsCache = {}
    ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 0.3)
end

local MAX_SNAPSHOT_RETRIES = 3
local snapshotRetries = 0

function Quests:Snapshot()
    local completed, source = ns.Compat.GetCompletedQuests()
    if not source then
        ns.Log:Warn("The client exposes no list of completed quests; progress cannot be read")
        return
    end
    local record = ns.Database:Character()
    local count, known = 0, 0
    for questID in pairs(completed) do
        count = count + 1
        if ns.Data.Quests[questID] then known = known + 1 end
    end
    -- Right after login the client may not have received the list yet: an empty answer
    -- never replaces saved progress, it is asked again a little later.
    if count == 0 and next(record.quests) and snapshotRetries < MAX_SNAPSHOT_RETRIES then
        snapshotRetries = snapshotRetries + 1
        ns.Log:Info("Completed quest list empty (attempt %d); keeping the saved progress and retrying", snapshotRetries)
        C_Timer.After(5, function() ns:SafeCall("Quests.Snapshot", Quests.Snapshot, Quests) end)
        return
    end
    record.quests = completed
    ns.Log:Info("Completed quests read with %s: %d (%d in the catalogue)", source, count, known)
    changed()
end

function Quests:OnLogin()
    self:Snapshot()
end

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
    local record = ns.Database:Character()
    if record and questID then
        record.quests[questID] = true
        ns.Log:Debug("Quest %d turned in", questID)
        changed()
    end
end)

-- Accepting or abandoning a quest changes the displayed statuses, not the totals.
local function logChanged()
    ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 0.3)
end
ns:RegisterEvent("QUEST_ACCEPTED", logChanged)
ns:RegisterEvent("QUEST_REMOVED", logChanged)

-------------------------------------------------------------------------------
-- Views
-------------------------------------------------------------------------------

-- Returns the view of the current settings: { tracking, faction, key }.
function Quests:CurrentView(faction)
    local tracking = ns.Database:Settings().tracking
    faction = faction or ns.Player.faction
    return { tracking = tracking, faction = faction, key = tracking .. ":" .. tostring(faction) }
end

local function completedSet(view)
    if view.tracking ~= Tracking.ACCOUNT then
        return ns.Database:Character().quests
    end
    if mergedRevision ~= revision then
        mergedCompleted = {}
        for _, record in ns.Database:Characters() do
            for questID in pairs(record.quests or {}) do mergedCompleted[questID] = true end
        end
        mergedRevision = revision
    end
    return mergedCompleted
end

-- The character's own race and class apply in the character view of its own faction;
-- otherwise only the faction matters.
local function usesCharacterFilter(view)
    return view.tracking == Tracking.CHARACTER and view.faction == ns.Player.faction
end

function Quests:IsVisible(questID, view)
    local row = ns.Data.Quests[questID]
    if not row then return false end
    local races = row[Q.RACES]
    if usesCharacterFilter(view) then
        return ns.Player:CanRace(races) and ns.Player:CanClass(row[Q.CLASSES])
    end
    return races == 0 or ns.MasksIntersect(races, ns.Player:FactionRaces(view.faction))
end

function Quests:IsCounted(questID)
    local row = ns.Data.Quests[questID]
    return row ~= nil and Quests.FlagsExclude(row[Q.FLAGS], NOT_COUNTED)
end

-- True when none of the `excluded` flag bits is set in `flags`.
function Quests.FlagsExclude(flags, excluded)
    local bitValue = 1
    while bitValue <= excluded do
        if excluded % (bitValue * 2) >= bitValue and flags % (bitValue * 2) >= bitValue then return false end
        bitValue = bitValue * 2
    end
    return true
end

function Quests.HasFlag(flags, flag)
    return flags % (flag * 2) >= flag
end

local function allDone(list, completed)
    if not list then return true end
    for _, id in ipairs(list) do
        if not completed[id] then return false end
    end
    return true
end

local function anyDone(list, completed)
    if not list then return true end
    for _, id in ipairs(list) do
        if completed[id] then return true end
    end
    return false
end

-- Returns the status of a quest in a view and, for locked quests, the reason
-- ("level" or "prerequisite"); for closed alternatives, "exclusive" or "breadcrumb".
function Quests:Status(questID, view)
    local row = ns.Data.Quests[questID]
    local completed = completedSet(view)
    if completed[questID] then return Status.DONE end
    local flags = row[Q.FLAGS]
    if not Quests.FlagsExclude(flags, NOT_COUNTED) then return Status.REPEATABLE end
    if row[Q.EXCLUSIVE] and anyDone(row[Q.EXCLUSIVE], completed) then
        return Status.DONE, "exclusive"
    end
    local target = row[Q.BREADCRUMB_FOR]
    if target and completed[target] then return Status.DONE, "breadcrumb" end
    if ns.Compat.IsOnQuest(questID) then return Status.ACTIVE end
    if not allDone(row[Q.PRE_ALL], completed) or not anyDone(row[Q.PRE_ANY], completed) then
        return Status.LOCKED, "prerequisite"
    end
    if view.tracking == Tracking.CHARACTER and (ns.Player.level or 0) < row[Q.MIN_LEVEL] then
        return Status.LOCKED, "level"
    end
    return Status.AVAILABLE
end

-------------------------------------------------------------------------------
-- Totals
-------------------------------------------------------------------------------

-- Summarizes a chain for a view: visible quests, counted total, completed count, level range.
function Quests:ChainSummary(chain, view)
    local visible, done, total, low, high = {}, 0, 0, nil, nil
    for _, questID in ipairs(chain) do
        if self:IsVisible(questID, view) then
            visible[#visible + 1] = questID
            local row = ns.Data.Quests[questID]
            local level = row[Q.LEVEL]
            if level > 0 then
                low = math.min(low or level, level)
                high = math.max(high or level, level)
            end
            if Quests.FlagsExclude(row[Q.FLAGS], NOT_COUNTED) then
                total = total + 1
                if self:Status(questID, view) == Status.DONE then done = done + 1 end
            end
        end
    end
    return { quests = visible, done = done, total = total, low = low, high = high }
end

-- Totals of a list of chains (a zone, a category or an instance), cached per view.
function Quests:Summary(cacheKey, chains, view)
    local key = view.key .. "|" .. cacheKey
    local cached = statsCache[key]
    if cached then return cached end
    local done, total = 0, 0
    for _, chain in ipairs(chains) do
        local summary = self:ChainSummary(chain, view)
        done, total = done + summary.done, total + summary.total
    end
    cached = { done = done, total = total }
    statsCache[key] = cached
    return cached
end

-- Zones grouped by continent, each { kind, id, chains, levels, continent, uiMap }.
function Quests:Groups()
    if self.groups then return self.groups end
    local groups = {}
    local Continent = ns.Const.Continent
    for areaID, zone in pairs(ns.Data.Zones) do
        local continent = zone.continent or Continent.OTHER
        groups[continent] = groups[continent] or {}
        table.insert(groups[continent], { kind = "zone", id = areaID, chains = zone.chains, levels = zone.levels,
            continent = continent, uiMap = zone.uiMap, art = zone.art, icon = zone.icon })
    end
    -- Areas that only name a set of quests are already among the categories.
    groups[Continent.CATEGORIES] = groups[Continent.CATEGORIES] or {}
    for sortID, sort in pairs(ns.Data.QuestSorts) do
        table.insert(groups[Continent.CATEGORIES], { kind = "sort", id = sortID, chains = sort.chains,
            levels = sort.levels, continent = Continent.CATEGORIES })
    end
    self.groups = groups
    return groups
end

function Quests:GroupName(group)
    if group.kind == "sort" then
        return ns.Names.QuestSort(group.id) or (group.id == 0 and ns.L.QUESTS_MISC) or ns.L.QUESTS_MISC
    end
    return ns.Names.Area(group.id) or string.format("#%d", group.id)
end

function Quests:Revision()
    return revision
end
