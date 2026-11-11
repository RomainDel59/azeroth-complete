-- Achievements tab (Legacy challenges in WoW Forever): categories on the left, their
-- achievements in the middle, the selected achievement and its criteria on the right.

local _, ns = ...

local View = {}
ns.Views.Achievements = View

local L = ns.L
local UI, Theme, Layout = ns.UI, ns.Theme, ns.Layout
local C = Theme.colors

local function buildCategoryRow(row)
    UI.DecorateRow(row)
    row.name = UI.Text(row, 13)
    row.name:SetPoint("LEFT", 12, 2)
    row.count = UI.Text(row, 12, C.gold, "body", "RIGHT")
    row.count:SetPoint("RIGHT", -10, 2)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.bar = UI.ProgressBar(row, 3)
    row.bar:SetPoint("BOTTOMLEFT", 12, 5)
    row.bar:SetPoint("BOTTOMRIGHT", -10, 5)
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
    local left, center, right = Layout.Columns(frame)

    Layout.Title(left, ns:GameLabel("LEGACY_CHALLENGE_FRAME_TITLE", "ACHIEVEMENTS_TITLE"), 20, "LEFT")
    self.ring = UI.ProgressRing(left, 120)
    self.ring:SetPoint("TOP", 0, -48)
    self.categories = UI.ScrollList(left, 40, buildCategoryRow, function(row, category) self:FillCategory(row, category) end, 5)
    self.categories:SetPoint("TOPLEFT", 16, -184)
    self.categories:SetPoint("BOTTOMRIGHT", -8, 12)

    self.title = UI.Text(center, 26, C.gold, "fancy", "CENTER")
    self.title:SetPoint("TOPLEFT", 12, -14)
    self.title:SetPoint("TOPRIGHT", -12, -14)
    self.subtitle = UI.Text(center, 14, C.green, "body", "CENTER")
    self.subtitle:SetPoint("TOP", self.title, "BOTTOM", 0, -6)
    self.filters = UI.StateFilter(center, "achievements", function() self:Refresh() end)
    self.filters:SetPoint("TOPLEFT", 18, -84)
    self.achievements = UI.ScrollList(center, 42, buildAchievementRow, function(row, id) self:FillAchievement(row, id) end, 3)
    self.achievements:SetPoint("TOPLEFT", 18, -114)
    self.achievements:SetPoint("BOTTOMRIGHT", -8, 14)

    Layout.Title(right, L.DETAILS, 20)
    self.details = UI.DetailPanel(right)
    self.details:SetPoint("TOPLEFT", 16, -50)
    self.details:SetPoint("BOTTOMRIGHT", -8, 12)
end

function View:Tracking()
    return ns.Database:Settings().tracking
end

function View:FillCategory(row, category)
    local summary = ns.Achievements:Summary(category, self:Tracking())
    row.name:SetText(category.name)
    row.count:SetText(string.format("%d / %d", summary.done, summary.total))
    row.bar:SetProgress(summary.done, summary.total)
    row:SetState(self.selected == category.id)
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
    if not ns.Achievements:Available() then
        self.title:SetText(L.ACHIEVEMENTS_TITLE)
        self.subtitle:SetText(L.ACHIEVEMENTS_UNAVAILABLE)
        self.categories:SetItems({})
        self.achievements:SetItems({})
        self.ring:SetProgress(0, 0, "")
        return
    end
    local categories = ns.Achievements:Categories()
    local done, total = 0, 0
    local current
    for _, category in ipairs(categories) do
        local summary = ns.Achievements:Summary(category, tracking)
        done, total = done + summary.done, total + summary.total
        if category.id == self.selected then current = category end
    end
    if not current then
        current = categories[1]
        self.selected = current and current.id
    end
    self.ring:SetProgress(done, total, L.COMPLETED_SHORT)
    self.categories:SetItems(categories, true)
    if current then
        local summary = ns.Achievements:Summary(current, tracking)
        self.title:SetText(current.name)
        self.subtitle:SetText(string.format(L.COMPLETED_COUNT, summary.done, summary.total))
        local listed = {}
        for _, achievementID in ipairs(current.achievements) do
            local entry = ns.Achievements:Get(achievementID, tracking)
            if self.filters:Keeps(entry and entry.completed) then listed[#listed + 1] = achievementID end
        end
        self.achievements:SetItems(listed, true)
    else
        self.title:SetText(L.ACHIEVEMENTS_TITLE)
        self.subtitle:SetText(L.NO_ACHIEVEMENTS)
        self.achievements:SetItems({})
    end
    self:ShowAchievement(self.selectedAchievement)
    self.mainFrame:SetFooter(L.FOOTER_ACHIEVEMENTS)
end
