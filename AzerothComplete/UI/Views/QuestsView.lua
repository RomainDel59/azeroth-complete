-- Quests tab: zones on the left, the zone summary and the selected quest in the middle,
-- the zone's quest chains on the right.

local _, ns = ...

local View = {}
ns.Views.Quests = View

local L = ns.L
local UI, Theme, Layout, QuestWidgets = ns.UI, ns.Theme, ns.Layout, ns.QuestWidgets
local C = Theme.colors
local Continent = ns.Const.Continent

local GROUP_BUTTONS = {
    { value = "ek", label = "CONTINENT_EASTERN_KINGDOMS", continents = { Continent.EASTERN_KINGDOMS } },
    { value = "kalimdor", label = "CONTINENT_KALIMDOR", continents = { Continent.KALIMDOR } },
    { value = "other", label = "CONTINENT_OTHER", continents = { Continent.OTHER, Continent.BATTLEGROUNDS } },
    { value = "categories", label = "CONTINENT_CATEGORIES", continents = { Continent.CATEGORIES } },
}

-------------------------------------------------------------------------------
-- Zone cards
-------------------------------------------------------------------------------

local function buildZoneCard(row)
    row.art = UI.Art(row)
    row.art:SetPoint("TOPLEFT", 1, -1)
    row.art:SetPoint("BOTTOMRIGHT", -1, 1)
    row.art.shadeFraction = 0.75
    row.border = UI.Border(row, C.borderDim, 2)
    row.name = UI.Text(row, 14, C.text)
    row.name:SetPoint("BOTTOMLEFT", 12, 8)
    row.count = UI.Text(row, 13, C.text, "body", "RIGHT")
    row.count:SetPoint("BOTTOMRIGHT", -12, 8)
    row.name:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMLEFT", -6, 0)
    row.levels = UI.Text(row, 11, C.goldDim, "body", "RIGHT")
    row.levels:SetPoint("TOPRIGHT", -10, -6)
    row.hover = UI.Solid(row, "HIGHLIGHT", { 1, 0.85, 0.45, 0.08 })
    row.hover:SetAllPoints()
end

function View:FillZoneCard(row, group)
    local summary = ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, self.mainFrame:View())
    row.name:SetText(ns.Quests:GroupName(group))
    row.count:SetText(string.format("%d / %d", summary.done, summary.total))
    local complete = summary.total > 0 and summary.done >= summary.total
    row.count:SetTextColor(Theme.Unpack(complete and C.green or C.text))
    row.levels:SetText(group.levels and QuestWidgets.LevelText(group.levels[1], group.levels[2]) or "")
    if not (group.uiMap and row.art:SetMap(group.uiMap)) then row.art:Clear() end
    local selected = self.selectedGroup == group
    row.border:SetColor(selected and C.gold or (complete and C.greenBorder or C.borderDim))
    row:SetScript("OnClick", function() self:SelectGroup(group) end)
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function View:Build(frame)
    self.expanded = {}
    self.query = ""
    local left, center, right = Layout.Columns(frame)

    -- Left: zones
    Layout.Title(left, L.ZONES, 20, "LEFT")
    local groupButtons = {}
    local buttonWidth = math.floor((Layout.LEFT_WIDTH - 32 - 6) / 2)
    for index, option in ipairs(GROUP_BUTTONS) do
        local button = UI.Button(left, buttonWidth, 26, L[option.label], function() self:SelectContinent(option.value) end)
        local column, line = (index - 1) % 2, math.floor((index - 1) / 2)
        button:SetPoint("TOPLEFT", 16 + column * (buttonWidth + 6), -48 - line * 32)
        button.value = option.value
        groupButtons[#groupButtons + 1] = button
    end
    self.groupButtons = groupButtons

    local search = UI.SearchBox(left, L.SEARCH_ZONE, function(text)
        self.zoneQuery = text
        self:RefreshZones()
    end)
    search:SetPoint("TOPLEFT", 16, -116)
    search:SetPoint("TOPRIGHT", -16, -116)

    self.zones = UI.ScrollList(left, 76, buildZoneCard, function(row, group) self:FillZoneCard(row, group) end, 8)
    self.zones:SetPoint("TOPLEFT", 16, -152)
    self.zones:SetPoint("BOTTOMRIGHT", -8, 12)

    -- Center: summary and selected quest
    self.centerTitle = UI.Text(center, 26, C.gold, "fancy", "CENTER")
    self.centerTitle:SetPoint("TOPLEFT", 12, -14)
    self.centerTitle:SetPoint("TOPRIGHT", -12, -14)
    self.banner = Layout.Banner(center, 150)
    self.banner:SetPoint("TOPLEFT", 16, -52)
    self.banner:SetPoint("TOPRIGHT", -16, -52)

    local detailBox = UI.Panel(center, C.panelDark, C.borderDim)
    detailBox:SetPoint("TOPLEFT", self.banner, "BOTTOMLEFT", 0, -14)
    detailBox:SetPoint("BOTTOMRIGHT", -16, 14)
    local detailTitle = UI.Heading(detailBox, 16, L.SELECTED_QUEST, "fancy")
    detailTitle:SetPoint("TOP", 0, -10)
    self.details = UI.DetailPanel(detailBox)
    self.details:SetPoint("TOPLEFT", 14, -36)
    self.details:SetPoint("BOTTOMRIGHT", -8, 10)

    -- Right: quests of the zone
    self.rightTitle = Layout.Title(right, "", 18)
    local questSearch = UI.SearchBox(right, L.SEARCH_QUEST, function(text)
        self.query = text
        self:RefreshQuests()
    end)
    questSearch:SetPoint("TOPLEFT", 14, -44)
    questSearch:SetPoint("TOPRIGHT", -14, -44)
    self.quests = UI.ScrollList(right, 34, QuestWidgets.BuildRow, function(row, item)
        QuestWidgets.FillRow(row, item, self.mainFrame:View(), self.selectedQuest)
        row:SetScript("OnClick", function() self:OnQuestClick(item) end)
    end, 4)
    self.quests:SetPoint("TOPLEFT", 14, -80)
    self.quests:SetPoint("BOTTOMRIGHT", -6, 36)
    self.questFooter = UI.Text(right, 12, C.text, "body", "CENTER")
    self.questFooter:SetPoint("BOTTOM", 0, 12)

    self:SelectContinent(self:InitialContinent(), true)
end

-------------------------------------------------------------------------------
-- Selection
-------------------------------------------------------------------------------

-- Starts on the continent of the zone the player is in.
function View:InitialContinent()
    local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for _, groups in pairs(ns.Quests:Groups()) do
        for _, group in ipairs(groups) do
            if uiMap and group.uiMap == uiMap then
                self.selectedGroup = group
                for _, option in ipairs(GROUP_BUTTONS) do
                    for _, continent in ipairs(option.continents) do
                        if continent == group.continent then return option.value end
                    end
                end
            end
        end
    end
    return ns.Player.faction == ns.Const.Faction.HORDE and "kalimdor" or "ek"
end

function View:GroupsOf(continentValue)
    self.sortedGroups = self.sortedGroups or {}
    if self.sortedGroups[continentValue] then return self.sortedGroups[continentValue] end
    local option
    for _, candidate in ipairs(GROUP_BUTTONS) do
        if candidate.value == continentValue then option = candidate end
    end
    local groups = {}
    local all = ns.Quests:Groups()
    for _, continent in ipairs(option.continents) do
        for _, group in ipairs(all[continent] or {}) do groups[#groups + 1] = group end
    end
    table.sort(groups, function(a, b)
        local la, lb = a.levels and a.levels[1] or 99, b.levels and b.levels[1] or 99
        if a.kind ~= "sort" and la ~= lb then return la < lb end
        return ns.Quests:GroupName(a) < ns.Quests:GroupName(b)
    end)
    self.sortedGroups[continentValue] = groups
    return groups
end

function View:SelectContinent(value, initial)
    self.continent = value
    for _, button in ipairs(self.groupButtons) do button:SetActive(button.value == value) end
    local groups = self:GroupsOf(value)
    local keep = false
    for _, group in ipairs(groups) do
        if group == self.selectedGroup then keep = true end
    end
    if not keep then self.selectedGroup = groups[1] end
    self:RefreshZones()
    self:SelectGroup(self.selectedGroup, initial)
end

-- Groups of the current continent that match the zone search, with a summary that
-- hides zones without visible quests for the current view.
function View:VisibleGroups()
    local view = self.mainFrame:View()
    local result = {}
    for _, group in ipairs(self:GroupsOf(self.continent)) do
        if UI.Matches(ns.Quests:GroupName(group), self.zoneQuery) then
            local summary = ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, view)
            if summary.total > 0 or group == self.selectedGroup then result[#result + 1] = group end
        end
    end
    return result
end

function View:RefreshZones()
    self.zones:SetItems(self:VisibleGroups(), true)
end

function View:SelectGroup(group, initial)
    if group ~= self.selectedGroup then
        self.selectedQuest = nil
    end
    self.selectedGroup = group
    if group then
        local ids = {}
        for _, chain in ipairs(group.chains) do
            for _, questID in ipairs(chain) do ids[#ids + 1] = questID end
        end
        ns.Names.Prefetch(ids)
        if not initial then ns.Log:Debug("Zone %s:%d selected (%d quests)", group.kind, group.id, #ids) end
    end
    self.quests.offset = 0
    self:Refresh()
end

function View:OnQuestClick(item)
    if item.kind == "chain" then
        self.expanded[item.id] = not self.expanded[item.id]
    end
    self.selectedQuest = item.id
    self:RefreshQuests()
    QuestWidgets.ShowDetails(self.details, item.id, self.mainFrame:View())
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

function View:RefreshQuests()
    local group = self.selectedGroup
    if not group then
        self.quests:SetItems({})
        return
    end
    local view = self.mainFrame:View()
    local items = QuestWidgets.BuildItems(group.chains, view, self.expanded, self.query)
    self.quests:SetItems(items, true)
    local summary = ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, view)
    self.questFooter:SetText(string.format(L.QUESTS_FOOTER, summary.done, summary.total, summary.total - summary.done))
end

function View:Refresh()
    local view = self.mainFrame:View()
    self:RefreshZones()
    local group = self.selectedGroup
    if not group then
        self.centerTitle:SetText("")
        self.rightTitle:SetText(L.QUESTS:upper())
        self.details:Clear()
        self.details:Finish()
        return
    end
    local name = ns.Quests:GroupName(group)
    self.centerTitle:SetText(name)
    self.rightTitle:SetText(string.format(L.QUESTS_OF, name):upper())

    local summary = ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, view)
    local banner = self.banner
    banner.name:SetText(name:upper())
    local continentName = L[GROUP_BUTTONS[1].label]
    for _, option in ipairs(GROUP_BUTTONS) do
        if option.value == self.continent then continentName = L[option.label] end
    end
    local factionName = view.faction == ns.Const.Faction.HORDE and L.FACTION_HORDE or L.FACTION_ALLIANCE
    banner.subtitle:SetText(string.format("%s  ·  %s", continentName, factionName))
    local trackingName = view.tracking == ns.Const.Tracking.ACCOUNT and L.TRACKING_ACCOUNT or L.TRACKING_CHARACTER
    banner.caption:SetText(string.format(L.QUESTS_CAPTION, summary.done, summary.total, trackingName))
    banner.ring:SetProgress(summary.done, summary.total, summary.total > 0 and summary.done >= summary.total and L.COMPLETE or L.DONE)
    if not (group.uiMap and banner.art:SetMap(group.uiMap)) then banner.art:Clear() end

    self:RefreshQuests()
    if self.selectedQuest then
        QuestWidgets.ShowDetails(self.details, self.selectedQuest, view)
    else
        self.details:Clear()
        self.details:Line(L.SELECT_QUEST, C.textDim)
        self.details:Finish()
    end
    self.mainFrame:SetFooter(L.FOOTER_QUESTS)
end
