-- Dumps the parts of a QuestieDB checkout that Azeroth Complete needs as one JSON document.
--
-- Usage: luajit questie_dump.lua <QuestieDB checkout> <output.json>
--
-- Prerequisite: the combined Forever export must exist in the checkout
-- (tools/export-forever.lua --include-authored), which build_data.py runs first.
-- Only identifiers, numbers and English fallback names are kept: the addon asks the
-- game client for every displayed text.

local root, outPath = arg[1], arg[2]
assert(root and outPath, "usage: questie_dump.lua <QuestieDB checkout> <output.json>")

-------------------------------------------------------------------------------
-- Minimal environment for the QuestieDB support modules
-------------------------------------------------------------------------------

local modules = {}
QuestieLoader = {
    ImportModule = function(_, name)
        modules[name] = modules[name] or { private = {} }
        return modules[name]
    end,
}
UnitFactionGroup = function() return "Alliance" end

-- Support files reference ZoneDB.zoneIDs; an auto-vivifying table keeps them loadable
-- without the enum, and the values we read never depend on it.
local zoneDB = QuestieLoader:ImportModule("ZoneDB")
zoneDB.zoneIDs = setmetatable({}, { __index = function() return 0 end })
local expansions = QuestieLoader:ImportModule("Expansions")
expansions.Current, expansions.Era, expansions.Tbc, expansions.Wotlk, expansions.Cata, expansions.MoP = 0, 0, 1, 2, 3, 4

local function runFile(path)
    local chunk = assert(loadfile(path))
    return chunk()
end

local function evalString(source)
    return assert(loadstring(source))()
end

-------------------------------------------------------------------------------
-- Inputs
-------------------------------------------------------------------------------

local combined = root .. "/src/corrections/Forever/combined/"
local quests = runFile(combined .. "foreverQuestDB.lua")
local npcs = runFile(combined .. "foreverNpcDB.lua")
local objects = runFile(combined .. "foreverObjectDB.lua")
local items = runFile(combined .. "foreverItemDB.lua")

local support = root .. "/support/Forever/"
runFile(support .. "Zones/areaIdToUiMapId.lua")
runFile(support .. "Zones/subZoneToParentZone.lua")
runFile(support .. "Zones/dungeons.lua")
local areaToUiMap = evalString(zoneDB.private.areaIdToUiMapId)
for k, v in pairs(evalString(zoneDB.private.areaIdToUiMapIdOverride or "return {}")) do areaToUiMap[k] = v end
local subZoneToParent = evalString(zoneDB.private.subZoneToParentZone)
for k, v in pairs(evalString(zoneDB.private.subZoneToParentZoneOverride or "return {}")) do subZoneToParent[k] = v end

local questXP = QuestieLoader:ImportModule("QuestXP")
runFile(support .. "QuestXP/xpDB-classic.lua")
runFile(support .. "QuestXP/xpDB-traces.lua")

-------------------------------------------------------------------------------
-- Selection
-------------------------------------------------------------------------------

-- Field indexes of the combined exports (see the legend at the top of each file).
local QUEST = { name = 1, startedBy = 2, finishedBy = 3, requiredLevel = 4, questLevel = 5,
    requiredRaces = 6, requiredClasses = 7, preQuestGroup = 12, preQuestSingle = 13,
    exclusiveTo = 16, zoneOrSort = 17, requiredSkill = 18, nextQuestInChain = 22,
    questFlags = 23, specialFlags = 24, parentQuest = 25, reputationReward = 26,
    breadcrumbForQuestId = 27 }
local NPC = { name = 1, minLevel = 4, maxLevel = 5, rank = 6, spawns = 7, zoneID = 9, npcFlags = 15 }
local OBJECT = { name = 1, spawns = 4, zoneID = 5 }
local ITEM = { name = 1, npcDrops = 2, objectDrops = 3, startQuest = 5, questRewards = 6, vendors = 14, teachesSpell = 16 }

local function firstSpawn(spawns)
    if type(spawns) ~= "table" then return nil end
    local bestZone, bestList
    for zone, list in pairs(spawns) do
        if type(list) == "table" and #list > 0 and (not bestList or #list > #bestList) then
            bestZone, bestList = zone, list
        end
    end
    if not bestList then return nil end
    return { zone = bestZone, x = bestList[1][1], y = bestList[1][2] }
end

-- Dungeon areas: [areaId] = { alternative area ids... }, used to place instance quests.
local dungeonAreas = {}
for areaId, entry in pairs(zoneDB.private.dungeons or {}) do
    dungeonAreas[tostring(areaId)] = entry[2] or {}
end

local out = { quests = {}, npcs = {}, objects = {}, items = {}, areaToUiMap = areaToUiMap,
    subZoneToParent = subZoneToParent, dungeonAreas = dungeonAreas }

for id, q in pairs(quests) do
    local xp = questXP.db[id]
    out.quests[tostring(id)] = {
        name = q[QUEST.name],
        startedBy = q[QUEST.startedBy],
        finishedBy = q[QUEST.finishedBy],
        requiredLevel = q[QUEST.requiredLevel],
        questLevel = q[QUEST.questLevel],
        requiredRaces = q[QUEST.requiredRaces],
        requiredClasses = q[QUEST.requiredClasses],
        preQuestGroup = q[QUEST.preQuestGroup],
        preQuestSingle = q[QUEST.preQuestSingle],
        exclusiveTo = q[QUEST.exclusiveTo],
        zoneOrSort = q[QUEST.zoneOrSort],
        requiredSkill = q[QUEST.requiredSkill],
        nextQuestInChain = q[QUEST.nextQuestInChain],
        questFlags = q[QUEST.questFlags],
        specialFlags = q[QUEST.specialFlags],
        parentQuest = q[QUEST.parentQuest],
        reputationReward = q[QUEST.reputationReward],
        breadcrumbForQuestId = q[QUEST.breadcrumbForQuestId],
        xp = xp and xp[2] or nil,
    }
end

for id, n in pairs(npcs) do
    out.npcs[tostring(id)] = {
        name = n[NPC.name], minLevel = n[NPC.minLevel], maxLevel = n[NPC.maxLevel],
        rank = n[NPC.rank], zoneID = n[NPC.zoneID], npcFlags = n[NPC.npcFlags],
        spawn = firstSpawn(n[NPC.spawns]),
    }
end

for id, o in pairs(objects) do
    out.objects[tostring(id)] = { name = o[OBJECT.name], zoneID = o[OBJECT.zoneID], spawn = firstSpawn(o[OBJECT.spawns]) }
end

for id, it in pairs(items) do
    out.items[tostring(id)] = {
        name = it[ITEM.name], npcDrops = it[ITEM.npcDrops], objectDrops = it[ITEM.objectDrops],
        startQuest = it[ITEM.startQuest], questRewards = it[ITEM.questRewards],
        vendors = it[ITEM.vendors], teachesSpell = it[ITEM.teachesSpell],
    }
end

-------------------------------------------------------------------------------
-- JSON output
-------------------------------------------------------------------------------

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true
end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encode(value, buffer)
    local kind = type(value)
    if kind == "nil" then
        buffer[#buffer + 1] = "null"
    elseif kind == "boolean" then
        buffer[#buffer + 1] = tostring(value)
    elseif kind == "number" then
        buffer[#buffer + 1] = (value % 1 == 0 and value < 2^53 and value > -2^53) and string.format("%.0f", value) or string.format("%.14g", value)
    elseif kind == "string" then
        buffer[#buffer + 1] = '"' .. value:gsub('[%c"\\]', function(c)
            return escapes[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif isArray(value) then
        buffer[#buffer + 1] = "["
        for i, v in ipairs(value) do
            if i > 1 then buffer[#buffer + 1] = "," end
            encode(v, buffer)
        end
        buffer[#buffer + 1] = "]"
    else
        buffer[#buffer + 1] = "{"
        local first = true
        for k, v in pairs(value) do
            if not first then buffer[#buffer + 1] = "," end
            first = false
            encode(tostring(k), buffer)
            buffer[#buffer + 1] = ":"
            encode(v, buffer)
        end
        buffer[#buffer + 1] = "}"
    end
end

local buffer = {}
encode(out, buffer)
local file = assert(io.open(outPath, "wb"))
file:write(table.concat(buffer))
file:close()
io.stderr:write(string.format("questie_dump: wrote %s\n", outPath))
