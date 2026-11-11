-- Offline tests of Azeroth Complete, run with a Lua 5.1 interpreter from the repository root:
--
--     lua5.1 tests/run.lua            (English client)
--     AC_TEST_LOCALE=frFR lua5.1 tests/run.lua
--
-- The addon is loaded in TOC order on top of tests/wow_stub.lua, then logs in, opens its
-- window and goes through every tab and list. The run fails on any error the addon logs,
-- on any missing translation and on any failed assertion.

package.path = "./tests/?.lua;" .. package.path
local Stub = require("wow_stub")

local ADDON = "AzerothComplete"
local failures = 0

local function fail(message, ...)
    failures = failures + 1
    io.stderr:write("FAIL: " .. string.format(message, ...) .. "\n")
end

local function check(condition, message, ...)
    if not condition then fail(message, ...) end
end

-------------------------------------------------------------------------------
-- Loading
-------------------------------------------------------------------------------

local ns = {}
local function loadToc()
    local files = {}
    for line in io.lines(ADDON .. "/" .. ADDON .. ".toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    for _, file in ipairs(files) do
        local chunk, err = loadfile(ADDON .. "/" .. file)
        if not chunk then error("cannot load " .. file .. ": " .. err) end
        chunk(ADDON, ns)
    end
    return #files
end

local fileCount = loadToc()
Stub.Fire("ADDON_LOADED", ADDON)
-- The client fires some events before the login, when no character record exists yet.
Stub.Fire("SKILL_LINES_CHANGED")
Stub.Fire("PLAYER_LOGIN")
Stub.Advance(1)

-------------------------------------------------------------------------------
-- Scenarios
-------------------------------------------------------------------------------

local function errorsInLog()
    local errors = {}
    for _, entry in ipairs(AzerothCompleteDB.log.entries) do
        if entry:find(" ERROR ", 1, true) or entry:find("Missing localized string", 1, true) then errors[#errors + 1] = entry end
    end
    return errors
end

-- Data sanity
check(ns.Diagnostics.Count(ns.Data.Quests) > 4000, "quest data looks too small")
check(ns.Data.Races.raceBits[1] == 0, "human race bit should be 0")
check(ns.HasBit(ns.Data.Races.allianceRaces, 32), "the Skyborne alliance bit (32) must be readable")
check(not ns.HasBit(ns.Data.Races.allianceRaces, 1), "orcs are not alliance")

-- Progress
local record = ns.Database:Character()
check(record and record.quests[783], "completed quests should be read at login")
local view = ns.Quests:CurrentView()
check(ns.Quests:Status(783, view) == "done", "quest 783 should be done")
check(ns.Quests:Status(18, view) == "active", "quest 18 is in the log")
Stub.Fire("QUEST_TURNED_IN", 18)
Stub.Advance(1)
check(ns.Quests:Status(18, view) == "done", "a turned-in quest becomes done")

-- Zones are named after their map, as the world map shows them; without a map name from the
-- client, the shipped one is used.
check(ns.Names.Area(40) == "Map 1436", "a zone is named after its map")
local getMapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function() return nil end
check(ns.Names.Area(40) == ns.Data.Strings[GetLocale()].maps[1436], "a zone falls back to the shipped map name")
C_Map.GetMapInfo = getMapInfo

-- Names: first lookup pending, then answered by the server
local pendingTitle = ns.Names.Quest(176)
Stub.Advance(1)
check(pendingTitle == nil and ns.Names.Quest(176) == "Quest 176", "quest titles are requested then cached")
check(ns.Database:Cache("quests")[176] == "Quest 176", "titles are cached in the saved variables")

-- Window and tabs
SlashCmdList.AZEROTHCOMPLETE("")
local frame = AzerothCompleteFrame
check(frame and frame:IsShown(), "the window opens with /azc")

local function clickRows(list, count)
    for i = 1, math.min(count, #list.rows) do
        local row = list.rows[i]
        if row:IsShown() then row:Click() end
    end
end

for _, tab in ipairs({ "quests", "professions", "toys", "dungeons", "raids", "achievements", "collections" }) do
    ns.MainFrame:SelectTab(tab)
    local active = ns.MainFrame.activeView
    check(active and active.frame:IsShown(), "tab %s shows its view", tab)
    -- Click through the lists of the view.
    for _, key in ipairs({ "zones", "quests", "professions", "recipes", "instances", "entries", "kinds", "categories", "achievements" }) do
        local list = active[key]
        if type(list) == "table" and list.rows then clickRows(list, 6) end
    end
    Stub.Advance(1)
end

-- Quests view behaviour
ns.MainFrame:SelectTab("quests")
local questsView = ns.MainFrame.activeView
for _, value in ipairs({ "kalimdor", "other", "categories", "ek" }) do questsView:SelectContinent(value) end
check(#questsView.zones.items > 0, "the zone list is not empty")
check(#questsView.quests.items > 0, "the quest list of the selected zone is not empty")
-- The player stands in a building of Elwynn Forest: the zone is found through the parent maps.
questsView.selectedGroup = nil
check(questsView:InitialContinent() == "ek" and questsView.selectedGroup and questsView.selectedGroup.id == 12,
    "the zone the player is in is selected first")
-- Artwork of the zones without a map of their own, and of the areas that only name quests.
local function findGroup(continentValue, id)
    for _, group in ipairs(questsView:GroupsOf(continentValue)) do
        if group.id == id then return group end
    end
end
local crafting = findGroup("categories", 16941)
check(crafting and not findGroup("ek", 16941), "an area that only names quests is listed among the categories")
local artOf = function(group)
    questsView:SelectGroup(group)
    return questsView.banner.art.request
end
local warrior = artOf(findGroup("categories", 81))
check(warrior and warrior.kind == "file" and warrior.ratio == 1, "a class category shows its talent background")
local blackrock = artOf(findGroup("ek", 25))
check(blackrock.kind == "file", "Blackrock Mountain shows the loading screen of its instances")
check(blackrock.top and blackrock.top > 0 and blackrock.bottom < 1,
    "a framed loading screen is cropped to its painting, without the logo band")
local noArt = { kind = "zone", id = 12, continent = ns.Const.Continent.EASTERN_KINGDOMS, chains = {}, art = 0 }
local request = artOf(noArt)
check(request.kind == "map" and request.dimmed and request.key:find("1415", 1, true),
    "a zone without any artwork shows its continent, darkened")
questsView:SelectContinent("ek")

-- One wheel notch moves the zone cards one by one.
questsView.zones:SetItems(questsView.zones.items)
questsView.zones:Scroll(1)
check(questsView.zones.offset == 1, "a wheel notch scrolls the zone list by one card (moved %d)", questsView.zones.offset)
local previousMin, previousMax = 0, 0
for _, group in ipairs(questsView:GroupsOf("ek")) do
    local low, high = group.levels and group.levels[1] or 99, group.levels and group.levels[2] or 99
    check(low > previousMin or (low == previousMin and high >= previousMax),
        "zones are sorted by level (zone %d)", group.id)
    previousMin, previousMax = low, high
end

-- A collection API answering in another order puts a non-text value in a name.
local getPetInfo = C_PetJournal.GetPetInfoBySpeciesID
C_PetJournal.GetPetInfoBySpeciesID = function(id)
    if id == ns.Data.Collections.pets[1] then return getPetInfo, 132599 end
    return getPetInfo(id)
end
ns.Collections:Invalidate("pets")
local pets = ns.Collections:Entries("pets")
C_PetJournal.GetPetInfoBySpeciesID = getPetInfo
ns.Collections:Invalidate("pets")
check(pets and #pets > 0, "a collection keeps its valid entries when one name is not a text")

-- Every tab has content
local expectations = {
    professions = "recipes", dungeons = "entries", raids = "entries", toys = "entries",
    collections = "entries", achievements = "achievements",
}
for tab, listKey in pairs(expectations) do
    ns.MainFrame:SelectTab(tab)
    local list = ns.MainFrame.activeView[listKey]
    check(list and #list.items > 0, "tab %s lists entries in %s", tab, listKey)
    local shown = 0
    for _, row in ipairs(list and list.rows or {}) do if row:IsShown() then shown = shown + 1 end end
    check(shown > 0, "tab %s draws rows", tab)
end

-- Quest details of an active quest, with objectives and a waypoint button
ns.MainFrame:SelectTab("quests")
questsView = ns.MainFrame.activeView
questsView:OnQuestClick({ kind = "quest", id = 176 })
check(#questsView.details.widgets.line > 0, "quest details are drawn")
for _, button in ipairs(questsView.details.widgets.button or {}) do
    if button:IsShown() then button:Click() end
end

-- Tracking modes and faction switch; the character filter only applies to the character.
frame.tracking:Click()
check(ns.Database:Settings().tracking == "account" and not frame.filter.available,
    "the tracking switch goes to the account, where the character filter does not apply")
frame.faction:Click()
Stub.Advance(1)
frame.tracking:Click()
check(ns.Database:Settings().tracking == "character", "the tracking switch comes back to the character")
check(not frame.filter.available, "the character filter does not apply to the other faction")
frame.faction:Click()
check(frame.filter.available, "the character filter applies to the character in its own faction")
Stub.Advance(1)

-- Character filter: the character (stub) knows Blacksmithing only.
local Q = ns.Const.Quest
local function questNeeding(predicate)
    for questID, row in pairs(ns.Data.Quests) do
        if predicate(row) and ns.Player:CanRace(row[Q.RACES]) and ns.Player:CanClass(row[Q.CLASSES]) then return questID end
    end
end
local skinning = questNeeding(function(row) return row[Q.SKILL] and row[Q.SKILL][1] == 393 end)
local smithing = questNeeding(function(row) return row[Q.SKILL] and row[Q.SKILL][1] == 164 end)
local order = questNeeding(function(row) return row[Q.CRAFT] and row[Q.CRAFT] ~= 164 end)
local alchemy = questNeeding(function(row) return row[Q.AREA] == -181 end)
check(skinning and smithing and order and alchemy, "the data has quests needing professions")
local possibleView = ns.MainFrame:View()
check(possibleView.possible, "the character filter is active by default")
check(not ns.Quests:IsVisible(skinning, possibleView), "a quest of an unlearned profession is hidden")
check(ns.Quests:IsVisible(smithing, possibleView), "a quest of a learned profession is shown")
check(not ns.Quests:IsVisible(order, possibleView), "a crafting order of an unlearned profession is hidden")
check(not ns.Quests:IsVisible(alchemy, possibleView), "a quest of an unlearned profession category is hidden")
ns.MainFrame:SelectTab("professions")
local shownProfessions = ns.MainFrame.activeView.professions.items
check(#shownProfessions == 1 and shownProfessions[1].skillLine == 164, "only the learned professions are listed")
ns.MainFrame:SelectTab("quests")
local filteredTotal = ns.Quests:Summary("test:skinning", { { skinning, smithing } }, possibleView).total
frame.filter:Click()
local everythingView = ns.MainFrame:View()
check(not everythingView.possible and ns.Quests:IsVisible(skinning, everythingView),
    "the filter switch shows the quests of every profession")
check(ns.Quests:Summary("test:skinning", { { skinning, smithing } }, everythingView).total > filteredTotal,
    "the counts follow the character filter")
ns.MainFrame:SelectTab("professions")
check(#ns.MainFrame.activeView.professions.items == #ns.Professions:List(), "every profession is listed without the filter")
frame.filter:Click()
ns.MainFrame:SelectTab("quests")

-- Crafting orders: the rows drop the prefix that every title shares.
local questName = ns.Names.Quest
ns.Names.Quest = function(questID) return "Writ: Item " .. questID end
local orders = ns.QuestWidgets.BuildItems(crafting.chains, everythingView, {})
ns.Names.Quest = questName
check(orders[1] and orders[1].prefix == "Writ: ", "the shared prefix of the titles is found")
ns.Names.Quest = function(questID) return "Commission : élixir " .. questID end
orders = ns.QuestWidgets.BuildItems(crafting.chains, everythingView, {})
local orderRow = questsView.quests.rows[1]
ns.QuestWidgets.FillRow(orderRow, orders[1], everythingView)
ns.Names.Quest = questName
check(orderRow.name:GetText():sub(1, 7) == "Élixir", "a name left by the prefix starts with a capital (%s)", orderRow.name:GetText())

-- A quest needing a higher profession rank is locked; the character (stub) has 75 in Blacksmithing.
local hardSmithing = questNeeding(function(row)
    return row[Q.SKILL] and row[Q.SKILL][1] == 164 and row[Q.SKILL][2] > 75 and not row[Q.PRE_ALL] and not row[Q.PRE_ANY]
end)
local playerLevel = ns.Player.level
ns.Player.level = 60
local status, reason = ns.Quests:Status(hardSmithing, possibleView)
ns.Player.level = playerLevel
check(status == ns.Const.Status.LOCKED and reason == "skill", "a quest above the profession rank is locked (%s, %s)",
    tostring(status), tostring(reason))

-- The state filter of the item lists: "to do" and "done" narrow the list, never the counts.
local elwynn = findGroup("ek", 12)
questsView:SelectGroup(elwynn)
local filter = questsView.stateFilter
local everyChainOpen = setmetatable({}, { __index = function() return true end })
local function listedStates(state)
    filter.buttons[state]:Click()
    local done, todo = 0, 0
    for _, item in ipairs(ns.QuestWidgets.BuildItems(elwynn.chains, possibleView, everyChainOpen, nil, filter)) do
        if item.kind == "quest" then
            if ns.Quests:Status(item.id, possibleView) == ns.Const.Status.DONE then done = done + 1 else todo = todo + 1 end
        end
    end
    return done, todo
end
local before = ns.Quests:Summary("zone:12", elwynn.chains, possibleView).done
local allDone, allTodo = listedStates(1)
local todoDone, todoTodo = listedStates(2)
local doneDone, doneTodo = listedStates(3)
check(allDone > 0 and allTodo > 0, "every quest is listed without a state filter")
check(todoDone == 0 and todoTodo == allTodo, "the to-do filter lists only the remaining quests")
check(doneTodo == 0 and doneDone == allDone, "the done filter lists only the completed quests")
check(ns.Database:Settings().listFilters.quests == "done", "the state filter of a list is remembered")
check(ns.Quests:Summary("zone:12", elwynn.chains, possibleView).done == before, "the state filter keeps the counts")
filter.buttons[1]:Click()
for _, tab in ipairs({ "professions", "toys", "dungeons", "raids", "achievements", "collections" }) do
    ns.MainFrame:SelectTab(tab)
    local stateFilter = ns.MainFrame.activeView.filters
    check(stateFilter and stateFilter.Keeps, "tab %s offers the state filter", tab)
    if stateFilter then
        stateFilter.buttons[2]:Click()
        stateFilter.buttons[1]:Click()
    end
end
ns.MainFrame:SelectTab("quests")

-- Professions: known spells were read
check(ns.Database:Character().recipes[2660], "known recipes are read from the spellbook")

-- Slash commands
for _, command in ipairs({ "help", "diag", "log 5", "debug", "debug", "rescan", "scale 1.2", "scale 9", "minimap", "minimap", "nope" }) do
    SlashCmdList.AZEROTHCOMPLETE(command)
end
Stub.Advance(2)
SlashCmdList.AZEROTHCOMPLETE("")
check(not frame:IsShown(), "/azc toggles the window closed")

-------------------------------------------------------------------------------
-- Localization completeness
-------------------------------------------------------------------------------

local function localeTable(path, locale)
    local captured
    local fakeNs = { RegisterLocale = function(_, _, strings) captured = strings end }
    local savedGetLocale = GetLocale
    GetLocale = function() return locale end
    assert(loadfile(path))(ADDON, fakeNs)
    GetLocale = savedGetLocale
    return captured
end

local english = localeTable(ADDON .. "/Locales/enUS.lua", "enUS")
local french = localeTable(ADDON .. "/Locales/frFR.lua", "frFR")
for key in pairs(english) do check(french[key] ~= nil, "frFR lacks %s", key) end
for key in pairs(french) do check(english[key] ~= nil, "frFR has %s, unknown in enUS", key) end

-------------------------------------------------------------------------------
-- Result
-------------------------------------------------------------------------------

for _, entry in ipairs(errorsInLog()) do fail("logged: %s", entry) end
io.write(string.format("[%s] %d files loaded, %d log entries, %d failures", GetLocale(), fileCount,
    #AzerothCompleteDB.log.entries, failures) .. "\n")
if os.getenv("AC_TEST_VERBOSE") then
    for _, entry in ipairs(AzerothCompleteDB.log.entries) do io.write(entry, "\n") end
end
if failures > 0 then os.exit(1) end
