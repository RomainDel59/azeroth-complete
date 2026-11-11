-- Dungeons and raids: defeated bosses and instance quests.
--
-- A boss counts as defeated once the character has won its encounter (ENCOUNTER_END) or
-- when a current lockout reports it killed. Both are stored in the character's record.

local _, ns = ...

local Instances = ns:RegisterModule("Instances")

local Kind = ns.Const.Instance
local Tracking = ns.Const.Tracking

-- Instances of one kind (dungeon or raid), sorted by level then name.
function Instances:List(kind)
    self.lists = self.lists or {}
    if self.lists[kind] then return self.lists[kind] end
    local list = {}
    for mapID, instance in pairs(ns.Data.Instances) do
        if instance.kind == kind then
            list[#list + 1] = { mapID = mapID, area = instance.area, art = instance.art, artFramed = instance.artFramed,
                bosses = instance.bosses,
                chains = instance.chains, levels = instance.levels, players = instance.players, kind = kind }
        end
    end
    table.sort(list, function(a, b)
        local la, lb = a.levels and a.levels[1] or 99, b.levels and b.levels[1] or 99
        if la ~= lb then return la < lb end
        return (self:Name(a) or "") < (self:Name(b) or "")
    end)
    self.lists[kind] = list
    return list
end

function Instances:Name(instance)
    return ns.Names.Instance(instance.mapID, instance.area) or string.format("#%d", instance.mapID)
end

-- Set of defeated encounters for a tracking mode.
local mergedDefeated -- account-wide set, rebuilt after each progress change

function Instances:Defeated(tracking)
    if tracking ~= Tracking.ACCOUNT then return ns.Database:Character().bosses end
    if not mergedDefeated then
        mergedDefeated = {}
        for _, record in ns.Database:Characters() do
            for encounterID in pairs(record.bosses or {}) do mergedDefeated[encounterID] = true end
        end
    end
    return mergedDefeated
end

ns:RegisterMessage("AC_PROGRESS_CHANGED", function() mergedDefeated = nil end)

function Instances:Summary(instance, view)
    local defeated = self:Defeated(view.tracking)
    local bossesDone = 0
    for _, encounterID in ipairs(instance.bosses) do
        if defeated[encounterID] then bossesDone = bossesDone + 1 end
    end
    local quests = ns.Quests:Summary("instance:" .. instance.mapID, instance.chains, view)
    return { bossesDone = bossesDone, bosses = #instance.bosses, questsDone = quests.done, quests = quests.total,
        done = bossesDone + quests.done, total = #instance.bosses + quests.total }
end

-------------------------------------------------------------------------------
-- Reading the character
-------------------------------------------------------------------------------

local function encounterByName(instance, bossName)
    for _, encounterID in ipairs(instance.bosses) do
        if ns.Names.Encounter(encounterID) == bossName then return encounterID end
    end
    return nil
end

function Instances:ReadLockouts()
    if not (GetNumSavedInstances and GetSavedInstanceInfo and GetSavedInstanceEncounterInfo) then return end
    local record = ns.Database:Character()
    local marked = 0
    for i = 1, GetNumSavedInstances() do
        local name, _, _, _, locked, _, _, _, _, _, numEncounters, _, _, instanceID = GetSavedInstanceInfo(i)
        if locked and name then
            for _, kind in pairs(Kind) do
                for _, instance in ipairs(self:List(kind)) do
                    -- The instance id identifies the map; older clients only give the name.
                    if (instanceID and instanceID == instance.mapID) or (not instanceID and self:Name(instance) == name) then
                        for j = 1, numEncounters or 0 do
                            local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, j)
                            local encounterID = isKilled and encounterByName(instance, bossName)
                            if encounterID and not record.bosses[encounterID] then
                                record.bosses[encounterID] = true
                                marked = marked + 1
                                mergedDefeated = nil
                            end
                        end
                    end
                end
            end
        end
    end
    if marked > 0 then
        ns.Log:Info("Lockouts: %d defeated bosses recorded", marked)
        ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 0.3)
    end
end

function Instances:OnLogin()
    if RequestRaidInfo then RequestRaidInfo() end
end

ns:RegisterEvent("UPDATE_INSTANCE_INFO", function() Instances:ReadLockouts() end)

ns:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName, _, _, success)
    if success ~= 1 and success ~= true then return end
    local record = ns.Database:Character()
    if record and encounterID then
        record.bosses[encounterID] = true
        ns.Log:Info("Encounter %d (%s) defeated", encounterID, tostring(encounterName))
        ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 0.3)
    end
end)
