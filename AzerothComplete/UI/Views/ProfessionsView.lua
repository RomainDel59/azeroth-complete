-- Professions tab, on the page of every tab: professions on the left, the selected
-- profession and recipe (reagents and how to obtain it) in the middle, the recipe catalogue
-- on the right.

local _, ns = ...

local View = {}
ns.Views.Professions = View

local L = ns.L
local UI, Theme, Layout = ns.UI, ns.Theme, ns.Layout
local C = Theme.colors
local R = ns.Const.Recipe


local function recipeName(recipe)
    local created = recipe[R.CREATED_ITEM]
    return ns.Names.Spell(recipe[R.SPELL]) or (created and ns.Names.Item(created)) or L.LOADING
end

local function recipeIcon(recipe)
    local created = recipe[R.CREATED_ITEM]
    return (created and ns.Compat.GetItemIcon(created)) or ns.Compat.GetSpellIcon(recipe[R.SPELL])
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------

local function buildProfessionCard(row)
    UI.ArtCard(row)
end

local function buildRecipeRow(row)
    UI.DecorateRow(row)
    row.icon = UI.FramedIcon(row, 26)
    row.icon:SetPoint("LEFT", 6, 0)
    row.name = UI.Text(row, 13)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.right = UI.Text(row, 11, C.orange, "body", "RIGHT")
    row.right:SetPoint("RIGHT", -10, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function View:Build(frame)
    self.query, self.professionQuery = "", ""
    local page = Layout.Page(frame, {
        groupsTitle = L.PROFESSIONS_TITLE,
        groupSearch = L.SEARCH,
        onGroupSearch = function(text)
            self.professionQuery = text
            self:Refresh()
        end,
        buildGroup = buildProfessionCard,
        fillGroup = function(row, profession) self:FillProfessionRow(row, profession) end,
        detailsTitle = L.SELECTED_RECIPE,
        itemSearch = L.SEARCH_RECIPE,
        onItemSearch = function(text)
            self.query = text
            self:RefreshRecipes()
        end,
        filterKey = "recipes",
        onFilter = function() self:RefreshRecipes() end,
        buildItem = buildRecipeRow,
        fillItem = function(row, recipe) self:FillRecipeRow(row, recipe) end,
        itemSpacing = 3,
    })
    self.page = page
    self.professions, self.recipes, self.filters = page.groups, page.items, page.filters
    self.title, self.banner, self.details = page.title, page.banner, page.details
    self.recipesTitle, self.recipeCount = page.itemsTitle, page.footer
end

-------------------------------------------------------------------------------
-- Rows content
-------------------------------------------------------------------------------

function View:FillProfessionRow(row, profession)
    local tracking = ns.Database:Settings().tracking
    row.name:SetText(ns.Names.SkillLine(profession.skillLine) or ("#" .. profession.skillLine))
    local rank = ns.Professions:Rank(profession.skillLine, tracking)
    row.levels:SetText(rank and string.format(L.RANK_OF, rank.rank, rank.maxRank) or L.NOT_LEARNED)
    local summary = ns.Professions:Summary(profession.skillLine, self.known)
    local complete = summary.total > 0 and summary.done >= summary.total
    row.count:SetText(#profession.recipes > 0 and string.format("%d / %d", summary.done, summary.total) or "")
    row.count:SetTextColor(Theme.Unpack(complete and C.green or C.text))
    if not row.art:SetArtwork(ns.Data.Artwork.professions[profession.skillLine]) then row.art:Clear() end
    row.border:SetColor(self.selected == profession.skillLine and C.gold or (complete and C.greenBorder or C.borderDim))
    row:SetScript("OnClick", function()
        self.selected = profession.skillLine
        self.selectedRecipe = nil
        self.recipes.offset = 0
        self:Refresh()
    end)
end

function View:FillRecipeRow(row, recipe)
    local spellID = recipe[R.SPELL]
    local known = self.known[spellID]
    row.icon:SetIcon(recipeIcon(recipe))
    row.name:SetText(recipeName(recipe))
    if known then
        local difficulty = ns.Professions.Difficulty(recipe, self.rankValue)
        row.name:SetTextColor(Theme.Unpack(difficulty and Theme.difficulty[difficulty] or C.green))
        row.right:SetText(string.format(L.RANK_SHORT, recipe[R.MIN_RANK]))
        row.right:SetTextColor(Theme.Unpack(C.goldDim))
        row:SetState(self.selectedRecipe == spellID, { bg = { 0.05, 0.16, 0.07, 0.95 }, border = C.greenBorder })
    else
        row.name:SetTextColor(Theme.Unpack(C.text))
        row.right:SetText(L.TO_OBTAIN:upper())
        row.right:SetTextColor(Theme.Unpack(C.orange))
        row:SetState(self.selectedRecipe == spellID)
    end
    row:SetScript("OnClick", function()
        self.selectedRecipe = spellID
        self.recipes:Redraw()
        self:ShowRecipe(recipe)
    end)
end

-------------------------------------------------------------------------------
-- Recipe details
-------------------------------------------------------------------------------

local function npcText(npcID)
    local name = ns.Names.Npc(npcID) or ("#" .. npcID)
    local row = ns.Data.Npcs[npcID]
    local place = row and row[2]
    if place then
        return string.format("%s %s", name, Theme.Colorize(string.format("(%s)", ns.Names.Area(place[1]) or "?"), C.textDim)), place
    end
    return name, nil
end

local function waypointButton(panel, place, label)
    if not (place and place[4]) then return end
    panel:Button(L.SHOW_ON_MAP, function()
        if ns.Compat.SetWaypoint(place[4], place[2], place[3]) then
            print(string.format("|cffffd200%s|r: %s", L.ADDON_TITLE, string.format(L.WAYPOINT_SET, label)))
        else
            print(string.format("|cffffd200%s|r: %s", L.ADDON_TITLE, L.WAYPOINT_UNAVAILABLE))
        end
    end)
end

function View:ShowRecipe(recipe)
    local panel = self.details
    panel:Clear(recipe and ("recipe:" .. recipe[R.SPELL]) or nil)
    if not recipe then
        panel:Line(L.SELECT_RECIPE, C.textDim)
        panel:Finish()
        return
    end
    local spellID = recipe[R.SPELL]
    local known = self.known[spellID]
    panel:Title(recipeIcon(recipe), recipeName(recipe), known and L.RECIPE_LEARNED or L.RECIPE_TO_LEARN, C.gold,
        known and C.green or C.orange)
    panel:Line(string.format(L.REQUIRED_RANK, recipe[R.MIN_RANK]), C.text, 12)
    if recipe[R.TRIVIAL_HIGH] > 0 then
        panel:Line(string.format(L.SKILL_UP_RANGE, recipe[R.TRIVIAL_LOW], recipe[R.TRIVIAL_HIGH]), C.textDim, 11)
    end

    local created = recipe[R.CREATED_ITEM]
    if created then
        panel:Heading(L.CREATES)
        panel:IconLine(ns.Compat.GetItemIcon(created), ns.Names.Item(created) or L.LOADING, nil, C.text, nil, function(tooltip)
            tooltip:SetHyperlink("item:" .. created)
        end)
    end

    panel:Heading(L.REAGENTS)
    for _, reagent in ipairs(recipe[R.REAGENTS] or {}) do
        local itemID, count = reagent[1], reagent[2]
        panel:IconLine(ns.Compat.GetItemIcon(itemID), ns.Names.Item(itemID) or L.LOADING, "x" .. count, C.text, nil,
            function(tooltip) tooltip:SetHyperlink("item:" .. itemID) end)
    end

    panel:Heading(L.HOW_TO_OBTAIN)
    local sources = recipe[R.SOURCES]
    if recipe[R.AUTO_LEARNED] == 1 then
        panel:Line(L.SOURCE_AUTO, C.text, 12)
    elseif not sources then
        panel:Line(L.SOURCE_TRAINER, C.text, 12)
    end
    for _, source in ipairs(sources or {}) do
        local recipeItem = source.item
        panel:IconLine(ns.Compat.GetItemIcon(recipeItem), ns.Names.Item(recipeItem) or L.LOADING, nil, C.gold, nil,
            function(tooltip) tooltip:SetHyperlink("item:" .. recipeItem) end)
        local any = false
        for _, npcID in ipairs(source.vendors or {}) do
            local text, place = npcText(npcID)
            panel:Line(string.format("%s %s", Theme.Colorize(L.SOURCE_VENDOR, C.goldDim), text), C.text, 12, nil, 8)
            waypointButton(panel, place, ns.Names.Npc(npcID) or "")
            any = true
        end
        for _, npcID in ipairs(source.npcDrops or {}) do
            local text, place = npcText(npcID)
            panel:Line(string.format("%s %s", Theme.Colorize(L.SOURCE_DROP, C.goldDim), text), C.text, 12, nil, 8)
            waypointButton(panel, place, ns.Names.Npc(npcID) or "")
            any = true
        end
        for _, objectID in ipairs(source.objectDrops or {}) do
            panel:Line(string.format("%s %s", Theme.Colorize(L.SOURCE_OBJECT, C.goldDim),
                ns.Names.Object(objectID) or ("#" .. objectID)), C.text, 12, nil, 8)
            any = true
        end
        for _, questID in ipairs(source.questRewards or {}) do
            panel:Line(string.format("%s %s", Theme.Colorize(L.SOURCE_QUEST, C.goldDim),
                ns.Names.Quest(questID) or L.LOADING), C.text, 12, nil, 8)
            any = true
        end
        if not any then panel:Line(L.SOURCE_UNKNOWN, C.textDim, 11, nil, 8) end
    end
    panel:Finish()
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

function View:RefreshRecipes()
    local profession = self.selected and ns.Professions:Get(self.selected)
    if not profession then
        self.recipes:SetItems({})
        self.recipeCount:SetText("")
        return
    end
    local items = {}
    for _, recipe in ipairs(profession.recipes) do
        if self.filters:Keeps(self.known[recipe[R.SPELL]]) and (self.query == "" or UI.Matches(recipeName(recipe), self.query)) then items[#items + 1] = recipe end
    end
    self.recipes:SetItems(items, true)
    self.recipeCount:SetText(string.format(L.RECIPES_LISTED, #items))
end

-- The character has learned no profession: the filter leaves nothing to show.
function View:ShowEmpty()
    self.rankValue = nil
    self.title:SetText("")
    local banner = self.banner
    banner.name:SetText("")
    banner.subtitle:SetText(L.NO_PROFESSION_LEARNED)
    banner.caption:SetText("")
    banner.ring:SetProgress(0, 0, "")
    banner.art:Clear()
    self.recipesTitle:SetText(L.RECIPES:upper())
    self.recipes:SetItems({})
    self.recipeCount:SetText("")
    self:ShowRecipe(nil)
    self.mainFrame:SetFooter(L.FOOTER_PROFESSIONS)
end

function View:Refresh()
    local tracking = ns.Database:Settings().tracking
    self.known = ns.Professions:Known(tracking)
    local list = {}
    for _, profession in ipairs(ns.Professions:Shown(self.mainFrame:View())) do
        if UI.Matches(ns.Names.SkillLine(profession.skillLine) or "", self.professionQuery) then list[#list + 1] = profession end
    end
    local listed = false
    for _, profession in ipairs(list) do
        if profession.skillLine == self.selected then listed = true end
    end
    if not listed then
        self.selected, self.selectedRecipe = nil, nil
    end
    self.professions:SetItems(list, true)
    if #list == 0 then
        self:ShowEmpty()
        return
    end
    if not self.selected then
        for _, profession in ipairs(list) do
            if ns.Professions:Rank(profession.skillLine, tracking) and #profession.recipes > 0 then
                self.selected = profession.skillLine
                break
            end
        end
        self.selected = self.selected or (list[1] and list[1].skillLine)
    end

    local profession = ns.Professions:Get(self.selected)
    local rank = ns.Professions:Rank(self.selected, tracking)
    self.rankValue = rank and rank.rank
    local name = ns.Names.SkillLine(self.selected) or ""
    self.title:SetText(name)
    local summary = ns.Professions:Summary(self.selected, self.known)
    local banner = self.banner
    banner.name:SetText(name:upper())
    banner.subtitle:SetText(rank and string.format(L.CURRENT_RANK, rank.rank, rank.maxRank) or L.NOT_LEARNED)
    local trackingName = tracking == ns.Const.Tracking.ACCOUNT and L.TRACKING_ACCOUNT or L.TRACKING_CHARACTER
    banner.caption:SetText(string.format(L.RECIPES_CAPTION, summary.done, summary.total, trackingName))
    banner.ring:SetProgress(summary.done, summary.total, summary.total > 0 and summary.done >= summary.total and L.COMPLETE or L.DONE)
    if not banner.art:SetArtwork(ns.Data.Artwork.professions[self.selected]) then banner.art:Clear() end
    self.recipesTitle:SetText(string.format(L.RECIPES_OF, name):upper())
    self:RefreshRecipes()

    local selectedRecipe
    for _, recipe in ipairs(profession and profession.recipes or {}) do
        if recipe[R.SPELL] == self.selectedRecipe then selectedRecipe = recipe end
    end
    self:ShowRecipe(selectedRecipe)
    self.mainFrame:SetFooter(L.FOOTER_PROFESSIONS)
end
