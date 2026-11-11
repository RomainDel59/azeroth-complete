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

-- Continent maps that stand for a zone whose own artwork cannot be drawn.
local CONTINENT_MAPS = { [Continent.EASTERN_KINGDOMS] = 1415, [Continent.KALIMDOR] = 1414 }
local WORLD_MAP = 947

-------------------------------------------------------------------------------
-- Zone cards
-------------------------------------------------------------------------------

-- Artwork of a zone or a category: the map or the picture chosen by the data (a loading
-- screen for a zone without a map, a talent background for a class); a zone that has none
-- of them shows its continent, darkened.
local function ShowGroupArt(art, group)
    if group.art and group.art ~= 0 then
        if group.artRatio then
            if art:SetFile(group.art, group.artRatio) then return end
        elseif art:SetLoadingScreen(group.art, group.artFramed) then
            return
        end
    elseif group.art == nil and group.uiMap and art:SetMap(group.uiMap) then
        return
    end
    if group.kind == "zone" and group.continent ~= Continent.CATEGORIES
        and art:SetMap(CONTINENT_MAPS[group.continent] or WORLD_MAP, true) then
        return
    end
    art:Clear()
end

local function buildZoneCard(row)
    UI.ArtCard(row)
end

function View:FillZoneCard(row, group)
    local summary = ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, self.mainFrame:View())
    row.name:SetText(ns.Quests:GroupName(group))
    row.count:SetText(string.format("%d / %d", summary.done, summary.total))
    local complete = summary.total > 0 and summary.done >= summary.total
    row.count:SetTextColor(Theme.Unpack(complete and C.green or C.text))
    row.levels:SetText(group.levels and QuestWidgets.LevelText(group.levels[1], group.levels[2]) or "")
    ShowGroupArt(row.art, group)
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

    self.zones = UI.ScrollList(left, UI.ART_CARD_HEIGHT, buildZoneCard, function(row, group) self:FillZoneCard(row, group) end, 6)
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
    self.stateFilter = UI.StateFilter(right, "quests", function()
        self.quests.offset = 0
        self:RefreshQuests()
    end)
    self.stateFilter:SetPoint("TOPLEFT", 14, -74)
    self.quests = UI.ScrollList(right, 34, QuestWidgets.BuildRow, function(row, item)
        QuestWidgets.FillRow(row, item, self.mainFrame:View(), self.selectedQuest)
        row:SetScript("OnClick", function() self:OnQuestClick(item) end)
    end, 4)
    self.quests:SetPoint("TOPLEFT", 14, -104)
    self.quests:SetPoint("BOTTOMRIGHT", -6, 36)
    self.questFooter = UI.Text(right, 12, C.text, "body", "CENTER")
    self.questFooter:SetPoint("BOTTOM", 0, 12)

    self:SelectContinent(self:InitialContinent(), true)
end

-------------------------------------------------------------------------------
-- Selection
-------------------------------------------------------------------------------

-- Starts on the zone the player is in. The client reports the most precise map, which may
-- be a building or a cave inside the zone: its parents are tried in turn.
function View:InitialContinent()
    local maps = ns.Compat.GetPlayerMaps()
    local byMap = {}
    for _, groups in pairs(ns.Quests:Groups()) do
        for _, group in ipairs(groups) do
            -- A category shows the map of a place it is not.
            if group.uiMap and group.continent ~= Continent.CATEGORIES then byMap[group.uiMap] = group end
        end
    end
    for _, uiMap in ipairs(maps) do
        local group = byMap[uiMap]
        if group then
            for _, option in ipairs(GROUP_BUTTONS) do
                for _, continent in ipairs(option.continents) do
                    if continent == group.continent then
                        self.selectedGroup = group
                        return option.value
                    end
                end
            end
        end
    end
    ns.Log:Info("No quest zone matches the player's maps [%s]", table.concat(maps, ", "))
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
    -- Lowest levels first: by minimum level, then maximum level; categories by name.
    table.sort(groups, function(a, b)
        if a.continent ~= Continent.CATEGORIES and b.continent ~= Continent.CATEGORIES then
            local minA, minB = a.levels and a.levels[1] or 99, b.levels and b.levels[1] or 99
            if minA ~= minB then return minA < minB end
            local maxA, maxB = a.levels and a.levels[2] or 99, b.levels and b.levels[2] or 99
            if maxA ~= maxB then return maxA < maxB end
        end
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
    -- Without the player's zone, the first zone that has quests for the current view.
    if not keep then
        local view = self.mainFrame:View()
        self.selectedGroup = groups[1]
        for _, group in ipairs(groups) do
            if ns.Quests:Summary(group.kind .. ":" .. group.id, group.chains, view).total > 0 then
                self.selectedGroup = group
                break
            end
        end
    end
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
    local items = QuestWidgets.BuildItems(group.chains, view, self.expanded, self.query, self.stateFilter)
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
    ShowGroupArt(banner.art, group)

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
