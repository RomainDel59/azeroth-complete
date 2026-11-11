-- Texts of game content, asked from the client.
--
-- Quest titles, item and spell names arrive asynchronously: the first lookup returns nil
-- (the interface shows a placeholder) and queues a request; when the client answers, the
-- text is cached in the saved variables of the client language and AC_NAMES_UPDATED is
-- sent so that the interface redraws. Requests are throttled to keep the server traffic
-- low. A text the client cannot provide falls back to the English name shipped with the
-- data, and the fallback is logged once per kind so that missing APIs show up in the log.

local _, ns = ...

local Names = {}
ns.Names = Names

local Q = ns.Const.Quest
local REQUESTS_PER_TICK = 20
local TICK_SECONDS = 0.2
local GIVE_UP_SECONDS = 5

local queues = { quest = {}, item = {}, spell = {} } -- ordered ids waiting for a request
local heads = { quest = 1, item = 1, spell = 1 }      -- index of the next id of each queue
local queued = { quest = {}, item = {}, spell = {} } -- [id] = true while queued
local waiting = { quest = {}, item = {}, spell = {} } -- [id] = request time
local failed = { quest = {}, item = {}, spell = {}, npc = {} }
local fallbackReported = {}
local ticker
local stats = { requested = 0, received = 0, fallbacks = 0 }
local fellBack = {} -- ["kind:id"] = true once counted
local NPC_RETRY_SECONDS = 10

local function reportFallback(kind, id)
    local key = kind .. ":" .. tostring(id)
    if fellBack[key] then return end
    fellBack[key] = true
    stats.fallbacks = stats.fallbacks + 1
    if not fallbackReported[kind] then
        fallbackReported[kind] = true
        ns.Log:Info("Client did not provide a %s text (first: %s); using the shipped fallback", kind, tostring(id))
    end
end

local function notify()
    ns:SendMessageDelayed("AC_NAMES_UPDATED", 0.3)
end

-------------------------------------------------------------------------------
-- Request loop
-------------------------------------------------------------------------------

local requesters = {
    quest = ns.Compat.RequestQuestData,
    item = ns.Compat.RequestItemData,
    spell = ns.Compat.RequestSpellData,
}

local resolvers -- defined below, used by the tick to check answers that arrive without events

local function tick()
    local now = GetTime()
    local budget = REQUESTS_PER_TICK
    local busy = false
    for kind, queue in pairs(queues) do
        while budget > 0 and heads[kind] <= #queue do
            local id = queue[heads[kind]]
            queue[heads[kind]] = false
            heads[kind] = heads[kind] + 1
            queued[kind][id] = nil
            if requesters[kind](id) then
                waiting[kind][id] = now
                stats.requested = stats.requested + 1
            else
                failed[kind][id] = true
            end
            budget = budget - 1
        end
        -- Answers may arrive without an event (cached data); time out the rest.
        for id, since in pairs(waiting[kind]) do
            busy = true
            if resolvers[kind](id) then
                waiting[kind][id] = nil
                notify()
            elseif now - since > GIVE_UP_SECONDS then
                waiting[kind][id] = nil
                failed[kind][id] = true
                notify()
            end
        end
        if heads[kind] <= #queue then
            busy = true
        else
            queues[kind], heads[kind] = {}, 1 -- drained: start a fresh array
        end
    end
    if not busy and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function enqueue(kind, id)
    if queued[kind][id] or waiting[kind][id] or failed[kind][id] then return end
    queued[kind][id] = true
    table.insert(queues[kind], id)
    if not ticker then ticker = C_Timer.NewTicker(TICK_SECONDS, function() ns:SafeCall("Names.tick", tick) end) end
end

-------------------------------------------------------------------------------
-- Resolvers: read the client, cache on success
-------------------------------------------------------------------------------

resolvers = {
    quest = function(id)
        local title = ns.Compat.GetQuestTitle(id)
        if title then ns.Database:Cache("quests")[id] = title stats.received = stats.received + 1 end
        return title
    end,
    item = function(id)
        local name = ns.Compat.GetItemName(id)
        if name then ns.Database:Cache("items")[id] = name stats.received = stats.received + 1 end
        return name
    end,
    spell = function(id)
        local name = ns.Compat.GetSpellName(id)
        if name then ns.Database:Cache("spells")[id] = name stats.received = stats.received + 1 end
        return name
    end,
}

local function resolve(kind, cacheName, id, fallback)
    if not id then return nil end
    local cached = ns.Database:Cache(cacheName)[id]
    if cached then return cached end
    local value = resolvers[kind](id)
    if value then return value end
    if failed[kind][id] then
        if fallback then reportFallback(kind, id) end
        return fallback
    end
    enqueue(kind, id)
    return nil
end

-------------------------------------------------------------------------------
-- Public lookups: each returns the text, or nil while it is being fetched
-------------------------------------------------------------------------------

function Names.Quest(questID)
    local row = ns.Data.Quests[questID]
    return resolve("quest", "quests", questID, row and row[Q.NAME_FALLBACK])
end

function Names.Item(itemID)
    local row = ns.Data.Items and ns.Data.Items[itemID]
    return resolve("item", "items", itemID, row and row[1])
end

function Names.Spell(spellID)
    return resolve("spell", "spells", spellID, spellID and ("#" .. spellID) or nil)
end

-- NPC names have no API: the tooltip of a creature link holds the name once the client
-- has met the creature. Otherwise the shipped English name is used.
function Names.Npc(npcID)
    local cache = ns.Database:Cache("npcs")
    if cache[npcID] then return cache[npcID] end
    local row = ns.Data.Npcs and ns.Data.Npcs[npcID]
    -- The tooltip request makes the client load the creature: a miss is retried later.
    local lastTry = failed.npc[npcID]
    if not lastTry or GetTime() - lastTry > NPC_RETRY_SECONDS then
        local name = ns.Compat.GetNpcName(npcID)
        if name then
            cache[npcID] = name
            return name
        end
        failed.npc[npcID] = GetTime()
    end
    if row and row[1] then reportFallback("npc", npcID) end
    return row and row[1]
end

function Names.Object(objectID)
    local row = ns.Data.Objects and ns.Data.Objects[objectID]
    return row and row[1]
end

-- A quest zone is named after its map, as the world map shows it: some area names of the
-- localized clients add the English name in parentheses. Other areas keep their own name.
function Names.Area(areaID)
    if not areaID then return nil end
    local zone = ns.Data.Zones[areaID]
    local uiMap = zone and zone.uiMap
    local mapName = uiMap and (ns.Compat.GetMapName(uiMap) or ns:GameString("maps", uiMap))
    return mapName or ns.Compat.GetAreaName(areaID) or ns:GameString("areas", areaID)
end

function Names.Instance(mapID, areaID)
    return ns.Compat.GetInstanceName(mapID) or Names.Area(areaID)
end

function Names.Faction(factionID)
    return ns.Compat.GetFactionName(factionID)
end

function Names.Encounter(encounterID)
    return ns.Database:Cache("encounters")[encounterID] or ns:GameString("encounters", encounterID)
end

function Names.SkillLine(skillLine)
    return ns:GameString("skillLines", skillLine)
end

function Names.QuestSort(sortID)
    return ns:GameString("questSorts", sortID)
end

-- Name of a quest giver or ender ({ kind, id } from the quest data).
function Names.Entity(entity)
    if not entity then return nil end
    local kind, id = entity[1], entity[2]
    if kind == ns.Const.Entity.NPC then return Names.Npc(id) end
    if kind == ns.Const.Entity.OBJECT then return Names.Object(id) end
    return Names.Item(id)
end

-- Queues titles ahead of display, e.g. the quests of the selected zone.
function Names.Prefetch(questIDs)
    for _, questID in ipairs(questIDs) do Names.Quest(questID) end
end

function Names.Stats()
    local pending = 0
    for kind in pairs(queues) do
        pending = pending + (#queues[kind] - heads[kind] + 1)
        for _ in pairs(waiting[kind]) do pending = pending + 1 end
    end
    return stats.requested, stats.received, stats.fallbacks, pending
end

-------------------------------------------------------------------------------
-- Client answers
-------------------------------------------------------------------------------

local function onAnswer(kind)
    return function(_, id, success)
        if not id or not waiting[kind][id] then return end
        waiting[kind][id] = nil
        if success == false or not resolvers[kind](id) then failed[kind][id] = true end
        notify()
    end
end

ns:RegisterEvent("QUEST_DATA_LOAD_RESULT", onAnswer("quest"))
ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", onAnswer("item"))
ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", onAnswer("item"))
ns:RegisterEvent("SPELL_DATA_LOAD_RESULT", onAnswer("spell"))
ns:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName)
    if encounterID and encounterName then ns.Database:Cache("encounters")[encounterID] = encounterName end
end)
