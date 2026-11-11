-- Achievements tab (Legacy challenges in WoW Forever), on the page of every tab: categories
-- on the left, the selected category and achievement (criteria, reward) in the middle, the
-- achievements of the category on the right.

local _, ns = ...

local View = {}
ns.Views.Achievements = View

local L = ns.L
local UI, Theme, Layout = ns.UI, ns.Theme, ns.Layout
local C = Theme.colors

local function buildCategoryCard(row)
    UI.ArtCard(row)
end

-- Artwork of the categories, which the client defines: a category named after a class shows
-- its talent background, one named after a profession its loading screen, and the others
-- take loading screens from the pool, so that no two cards of the list look the same.
local function categoryArtwork(categories)
    local artwork = ns.Data.Artwork
    local byName = {}
    for classID, entry in pairs(artwork.classes) do
        local name = ns.Compat.GetClassName(classID)
        if name then byName[name] = entry end
    end
    for skillLine, entry in pairs(artwork.professions) do
        local name = ns.Names.SkillLine(skillLine)
        if name then byName[name] = entry end
    end
    local result, used = {}, {}
    for _, category in ipairs(categories) do
        local entry = byName[category.name]
        if entry and not used[entry.art] then
            result[category.id] = entry
            used[entry.art] = true
        end
    end
    local next = 1
    for _, category in ipairs(categories) do
        if not result[category.id] then
            while artwork.pool[next] and used[artwork.pool[next].art] do next = next + 1 end
            local entry = artwork.pool[next]
            if entry then
                result[category.id] = entry
                used[entry.art] = true
            end
        end
    end
    return result
end

local function buildAchievementRow(row)
    UI.DecorateRow(row)
    row.icon = UI.FramedIcon(row, 30)
    row.icon:SetPoint("LEFT", 6, 0)
    row.name = UI.Text(row, 13)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.description = UI.Text(row, 11, C.textDim)
    row.description:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 2)
    row.check = UI.Glyph(row, "check", 16, C.green)
    row.check:SetPoint("RIGHT", -8, 0)
    row.points = UI.Text(row, 12, C.gold, "body", "RIGHT")
    row.points:SetPoint("RIGHT", row.check, "LEFT", -6, 0)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -70, -8)
    row.description:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -70, 8)
end

function View:Build(frame)
    self.query, self.categoryQuery = "", ""
    local page = Layout.Page(frame, {
        groupsTitle = ns:GameLabel("LEGACY_CHALLENGE_FRAME_TITLE", "ACHIEVEMENTS_TITLE"),
        groupSearch = L.SEARCH,
        onGroupSearch = function(text)
            self.categoryQuery = text
            self:Refresh()
        end,
        buildGroup = buildCategoryCard,
        fillGroup = function(row, category) self:FillCategory(row, category) end,
        detailsTitle = L.SELECTED_ENTRY,
        itemSearch = L.SEARCH,
        onItemSearch = function(text)
            self.query = text
            self:Refresh()
        end,
        filterKey = "achievements",
        onFilter = function() self:Refresh() end,
        itemHeight = 42,
        buildItem = buildAchievementRow,
        fillItem = function(row, id) self:FillAchievement(row, id) end,
        itemSpacing = 3,
    })
    self.page = page
    self.categories, self.achievements, self.filters = page.groups, page.items, page.filters
    self.title, self.banner, self.details = page.title, page.banner, page.details
    self.achievementsTitle, self.count = page.itemsTitle, page.footer
end

function View:Tracking()
    return ns.Database:Settings().tracking
end

function View:FillCategory(row, category)
    local summary = ns.Achievements:Summary(category, self:Tracking())
    row.name:SetText(category.name)
    row.levels:SetText("")
    local complete = summary.total > 0 and summary.done >= summary.total
    row.count:SetText(string.format("%d / %d", summary.done, summary.total))
    row.count:SetTextColor(Theme.Unpack(complete and C.green or C.text))
    if not row.art:SetArtwork(self.artwork and self.artwork[category.id]) then row.art:Clear() end
    row.border:SetColor(self.selected == category.id and C.gold or (complete and C.greenBorder or C.borderDim))
    row:SetScript("OnClick", function()
        self.selected = category.id
        self.selectedAchievement = nil
        self.achievements.offset = 0
        self:Refresh()
    end)
end

function View:FillAchievement(row, achievementID)
    local entry = ns.Achievements:Get(achievementID, self:Tracking())
    if not entry then return end
    row.icon:SetIcon(entry.icon)
    row.name:SetText(entry.name)
    row.name:SetTextColor(Theme.Unpack(entry.completed and C.green or C.text))
    row.description:SetText(entry.description or "")
    row.points:SetText(entry.points and entry.points > 0 and tostring(entry.points) or "")
    row.check:SetShown(entry.completed)
    row:SetState(self.selectedAchievement == achievementID)
    row:SetScript("OnClick", function()
        self.selectedAchievement = achievementID
        self.achievements:Redraw()
        self:ShowAchievement(achievementID)
    end)
end

function View:ShowAchievement(achievementID)
    local panel = self.details
    panel:Clear(achievementID and ("achievement:" .. achievementID) or nil)
    local entry = achievementID and ns.Achievements:Get(achievementID, self:Tracking())
    if not entry then
        panel:Line(L.SELECT_ENTRY, C.textDim)
        panel:Finish()
        return
    end
    panel:Title(entry.icon, entry.name, entry.completed and (entry.date and string.format(L.EARNED_ON, entry.date) or L.COMPLETED)
        or L.IN_PROGRESS, C.gold, entry.completed and C.green or C.orange)
    if entry.points and entry.points > 0 then panel:Line(string.format(L.POINTS, entry.points), C.gold, 12) end
    if entry.description then
        panel:Space(4)
        panel:Line(entry.description, C.text, 12)
    end
    local criteria = ns.Achievements:Criteria(achievementID)
    if #criteria > 0 then
        panel:Heading(L.CRITERIA)
        for _, criterion in ipairs(criteria) do
            local text = criterion.text ~= "" and criterion.text or L.CRITERION
            if criterion.required and criterion.required > 1 then
                text = string.format("%s (%d / %d)", text, math.min(criterion.quantity or 0, criterion.required), criterion.required)
            end
            panel:Line((criterion.completed and "+ " or "- ") .. text, criterion.completed and C.green or C.text, 12)
        end
    end
    if entry.reward then
        panel:Heading(L.REWARD)
        panel:Line(entry.reward, C.gold, 12)
    end
    panel:Finish()
end

function View:Refresh()
    local tracking = self:Tracking()
    local banner = self.banner
    if not ns.Achievements:Available() then
        self.title:SetText(L.ACHIEVEMENTS_TITLE)
        banner.name:SetText("")
        banner.subtitle:SetText(L.ACHIEVEMENTS_UNAVAILABLE)
        banner.caption:SetText("")
        banner.ring:SetProgress(0, 0, "")
        banner.art:Clear()
        self.categories:SetItems({})
        self.achievements:SetItems({})
        return
    end
    local categories = ns.Achievements:Categories()
    if self.artworkFor ~= categories then
        self.artwork, self.artworkFor = categoryArtwork(categories), categories
    end
    local done, total = 0, 0
    local current
    local listedCategories = {}
    for _, category in ipairs(categories) do
        local summary = ns.Achievements:Summary(category, tracking)
        done, total = done + summary.done, total + summary.total
        if category.id == self.selected then current = category end
        if UI.Matches(category.name, self.categoryQuery) then listedCategories[#listedCategories + 1] = category end
    end
    if not current then
        current = categories[1]
        self.selected = current and current.id
    end
    self.page.groupsCount:SetText(string.format("%d / %d", done, total))
    self.categories:SetItems(listedCategories, true)
    if current then
        local summary = ns.Achievements:Summary(current, tracking)
        self.title:SetText(current.name)
        banner.name:SetText(current.name:upper())
        banner.subtitle:SetText(ns:GameLabel("LEGACY_CHALLENGE_FRAME_TITLE", "ACHIEVEMENTS_TITLE"))
        banner.caption:SetText(string.format(L.COMPLETED_COUNT, summary.done, summary.total))
        banner.ring:SetProgress(summary.done, summary.total, summary.total > 0 and summary.done >= summary.total and L.COMPLETE or L.DONE)
        if not banner.art:SetArtwork(self.artwork[current.id]) then banner.art:Clear() end
        self.achievementsTitle:SetText(current.name:upper())
        local listed = {}
        for _, achievementID in ipairs(current.achievements) do
            local entry = ns.Achievements:Get(achievementID, tracking)
            if self.filters:Keeps(entry and entry.completed) and UI.Matches(entry and entry.name or "", self.query) then
                listed[#listed + 1] = achievementID
            end
        end
        self.achievements:SetItems(listed, true)
        self.count:SetText(string.format(L.ENTRIES_LISTED, #listed))
    else
        self.title:SetText(L.ACHIEVEMENTS_TITLE)
        banner.name:SetText("")
        banner.subtitle:SetText(L.NO_ACHIEVEMENTS)
        banner.caption:SetText("")
        banner.ring:SetProgress(0, 0, "")
        banner.art:Clear()
        self.achievementsTitle:SetText("")
        self.count:SetText("")
        self.achievements:SetItems({})
    end
    self:ShowAchievement(self.selectedAchievement)
    self.mainFrame:SetFooter(L.FOOTER_ACHIEVEMENTS)
end
