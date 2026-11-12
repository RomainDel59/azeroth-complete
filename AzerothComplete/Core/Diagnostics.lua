-- Startup diagnostics: records in the log which client APIs exist, so that a feature that
-- misbehaves on the Forever client can be traced to a missing function from the log alone.

local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

-- Dotted paths of the APIs the addon can use; "|" separates alternatives.
local PROBES = {
    { "Completed quests", "C_QuestLog.GetAllCompletedQuestIDs|GetQuestsCompleted" },
    { "Quest titles", "C_QuestLog.GetTitleForQuestID|C_QuestLog.GetQuestInfo" },
    { "Quest data requests", "C_QuestLog.RequestLoadQuestByID" },
    { "Quest log lookup", "C_QuestLog.IsOnQuest|C_QuestLog.GetLogIndexForQuestID|GetQuestLogIndexByID" },
    { "Quest objectives", "C_QuestLog.GetQuestObjectives" },
    { "Item names", "C_Item.GetItemNameByID|C_Item.GetItemInfo|GetItemInfo" },
    { "Item data requests", "C_Item.RequestLoadItemDataByID" },
    { "Spell names", "C_Spell.GetSpellName|GetSpellInfo" },
    { "Spell data requests", "C_Spell.RequestLoadSpellData" },
    { "Known spells", "C_SpellBook.IsSpellKnown|IsPlayerSpell|IsSpellKnown" },
    { "Professions", "GetProfessions|GetNumSkillLines" },
    { "Area names", "C_Map.GetAreaInfo" },
    { "Class names", "GetClassInfo" },
    { "Map art", "C_Map.GetMapArtLayerTextures" },
    { "Player map", "C_Map.GetBestMapForUnit" },
    { "Map hierarchy", "C_Map.GetMapInfo" },
    { "Waypoints", "C_Map.SetUserWaypoint" },
    { "Tooltip data", "C_TooltipInfo.GetHyperlink" },
    { "Factions", "C_Reputation.GetFactionDataByID|GetFactionInfoByID" },
    { "Mount journal", "C_MountJournal.GetMountIDs|C_MountJournal.GetMountInfoByID" },
    { "Pet journal", "C_PetJournal.GetPetInfoBySpeciesID" },
    { "Toy box", "C_ToyBox.GetToyInfo|PlayerHasToy" },
    { "Appearance sets", "C_TransmogSets.GetSetInfo" },
    { "Titles", "GetTitleName" },
    { "Achievements", "GetCategoryList|GetAchievementInfo" },
    { "Saved instances", "GetNumSavedInstances" },
    { "Addon compartment", "AddonCompartmentFrame" },
}

local function resolve(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

-- Returns the first available alternative of a probe, or nil.
function Diagnostics.Find(alternatives)
    for path in alternatives:gmatch("[^|]+") do
        if resolve(path) ~= nil then return path end
    end
    return nil
end

function Diagnostics:Run()
    local missing = {}
    for _, probe in ipairs(PROBES) do
        local found = self.Find(probe[2])
        if found then
            ns.Log:Debug("API %-20s -> %s", probe[1], found)
        else
            missing[#missing + 1] = probe[1]
        end
    end
    if #missing > 0 then
        ns.Log:Info("Unavailable APIs: %s", table.concat(missing, ", "))
    else
        ns.Log:Info("Every probed API is available")
    end
    local data = ns.Data
    ns.Log:Info("Data: build %s, %d quests, %d professions, %d instances", tostring(data.Build),
        self.Count(data.Quests), self.Count(data.Professions), self.Count(data.Instances))
end

-- Full report for /azc diag, printed to the chat and written to the log.
function Diagnostics:Report()
    local lines = { string.format("Version %s, client %s, locale %s", ns.Compat.GetAddOnVersion(),
        ns.Compat.GetClientBuild(), GetLocale()) }
    for _, probe in ipairs(PROBES) do
        lines[#lines + 1] = string.format("%s: %s", probe[1], self.Find(probe[2]) or "MISSING")
    end
    local requested, received, fallbacks, pending = ns.Names.Stats()
    lines[#lines + 1] = string.format("Texts: %d requested, %d received, %d fallbacks, %d pending",
        requested, received, fallbacks, pending)
    lines[#lines + 1] = string.format("Characters known: %d", ns.Database:CountCharacters())
    for _, line in ipairs(lines) do ns.Log:Info("diag: %s", line) end
    return lines
end

function Diagnostics.Count(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end
