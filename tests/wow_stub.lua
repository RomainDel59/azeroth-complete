-- Minimal WoW client emulation for the offline tests.
--
-- Widgets accept only the methods listed below, so a misspelled or non-existent widget
-- method fails the tests instead of failing in the game. Game APIs return small,
-- deterministic fixtures; asynchronous answers (quest titles, item names) are delivered
-- when the test advances the timers.

local Stub = {}

local locale = os.getenv("AC_TEST_LOCALE") or "enUS"
local clock = 0
local timers = {}
local eventFrames = {}

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------

local NOOP_METHODS = {
    -- Region / frame
    "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameStrata", "SetFrameLevel", "SetToplevel", "SetMovable",
    "SetClampedToScreen", "EnableMouse", "EnableMouseWheel", "RegisterForDrag", "RegisterForClicks", "StartMoving",
    "StopMovingOrSizing", "SetScale", "SetClipsChildren", "SetHighlightTexture", "SetAlpha", "UnregisterEvent",
    "SetHitRectInsets", "Raise", "Lower",
    -- Texture
    "SetTexture", "SetColorTexture", "SetTexCoord", "SetRotation", "SetGradient", "SetVertexColor", "SetBlendMode",
    "SetDrawLayer", "SetDesaturated",
    -- Font string / edit box
    "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetNonSpaceWrap", "SetShadowOffset",
    "SetShadowColor", "SetAutoFocus", "SetTextInsets", "ClearFocus", "SetFocus", "SetMaxLetters",
    -- Slider / scroll frame
    "SetOrientation", "SetThumbTexture", "SetValueStep", "SetObeyStepOnDrag", "SetScrollChild",
    -- Tooltip
    "SetOwner", "ClearLines", "AddLine", "AddDoubleLine",
}

local Widget = {}
-- Widget methods are capitalized; lowercase keys are the addon's own fields and may be nil.
Widget.__index = function(self, key)
    local method = Widget[key]
    if method then return method end
    if type(key) == "string" and key:match("^%u") then
        error(string.format("unknown widget method %s on %s", key, rawget(self, "_type") or "?"), 2)
    end
    return nil
end

for _, name in ipairs(NOOP_METHODS) do Widget[name] = function() end end

function Widget:SetSize(width, height) self._width, self._height = width, height end
function Widget:SetWidth(width) self._width = width end
function Widget:SetHeight(height) self._height = height end
function Widget:GetWidth() return self._width or 400 end
function Widget:GetHeight() return self._height or 300 end
function Widget:GetFrameLevel()
    local level, parent = 0, self._parent
    while parent do level, parent = level + 1, parent._parent end
    return level
end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetCenter() return 500, 400 end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:Show() self._shown = true end
function Widget:Hide()
    local wasShown = self._shown
    self._shown = false
    if wasShown and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:SetScript(event, handler) self._scripts[event] = handler end
function Widget:GetScript(event) return self._scripts[event] end
function Widget:HookScript(event, handler)
    local previous = self._scripts[event]
    self._scripts[event] = function(...) if previous then previous(...) end handler(...) end
end
function Widget:SetText(text) self._text = text end
function Widget:GetText() return self._text end
function Widget:GetStringHeight() return 14 end
function Widget:GetStringWidth() return #(self._text or "") * 6 end
function Widget:SetMinMaxValues(low, high) self._min, self._max = low, high end
function Widget:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Widget:SetValue(value)
    self._value = value
    if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, value) end
end
function Widget:GetValue() return self._value or 0 end
function Widget:SetVerticalScroll(value) self._scroll = value end
function Widget:GetVerticalScroll() return self._scroll or 0 end
function Widget:RegisterEvent(event)
    if not Stub.knownEvents[event] then error("unknown event " .. event) end
    eventFrames[self] = eventFrames[self] or {}
    eventFrames[self][event] = true
end
function Widget:SetHyperlink() end
function Widget:Click(button)
    if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end
end
function Widget:GetChildren() return unpack(self._children) end

local function newWidget(kind, parent)
    local widget = setmetatable({ _type = kind, _scripts = {}, _children = {}, _shown = true, _parent = parent }, Widget)
    if parent then table.insert(parent._children, widget) end
    return widget
end

function Widget:CreateTexture() return newWidget("Texture", self) end
function Widget:CreateFontString() return newWidget("FontString", self) end

function CreateFrame(kind, name, parent)
    local frame = newWidget(kind, parent)
    if name then _G[name] = frame end
    return frame
end

UIParent = newWidget("Frame")
WorldFrame = newWidget("Frame")
Minimap = newWidget("Frame")
GameTooltip = newWidget("GameTooltip")
DEFAULT_CHAT_FRAME = newWidget("Frame")
Stub.chat = {}
function DEFAULT_CHAT_FRAME.AddMessage(_, text) table.insert(Stub.chat, text) end
UISpecialFrames = {}
SlashCmdList = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-------------------------------------------------------------------------------
-- Events and timers
-------------------------------------------------------------------------------

Stub.knownEvents = {}
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "QUEST_ACCEPTED",
    "QUEST_REMOVED", "QUEST_DATA_LOAD_RESULT", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
    "SPELL_DATA_LOAD_RESULT", "ENCOUNTER_END", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
    "CRAFT_SHOW", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "UPDATE_INSTANCE_INFO",
    "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "NEW_PET_ADDED", "PET_JOURNAL_LIST_UPDATE", "TOYS_UPDATED",
    "NEW_TOY_ADDED", "TRANSMOG_COLLECTION_UPDATED", "KNOWN_TITLES_UPDATE", "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" }) do
    Stub.knownEvents[event] = true
end

function Stub.Fire(event, ...)
    for frame, events in pairs(eventFrames) do
        if events[event] and frame._scripts.OnEvent then frame._scripts.OnEvent(frame, event, ...) end
    end
end

C_Timer = {}
function C_Timer.After(delay, callback) table.insert(timers, { at = clock + delay, callback = callback }) end
function C_Timer.NewTicker(interval, callback)
    local ticker = { cancelled = false }
    local function schedule()
        table.insert(timers, { at = clock + interval, callback = function()
            if ticker.cancelled then return end
            callback()
            if not ticker.cancelled then schedule() end
        end })
    end
    function ticker.Cancel() ticker.cancelled = true end
    schedule()
    return ticker
end

-- Advances the clock, running due timers in order.
function Stub.Advance(seconds)
    local target = clock + seconds
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local nextTimer = timers[1]
        if not nextTimer or nextTimer.at > target then break end
        table.remove(timers, 1)
        clock = nextTimer.at
        nextTimer.callback()
    end
    clock = target
end

function GetTime() return clock end
date = os.date
time = os.time

-------------------------------------------------------------------------------
-- Client
-------------------------------------------------------------------------------

function GetLocale() return locale end
function GetBuildInfo() return "1.60.1", "70888", "Nov 10 2026", 16001 end
function geterrorhandler() return function(err) error(err) end end
function debugstack() return debug.traceback() end
function print(...) table.insert(Stub.chat, table.concat({ ... }, " ")) end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetCursorPosition() return 0, 0 end
C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "@project-version@" or nil end }

QUESTS_LABEL = locale == "frFR" and "Quêtes" or "Quests"
TRADE_SKILLS = locale == "frFR" and "Métiers" or "Professions"
TOY_BOX = locale == "frFR" and "Coffre à jouets" or "Toy Box"

-------------------------------------------------------------------------------
-- Player
-------------------------------------------------------------------------------

function UnitName() return "Tester" end
function GetRealmName() return "Forever" end
function UnitClass() return "Paladin", "PALADIN", 2 end
function UnitRace() return "Human", "Human", 1 end
function UnitFactionGroup() return "Alliance", "Alliance" end
function UnitLevel() return 12 end

-------------------------------------------------------------------------------
-- Game data fixtures
-------------------------------------------------------------------------------

Stub.completedQuests = { 783, 7, 15, 33 }
Stub.questTitles = {}  -- titles the "server" has sent
Stub.unknownQuest = 999999

C_QuestLog = {}
function C_QuestLog.GetAllCompletedQuestIDs() return Stub.completedQuests end
function C_QuestLog.GetTitleForQuestID(questID) return Stub.questTitles[questID] end
function C_QuestLog.RequestLoadQuestByID(questID)
    C_Timer.After(0.1, function()
        Stub.questTitles[questID] = "Quest " .. questID
        Stub.Fire("QUEST_DATA_LOAD_RESULT", questID, true)
    end)
end
function C_QuestLog.IsOnQuest(questID) return questID == 18 end
function C_QuestLog.GetQuestObjectives(questID)
    if questID == 18 then return { { text = "Kill things: 2/10", finished = false } } end
    return {}
end

C_Item = {}
Stub.itemNames = {}
function C_Item.GetItemNameByID(itemID) return Stub.itemNames[itemID] end
function C_Item.GetItemIconByID() return 134400 end
function C_Item.RequestLoadItemDataByID(itemID)
    C_Timer.After(0.1, function()
        Stub.itemNames[itemID] = "Item " .. itemID
        Stub.Fire("ITEM_DATA_LOAD_RESULT", itemID, true)
    end)
end

C_Spell = {}
function C_Spell.GetSpellName(spellID) return "Spell " .. spellID end
function C_Spell.GetSpellTexture() return 136241 end
function IsPlayerSpell(spellID) return spellID == 2660 or spellID == 2663 end

C_Map = {}
function C_Map.GetAreaInfo(areaID) return "Area " .. areaID end
-- The player stands in a building (2000) of Elwynn Forest (1429), in the Eastern Kingdoms (1415).
function C_Map.GetBestMapForUnit() return 2000 end
function C_Map.GetMapInfo(uiMapID)
    local parents = { [2000] = 1429, [1429] = 1415, [1415] = 947 }
    return { mapID = uiMapID, name = "Map " .. uiMapID, parentMapID = parents[uiMapID] or 0 }
end
function C_Map.GetMapArtLayers() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
function C_Map.GetMapArtLayerTextures() return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } end
function C_Map.CanSetUserWaypointOnMap() return true end
function C_Map.SetUserWaypoint() Stub.waypoint = true end
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
function GetRealZoneText(mapID) return "Instance " .. mapID end

C_Reputation = { GetFactionDataByID = function(id) return { name = "Faction " .. id } end }
C_TooltipInfo = { GetHyperlink = function(link)
    local npc = link:match("Creature%-0%-0%-0%-0%-(%d+)")
    if npc and tonumber(npc) % 2 == 0 then return { lines = { { leftText = "NPC " .. npc } } } end
    return { lines = {} }
end }

local CLASS_NAMES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage", "Warlock", "Monk", "Druid" }
function GetClassInfo(classID)
    local name = CLASS_NAMES[classID]
    if name then return name, name:upper():gsub(" ", ""), classID end
end

function GetProfessions() return 1, nil end
function GetProfessionInfo() return "Blacksmithing", 136241, 75, 150, 0, 0, 164 end

function GetNumSavedInstances() return 0 end
function RequestRaidInfo() Stub.Fire("UPDATE_INSTANCE_INFO") end
function GetSavedInstanceInfo() return nil end
function GetSavedInstanceEncounterInfo() return nil end

C_MountJournal = {}
function C_MountJournal.GetMountIDs() return { 6, 7, 8 } end
function C_MountJournal.GetMountInfoByID(id)
    return "Mount " .. id, 400 + id, 132261, false, true, 0, false, id == 8, 0, false, id == 6, id
end
function C_MountJournal.GetMountInfoExtraByID() return 1, "A fine mount.", "Vendor: Somewhere" end

C_PetJournal = {}
function C_PetJournal.GetPetInfoBySpeciesID(id)
    return "Pet " .. id, 132599, 1, 1, "Drop: Somewhere", "A fine pet.", false, false, false, false, true, 1
end
function C_PetJournal.GetNumCollectedInfo(id) return id % 2, 3 end

C_ToyBox = { GetToyInfo = function(itemID) return itemID, "Toy " .. itemID, 134400 end }
function PlayerHasToy(itemID) return itemID % 2 == 1 end

C_TransmogSets = {}
function C_TransmogSets.GetSetInfo(id) return { name = "Set " .. id, collected = false, description = "Some set" } end
function C_TransmogSets.GetSetPrimaryAppearances() return { { collected = true }, { collected = false } } end

function GetTitleName(id) return "Title " .. id .. " " end
function IsTitleKnown(id) return id == 1 end

-- Legacy challenge categories: named after a class, a profession or neither.
local CATEGORY_NAMES = { [92] = "Druid", [93] = "Paladin", [94] = "Exploration",
    [95] = locale == "frFR" and "Alchimie" or "Alchemy", [96] = locale == "frFR" and "Forge" or "Blacksmithing" }
function GetCategoryList() return { 92, 93, 94, 95, 96 } end
function GetCategoryInfo(id) return CATEGORY_NAMES[id] or ("Category " .. id), -1 end
function GetCategoryNumAchievements() return 2 end
function GetAchievementInfo(categoryOrID, index)
    local id = index and (categoryOrID * 10 + index) or categoryOrID
    return id, "Challenge " .. id, 10, id % 2 == 0, 11, 10, 26, "Do something", 0, 136000, "", false, id % 2 == 0
end
function GetAchievementNumCriteria() return 2 end
function GetAchievementCriteriaInfo(_, index) return "Criterion " .. index, 0, index == 1, index, 3 end

return Stub
