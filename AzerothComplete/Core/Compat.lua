-- Client API wrappers.
--
-- The Forever client is built on the modern engine but does not expose every retail API,
-- and some functions exist under their legacy global name only. Each wrapper picks the
-- first available implementation, so the rest of the addon calls one stable function and
-- never tests for an API itself. Diagnostics.lua logs which implementations exist.

local _, ns = ...

local Compat = {}
ns.Compat = Compat

local function pick(...)
    for i = 1, select("#", ...) do
        local fn = select(i, ...)
        if type(fn) == "function" then return fn end
    end
    return nil
end

local C_AddOns, C_QuestLog, C_Item, C_Spell, C_Map = C_AddOns, C_QuestLog, C_Item, C_Spell, C_Map
local C_TooltipInfo, C_Reputation = C_TooltipInfo, C_Reputation

-------------------------------------------------------------------------------
-- Client
-------------------------------------------------------------------------------

local getMetadata = pick(C_AddOns and C_AddOns.GetAddOnMetadata, GetAddOnMetadata)

function Compat.GetAddOnVersion()
    local version = getMetadata and getMetadata(ns.ADDON_NAME, "Version")
    if not version or version:find("@", 1, true) then return "dev" end
    return version
end

function Compat.GetClientBuild()
    local version, build = GetBuildInfo()
    return string.format("%s.%s", tostring(version), tostring(build))
end

-------------------------------------------------------------------------------
-- Quests
-------------------------------------------------------------------------------

-- Returns a set {[questID] = true} of every quest the character has turned in.
function Compat.GetCompletedQuests()
    local result = {}
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        for _, questID in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do result[questID] = true end
        return result, "C_QuestLog.GetAllCompletedQuestIDs"
    end
    if GetQuestsCompleted then
        local completed = GetQuestsCompleted()
        if type(completed) == "table" then
            for questID in pairs(completed) do result[questID] = true end
        end
        return result, "GetQuestsCompleted"
    end
    return result, nil
end

local isQuestFlaggedCompleted = pick(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, IsQuestFlaggedCompleted)
function Compat.IsQuestCompleted(questID)
    return isQuestFlaggedCompleted and isQuestFlaggedCompleted(questID) or false
end

local getLogIndex = pick(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, GetQuestLogIndexByID)
function Compat.IsOnQuest(questID)
    if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(questID) end
    local index = getLogIndex and getLogIndex(questID)
    return index ~= nil and index > 0
end

-- Returns the title the client knows for a quest, or nil when it is not cached yet.
function Compat.GetQuestTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title and title ~= "" then return title end
    end
    if C_QuestLog and C_QuestLog.GetQuestInfo then
        local title = C_QuestLog.GetQuestInfo(questID)
        if type(title) == "string" and title ~= "" then return title end
    end
    return nil
end

-- Asks the server for a quest's data; QUEST_DATA_LOAD_RESULT reports the answer.
-- Returns false when the client cannot request quest data at all.
function Compat.RequestQuestData(questID)
    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(questID)
        return true
    end
    return false
end

-- Objectives of a quest in the log: { { text, finished }, ... } or nil.
function Compat.GetQuestObjectives(questID)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local objectives = C_QuestLog.GetQuestObjectives(questID)
        if objectives and #objectives > 0 then
            local result = {}
            for _, objective in ipairs(objectives) do
                result[#result + 1] = { text = objective.text, finished = objective.finished }
            end
            return result
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Items and spells
-------------------------------------------------------------------------------

local getItemNameByID = pick(C_Item and C_Item.GetItemNameByID)
local getItemInfo = pick(C_Item and C_Item.GetItemInfo, GetItemInfo)
local getItemIcon = pick(C_Item and C_Item.GetItemIconByID, GetItemIcon)
local getItemInfoInstant = pick(C_Item and C_Item.GetItemInfoInstant, GetItemInfoInstant)

function Compat.GetItemName(itemID)
    local name = getItemNameByID and getItemNameByID(itemID)
    if not name and getItemInfo then name = getItemInfo(itemID) end
    if name == "" then return nil end
    return name
end

-- Item quality (0 poor .. 5 legendary) when cached.
function Compat.GetItemQuality(itemID)
    if C_Item and C_Item.GetItemQualityByID then return C_Item.GetItemQualityByID(itemID) end
    if getItemInfo then return select(3, getItemInfo(itemID)) end
    return nil
end

function Compat.GetItemIcon(itemID)
    local icon = getItemIcon and getItemIcon(itemID)
    if not icon and getItemInfoInstant then icon = select(5, getItemInfoInstant(itemID)) end
    return icon
end

function Compat.RequestItemData(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
        return true
    end
    if getItemInfo then getItemInfo(itemID) return true end -- the legacy call queues the request
    return false
end

local getSpellName = pick(C_Spell and C_Spell.GetSpellName)
local getSpellTexture = pick(C_Spell and C_Spell.GetSpellTexture, GetSpellTexture)

function Compat.GetSpellName(spellID)
    if getSpellName then return getSpellName(spellID) end
    if GetSpellInfo then return (GetSpellInfo(spellID)) end
    return nil
end

function Compat.GetSpellIcon(spellID)
    if getSpellTexture then return getSpellTexture(spellID) end
    if GetSpellInfo then return select(3, GetSpellInfo(spellID)) end
    return nil
end

function Compat.RequestSpellData(spellID)
    if C_Spell and C_Spell.RequestLoadSpellData then
        C_Spell.RequestLoadSpellData(spellID)
        return true
    end
    return false
end

local isPlayerSpell = pick(IsPlayerSpell, C_SpellBook and C_SpellBook.IsSpellKnown, IsSpellKnown)
function Compat.IsSpellKnown(spellID)
    return isPlayerSpell and isPlayerSpell(spellID) or false
end

-------------------------------------------------------------------------------
-- Places and factions
-------------------------------------------------------------------------------

-- Localized name of a class, from its id.
function Compat.GetClassName(classID)
    if not GetClassInfo then return nil end
    local name = GetClassInfo(classID)
    if name and name ~= "" then return name end
    return nil
end

function Compat.GetAreaName(areaID)
    if C_Map and C_Map.GetAreaInfo then
        local name = C_Map.GetAreaInfo(areaID)
        if name and name ~= "" then return name end
    end
    return nil
end

function Compat.GetInstanceName(mapID)
    if GetRealZoneText then
        local name = GetRealZoneText(mapID)
        if name and name ~= "" then return name end
    end
    return nil
end

function Compat.GetFactionName(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        if data and data.name then return data.name end
    end
    if GetFactionInfoByID then return (GetFactionInfoByID(factionID)) end
    return nil
end

-- Map art: returns the layer description and its tile textures, or nil.
function Compat.GetMapArt(uiMapID)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local layers = C_Map.GetMapArtLayers(uiMapID)
    local layer = layers and layers[1]
    if not layer then return nil end
    local textures = C_Map.GetMapArtLayerTextures(uiMapID, 1)
    if not textures or #textures == 0 then return nil end
    return layer, textures
end

-- Name of a map as the world map shows it.
function Compat.GetMapName(uiMapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
    local name = info and info.name
    if name and name ~= "" then return name end
    return nil
end

-- Maps the player is in, from the most precise (a building, a cave) up to its zone and
-- continent; empty when the client cannot tell.
function Compat.GetPlayerMaps()
    local maps = {}
    local uiMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    while uiMapID and uiMapID ~= 0 and #maps < 10 do
        maps[#maps + 1] = uiMapID
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
        uiMapID = info and info.parentMapID
    end
    return maps
end

-- Places a user waypoint on the world map; returns false when the client cannot.
function Compat.SetWaypoint(uiMapID, x, y)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap) then return false end
    if not C_Map.CanSetUserWaypointOnMap(uiMapID) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapID, x / 100, y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    return true
end

-------------------------------------------------------------------------------
-- Tooltip text (names the API does not expose, such as NPCs)
-------------------------------------------------------------------------------

local scanTooltip

-- Returns the first line of the tooltip of a hyperlink ("unit:...", "quest:..."), or nil.
function Compat.GetHyperlinkTitle(link)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        local line = data and data.lines and data.lines[1]
        if line and line.leftText and line.leftText ~= "" then return line.leftText end
        return nil
    end
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "AzerothCompleteScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTooltip:ClearLines()
    local ok = pcall(scanTooltip.SetHyperlink, scanTooltip, link)
    if not ok then return nil end
    local region = _G["AzerothCompleteScanTooltipTextLeft1"]
    local text = region and region:GetText()
    if text and text ~= "" then return text end
    return nil
end

function Compat.GetNpcName(npcID)
    return Compat.GetHyperlinkTitle(string.format("unit:Creature-0-0-0-0-%d-0000000000", npcID))
end

-------------------------------------------------------------------------------
-- Professions
-------------------------------------------------------------------------------

-- Returns { [localizedName] = { rank, maxRank, skillLine } } for the character's skills.
function Compat.GetProfessionRanks()
    local result = {}
    if GetProfessions and GetProfessionInfo then
        -- The returns have nil holes (a missing primary profession), so ipairs cannot be used.
        local indexes = { GetProfessions() }
        for slot = 1, select("#", GetProfessions()) do
            local index = indexes[slot]
            if index then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
                if name then result[name] = { rank = rank, maxRank = maxRank, skillLine = skillLine } end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if name and not isHeader and not result[name] then
                result[name] = { rank = rank, maxRank = maxRank }
            end
        end
    end
    return result
end
