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

-- Tracking modes and faction switch
frame.tracking:Select("account", true)
frame.faction:Click()
Stub.Advance(1)
frame.tracking:Select("character", true)
frame.faction:Click()
Stub.Advance(1)

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
