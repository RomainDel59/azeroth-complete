-- Quest list and quest details, shared by the quest, dungeon and raid views.

local _, ns = ...

local QuestWidgets = {}
ns.QuestWidgets = QuestWidgets

local L = ns.L
local UI, Theme = ns.UI, ns.Theme
local C = Theme.colors
local Q, Status, Flag, Entity = ns.Const.Quest, ns.Const.Status, ns.Const.QuestFlag, ns.Const.Entity

QuestWidgets.STATUS_COLORS = {
    [Status.DONE] = C.green,
    [Status.ACTIVE] = C.yellow,
    [Status.AVAILABLE] = C.text,
    [Status.LOCKED] = C.gray,
    [Status.REPEATABLE] = C.blue,
}

local function questName(questID)
    local name = ns.Names.Quest(questID)
    if name then return name end
    -- A prerequisite outside the catalogue has no fallback name.
    return ns.Data.Quests[questID] and L.LOADING or ("#" .. questID)
end

-- Level range text: "Lvl 6-8" or "Lvl 9".
function QuestWidgets.LevelText(low, high)
    if not low then return "" end
    if high and high ~= low then return string.format(L.LEVEL_RANGE, low, high) end
    return string.format(L.LEVEL_SHORT, low)
end

-------------------------------------------------------------------------------
-- List items: chains (expandable) and quests
-------------------------------------------------------------------------------

-- Prefix ending with a colon that most titles of a list share, such as the "Craftsman's
-- Writ:" of the crafting orders: the rows then show what tells the quests apart.
local function sharedPrefix(chains)
    local counts, named = {}, 0
    for _, chain in ipairs(chains) do
        for _, questID in ipairs(chain) do
            local name = ns.Names.Quest(questID)
            if name then
                named = named + 1
                local prefix = name:match("^(.-%s?:%s+)%S")
                if prefix then counts[prefix] = (counts[prefix] or 0) + 1 end
            end
        end
    end
    for prefix, count in pairs(counts) do
        if count >= 3 and count * 2 >= named then return prefix end
    end
    return nil
end

-- Turns chains into list items for a view. `expanded[rootID]` opens a chain. A state
-- `filter` (UI.StateFilter) narrows the quests listed; the counts keep them all.
function QuestWidgets.BuildItems(chains, view, expanded, query, filter)
    local items = {}
    local prefix = sharedPrefix(chains)
    for _, chain in ipairs(chains) do
        local summary = ns.Quests:ChainSummary(chain, view)
        local visible = summary.quests
        if filter then
            local kept = {}
            for _, questID in ipairs(visible) do
                if filter:Keeps(ns.Quests:Status(questID, view) == Status.DONE) then kept[#kept + 1] = questID end
            end
            visible = kept
        end
        if query and query ~= "" then
            local matching = {}
            for _, questID in ipairs(visible) do
                if UI.Matches(ns.Names.Quest(questID) or "", query) then matching[#matching + 1] = questID end
            end
            visible = matching
        end
        if #visible == 1 then
            items[#items + 1] = { kind = "quest", id = visible[1], prefix = prefix }
        elseif #visible > 1 then
            local root = visible[1]
            local open = expanded[root] or (query and query ~= "")
            items[#items + 1] = { kind = "chain", id = root, summary = summary, open = open, prefix = prefix }
            if open then
                for _, questID in ipairs(visible) do
                    items[#items + 1] = { kind = "quest", id = questID, indent = true, prefix = prefix }
                end
            end
        end
    end
    return items
end

-- Upper case first letter, including the accented letters of Latin-1 (two bytes in UTF-8,
-- which the client's string.upper leaves as they are).
local function capitalize(text)
    local first, second = text:byte(1, 2)
    if first and first >= 97 and first <= 122 then
        return string.char(first - 32) .. text:sub(2)
    end
    if first == 0xC3 and second and second >= 0xA0 and second <= 0xBE and second ~= 0xB7 then
        return string.char(0xC3, second - 0x20) .. text:sub(3)
    end
    return text
end

local function rowName(item)
    local name = questName(item.id)
    if item.prefix and name:sub(1, #item.prefix) == item.prefix then return capitalize(name:sub(#item.prefix + 1)) end
    return name
end

-- Builds the widgets of one list row.
function QuestWidgets.BuildRow(row)
    UI.DecorateRow(row)
    row.expand = UI.ExpandBox(row, 18)
    row.expand:SetPoint("LEFT", 8, 0)
    row.marker = UI.Glyph(row, "arrow", 12, C.yellow)
    row.marker:SetPoint("LEFT", 12, 0)
    row.name = UI.Text(row, 13)
    row.level = UI.Text(row, 11, C.goldDim, "body", "RIGHT")
    row.level:SetWidth(70)
    row.right = UI.Text(row, 11, C.text, "body", "RIGHT")
    row.right:SetWidth(60)
    row.check = UI.Glyph(row, "check", 16, C.green)
    row.check:SetPoint("RIGHT", -6, 0)
    row.right:SetPoint("RIGHT", row.check, "LEFT", -6, 0)
    row.level:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
end

-- Shows an item in a row; `selected` is the selected quest id.
function QuestWidgets.FillRow(row, item, view, selected)
    local isChain = item.kind == "chain"
    row.expand:SetShown(isChain)
    row.name:ClearAllPoints()
    row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
    row.name:SetPoint("LEFT", row, "LEFT", 34 + (item.indent and 14 or 0), 0)

    if isChain then
        local summary = item.summary
        row.expand:SetExpanded(item.open)
        row.name:SetText(rowName(item))
        local complete = summary.total > 0 and summary.done >= summary.total
        row.name:SetTextColor(Theme.Unpack(complete and C.green or C.gold))
        row.level:SetText(QuestWidgets.LevelText(summary.low, summary.high))
        row.right:SetText(string.format("%d / %d", summary.done, summary.total))
        row.right:SetTextColor(Theme.Unpack(complete and C.green or C.text))
        row.check:Hide()
        row.marker:Hide()
        row:SetState(false, { bg = { 0.13, 0.09, 0.05, 0.95 }, border = C.borderDim })
        return
    end

    local quest = ns.Data.Quests[item.id]
    local status = ns.Quests:Status(item.id, view)
    row.name:SetText(rowName(item))
    row.name:SetTextColor(Theme.Unpack(QuestWidgets.STATUS_COLORS[status] or C.text))
    row.level:SetText(QuestWidgets.LevelText(quest[Q.LEVEL]))
    local xp = quest[Q.XP]
    row.right:SetText(xp and string.format(L.XP_SHORT, xp) or "")
    row.right:SetTextColor(Theme.Unpack(C.textDim))
    row.check:SetShown(status == Status.DONE)
    row.marker:SetShown(status == Status.ACTIVE)
    row:SetState(selected == item.id)
end

-------------------------------------------------------------------------------
-- Details
-------------------------------------------------------------------------------

local followers -- [questID] = { quests that require it }

local function followersOf(questID)
    if not followers then
        followers = {}
        local function add(from, to)
            followers[from] = followers[from] or {}
            table.insert(followers[from], to)
        end
        for id, row in pairs(ns.Data.Quests) do
            for _, pre in ipairs(row[Q.PRE_ALL] or {}) do add(pre, id) end
            for _, pre in ipairs(row[Q.PRE_ANY] or {}) do add(pre, id) end
        end
        for id, row in pairs(ns.Data.Quests) do
            local nextID = row[Q.NEXT]
            if nextID then
                local list = followers[id]
                local present = false
                for _, existing in ipairs(list or {}) do if existing == nextID then present = true end end
                if not present then add(id, nextID) end
            end
        end
        for _, list in pairs(followers) do table.sort(list) end
    end
    return followers[questID]
end

local function nameList(ids)
    if not ids or #ids == 0 then return L.NONE end
    local names = {}
    for _, id in ipairs(ids) do names[#names + 1] = questName(id) end
    return table.concat(names, ", ")
end

local function statusText(status, reason)
    if status == Status.DONE then
        if reason == "exclusive" then return L.STATUS_CLOSED end
        if reason == "breadcrumb" then return L.STATUS_SKIPPED end
        return L.STATUS_DONE
    end
    if status == Status.LOCKED then
        if reason == "level" then return L.STATUS_LOCKED_LEVEL end
        if reason == "skill" then return L.STATUS_LOCKED_SKILL end
        return L.STATUS_LOCKED_PREREQ
    end
    return L["STATUS_" .. status:upper()]
end

-- Location of a giver: uiMapID, x, y, area name — or nil.
local function locate(entity)
    if not entity then return nil end
    local row
    if entity[1] == Entity.NPC then row = ns.Data.Npcs[entity[2]]
    elseif entity[1] == Entity.OBJECT then row = ns.Data.Objects[entity[2]] end
    local place = row and row[2]
    if not place then return nil end
    return place[4], place[2], place[3], ns.Names.Area(place[1])
end

local function entityLine(panel, label, entity)
    local name = ns.Names.Entity(entity)
    if not name then return end
    local uiMap, x, y, areaName = locate(entity)
    local text = string.format("%s %s", Theme.Colorize(label, C.goldDim), name)
    if areaName then text = text .. Theme.Colorize(string.format(" (%s %.0f, %.0f)", areaName, x, y), C.textDim) end
    panel:Line(text)
    if uiMap then
        panel:Button(L.SHOW_ON_MAP, function()
            if ns.Compat.SetWaypoint(uiMap, x, y) then
                ns.Log:Debug("Waypoint set on map %d at %.1f, %.1f", uiMap, x, y)
                print(string.format("|cffffd200%s|r: %s", L.ADDON_TITLE, string.format(L.WAYPOINT_SET, name)))
            else
                ns.Log:Info("Waypoint unavailable on map %s", tostring(uiMap))
                print(string.format("|cffffd200%s|r: %s", L.ADDON_TITLE, L.WAYPOINT_UNAVAILABLE))
            end
        end)
    end
end

-- Fills a detail panel with everything known about a quest.
function QuestWidgets.ShowDetails(panel, questID, view)
    panel:Clear("quest:" .. tostring(questID))
    local quest = ns.Data.Quests[questID]
    if not quest then
        panel:Line(L.SELECT_QUEST, C.textDim)
        panel:Finish()
        return
    end
    local status, reason = ns.Quests:Status(questID, view)
    panel:Line(questName(questID), C.gold, 20, "fancy")
    local levelText = string.format(L.QUEST_LEVEL_LINE, quest[Q.LEVEL], quest[Q.MIN_LEVEL])
    panel:Line(string.format("%s  ·  %s", Theme.Colorize(statusText(status, reason):upper(), QuestWidgets.STATUS_COLORS[status] or C.text),
        Theme.Colorize(levelText, C.green)), C.text, 13)

    local flags = quest[Q.FLAGS]
    local notes = {}
    if ns.Quests.HasFlag(flags, Flag.DAILY) then notes[#notes + 1] = L.FLAG_DAILY end
    if ns.Quests.HasFlag(flags, Flag.WEEKLY) then notes[#notes + 1] = L.FLAG_WEEKLY end
    if ns.Quests.HasFlag(flags, Flag.REPEATABLE) and #notes == 0 then notes[#notes + 1] = L.FLAG_REPEATABLE end
    if ns.Quests.HasFlag(flags, Flag.EVENT) then notes[#notes + 1] = L.FLAG_EVENT end
    if ns.Quests.HasFlag(flags, Flag.BREADCRUMB) then notes[#notes + 1] = L.FLAG_BREADCRUMB end
    if #notes > 0 then panel:Line(table.concat(notes, "  ·  "), C.blue, 11) end
    panel:Space(6)

    local prerequisites = {}
    for _, id in ipairs(quest[Q.PRE_ALL] or {}) do prerequisites[#prerequisites + 1] = id end
    for _, id in ipairs(quest[Q.PRE_ANY] or {}) do prerequisites[#prerequisites + 1] = id end
    panel:Line(string.format("%s %s", Theme.Colorize(L.PREREQUISITES, C.goldDim), nameList(prerequisites)), C.text, 12)
    if quest[Q.PRE_ANY] and #quest[Q.PRE_ANY] > 1 then panel:Line(L.PREREQUISITES_ANY, C.textDim, 11) end
    local nextQuests = followersOf(questID)
    if nextQuests then
        panel:Line(string.format("%s %s", Theme.Colorize(L.FOLLOW_UPS, C.goldDim), nameList(nextQuests)), C.text, 12)
    end
    if quest[Q.EXCLUSIVE] then
        panel:Line(string.format("%s %s", Theme.Colorize(L.EXCLUSIVE_WITH, C.goldDim), nameList(quest[Q.EXCLUSIVE])), C.text, 12)
    end
    if quest[Q.BREADCRUMB_FOR] then
        panel:Line(string.format("%s %s", Theme.Colorize(L.LEADS_TO, C.goldDim), questName(quest[Q.BREADCRUMB_FOR])), C.text, 12)
    end
    local skill = quest[Q.SKILL]
    if skill then
        panel:Line(string.format("%s %s (%d)", Theme.Colorize(L.REQUIRES, C.goldDim),
            ns.Names.SkillLine(skill[1]) or ("#" .. skill[1]), skill[2]), C.text, 12)
    end

    panel:Space(4)
    entityLine(panel, L.GIVER, quest[Q.GIVER])
    if quest[Q.ENDER] and not (quest[Q.GIVER] and quest[Q.ENDER][1] == quest[Q.GIVER][1] and quest[Q.ENDER][2] == quest[Q.GIVER][2]) then
        entityLine(panel, L.ENDER, quest[Q.ENDER])
    end

    local rewards = {}
    if quest[Q.XP] then rewards[#rewards + 1] = string.format(L.XP_LINE, quest[Q.XP]) end
    for _, reputation in ipairs(quest[Q.REPUTATION] or {}) do
        local faction = ns.Names.Faction(reputation[1])
        if faction then rewards[#rewards + 1] = string.format(L.REPUTATION_LINE, reputation[2], faction) end
    end
    if #rewards > 0 then
        panel:Heading(L.REWARDS)
        for _, line in ipairs(rewards) do panel:Line(line, C.text, 12) end
    end

    if status == Status.ACTIVE then
        local objectives = ns.Compat.GetQuestObjectives(questID)
        if objectives then
            panel:Heading(L.OBJECTIVES)
            for _, objective in ipairs(objectives) do
                panel:Line(objective.text, objective.finished and C.green or C.text, 12)
            end
        end
    end
    panel:Finish()
end
