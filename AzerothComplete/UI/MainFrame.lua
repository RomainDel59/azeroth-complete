-- Main window: header, tabs, faction and tracking selectors, footer, and the active view.
--
-- Views are created on first display. Each view is a table with Build(frame) and
-- Refresh(); MainFrame calls Refresh when the view is shown and whenever progress, names
-- or settings change while it is visible.

local _, ns = ...

local MainFrame = {}
ns.MainFrame = MainFrame

local L = ns.L
local UI, Theme = ns.UI, ns.Theme
local C = Theme.colors
local Tracking, Faction = ns.Const.Tracking, ns.Const.Faction

local WIDTH, HEIGHT = 1200, 680
local CONTENT_TOP = 168

ns.Views = ns.Views or {}

-- Tab order and the view that renders each tab.
-- `global` names the client's own label when it has one (see ns:GameLabel).
local TABS = {
    { id = "quests", global = "QUESTS_LABEL", label = "TAB_QUESTS", icon = "quests", view = "Quests" },
    { id = "professions", global = "TRADE_SKILLS", label = "TAB_PROFESSIONS", icon = "professions", view = "Professions" },
    { id = "dungeons", global = "DUNGEONS", label = "TAB_DUNGEONS", icon = "dungeons", view = "Dungeons" },
    { id = "raids", global = "RAIDS", label = "TAB_RAIDS", icon = "raids", view = "Raids" },
    { id = "achievements", global = "LEGACY_CHALLENGE_FRAME_TITLE", label = "TAB_ACHIEVEMENTS", icon = "achievements", view = "Achievements" },
    { id = "collections", label = "TAB_COLLECTIONS", icon = "collections", view = "Collections" },
}

-- State shared by every view: the faction shown and the tracking mode.
MainFrame.state = { faction = nil }

function MainFrame:View()
    return ns.Quests:CurrentView(self.state.faction)
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

-- Tooltip of a progress: the percentage, then what it counts.
local function progressLine(counts)
    if counts.total == 0 then return L.UNAVAILABLE end
    return string.format(L.PROGRESS_TOOLTIP, math.floor(counts.done / counts.total * 100), counts.done, counts.total)
end

local function buildHeader(frame)
    -- Overall progress: every tab weighs the same.
    local ring = UI.ProgressRing(frame, 96)
    ring:SetPoint("TOPLEFT", 18, -10)
    ring:EnableMouse(true)
    ring:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.OVERALL_PROGRESS, 1, 0.82, 0)
        local progress = MainFrame.progress
        if progress then
            for _, tab in ipairs(TABS) do
                GameTooltip:AddDoubleLine(ns:GameLabel(tab.global, tab.label), progressLine(progress[tab.id]), 1, 1, 1, 1, 1, 1)
            end
        end
        GameTooltip:AddLine(L.OVERALL_PROGRESS_NOTE, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    ring:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.ring = ring

    local title = UI.Text(frame, 30, C.gold, "body", "CENTER")
    title:SetPoint("TOP", 0, -22)
    title:SetText(L.ADDON_TITLE:upper())
    local subtitle = UI.Text(frame, 15, C.text, "body", "CENTER")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -8)
    subtitle:SetText(L.ADDON_SUBTITLE)

    local close = UI.CloseButton(frame, 26, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -14)

    -- The header drags the window.
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 120, 0)
    drag:SetPoint("TOPRIGHT", -50, 0)
    drag:SetHeight(84)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        ns.Database:Settings().position = { point, relativePoint, x, y }
    end)
end

local function buildTabs(frame)
    frame.tabs = {}
    local count = #TABS
    local spacing = 8
    local left = 132
    local width = math.floor((WIDTH - left - 24 - spacing * (count - 1)) / count)
    for index, tab in ipairs(TABS) do
        local button = UI.TabButton(frame, width, 36, Theme.icons[tab.icon], ns:GameLabel(tab.global, tab.label), function()
            MainFrame:SelectTab(tab.id)
        end)
        button:SetPoint("TOPLEFT", left + (index - 1) * (width + spacing), -92)
        -- Progress of the tab, a thin bar along its bottom edge, its figures in the tooltip.
        button.progress = UI.ProgressBar(button, 3)
        button.progress:SetPoint("BOTTOMLEFT", 1, 1)
        button.progress:SetPoint("BOTTOMRIGHT", -1, 1)
        button:SetScript("OnEnter", function(self)
            local progress = MainFrame.progress
            if not progress then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.label:GetText() or "", 1, 0.82, 0)
            GameTooltip:AddLine(progressLine(progress[tab.id]), 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button.tab = tab
        frame.tabs[tab.id] = button
    end
    local rule = UI.Solid(frame, "ARTWORK", C.borderDim)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 120, -134)
    rule:SetPoint("TOPRIGHT", -24, -134)
end

-- The three switches of the header share one style and spread over the width of the window:
-- the faction on the left, the tracking mode in the middle, the filter on the right.
local function buildSelectors(frame)
    local faction = UI.Toggle(frame, L.FACTION_LABEL, function()
        local current = MainFrame.state.faction or ns.Player.faction
        MainFrame.state.faction = current == Faction.ALLIANCE and Faction.HORDE or Faction.ALLIANCE
        ns.Log:Debug("Faction shown: %s", MainFrame.state.faction)
        MainFrame:Refresh()
    end)
    faction:SetPoint("TOPLEFT", 28, -142)
    frame.faction = faction

    local tracking = UI.Toggle(frame, L.TRACKING_LABEL, function()
        local settings = ns.Database:Settings()
        settings.tracking = settings.tracking == Tracking.ACCOUNT and Tracking.CHARACTER or Tracking.ACCOUNT
        ns.Log:Debug("Tracking mode: %s", settings.tracking)
        MainFrame:Refresh()
    end)
    tracking:SetPoint("TOP", 0, -142)
    frame.tracking = tracking

    local filter = UI.Toggle(frame, L.FILTER_LABEL, function()
        local settings = ns.Database:Settings()
        settings.possibleOnly = settings.possibleOnly == false
        ns.Log:Debug("Character filter: %s", tostring(settings.possibleOnly))
        MainFrame:Refresh()
    end)
    filter:SetPoint("TOPRIGHT", -28, -142)
    frame.filter = filter
end

local function buildFooter(frame)
    local footer = UI.Text(frame, 12, C.textDim, "body", "CENTER")
    footer:SetPoint("BOTTOM", 0, 14)
    frame.footer = footer
end

local function create()
    local frame = CreateFrame("Frame", "AzerothCompleteFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    local bg = UI.Solid(frame, "BACKGROUND", C.window)
    bg:SetAllPoints()
    UI.Border(frame, C.border, 2)
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", -6, 6)
    UI.Border(inner, C.borderDim)

    buildHeader(frame)
    buildTabs(frame)
    buildSelectors(frame)
    buildFooter(frame)

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", 24, -CONTENT_TOP)
    frame.content:SetPoint("BOTTOMRIGHT", -24, 38)
    frame.views = {}

    frame:SetScript("OnShow", function()
        ns.Log:Debug("Window shown")
        MainFrame:Refresh()
    end)
    table.insert(UISpecialFrames, "AzerothCompleteFrame") -- closes with Escape
    return frame
end

-------------------------------------------------------------------------------
-- Behaviour
-------------------------------------------------------------------------------

function MainFrame:Frame()
    if not self.frame then
        self.frame = create()
        local settings = ns.Database:Settings()
        self.frame:SetScale(settings.scale or 1)
        local position = settings.position
        if position then
            self.frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
        else
            self.frame:SetPoint("CENTER")
        end
        self:SelectTab(settings.tab or "quests", true)
    end
    return self.frame
end

function MainFrame:SelectTab(id, silent)
    local frame = self:Frame()
    local tab
    for _, candidate in ipairs(TABS) do
        if candidate.id == id then tab = candidate end
    end
    tab = tab or TABS[1]
    for tabID, button in pairs(frame.tabs) do button:SetActive(tabID == tab.id) end
    for _, view in pairs(frame.views) do view.frame:Hide() end

    local view = frame.views[tab.id]
    if not view then
        local definition = ns.Views[tab.view]
        view = setmetatable({ mainFrame = self }, { __index = definition })
        view.frame = CreateFrame("Frame", nil, frame.content)
        view.frame:SetAllPoints()
        ns:SafeCall("view " .. tab.id .. " build", view.Build, view, view.frame)
        frame.views[tab.id] = view
    end
    view.frame:Show()
    self.activeView = view
    self.activeTab = tab.id
    ns.Database:Settings().tab = tab.id
    if not silent then ns.Log:Debug("Tab %s", tab.id) end
    self:Refresh()
end

-- Redraws the selectors and the active view.
function MainFrame:Refresh()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local faction = self.state.faction or ns.Player.faction
    local horde = faction == Faction.HORDE
    frame.faction:SetValue(horde and Theme.icons.horde or Theme.icons.alliance,
        horde and L.FACTION_HORDE or L.FACTION_ALLIANCE, L.FACTION_TOOLTIP)
    local settings = ns.Database:Settings()
    local account = settings.tracking == Tracking.ACCOUNT
    frame.tracking:SetValue(account and Theme.icons.account or Theme.icons.character,
        account and L.TRACKING_ACCOUNT or L.TRACKING_CHARACTER,
        account and L.TRACKING_TOOLTIP_ACCOUNT or L.TRACKING_TOOLTIP_CHARACTER)
    local possible = settings.possibleOnly ~= false
    frame.filter:SetValue(possible and Theme.icons.possible or Theme.icons.everything,
        possible and L.FILTER_POSSIBLE or L.FILTER_EVERYTHING,
        possible and L.FILTER_TOOLTIP_POSSIBLE or L.FILTER_TOOLTIP_EVERYTHING)
    frame.filter:SetAvailable(not account and faction == ns.Player.faction, L.FILTER_UNAVAILABLE)
    local view = self.activeView
    if view and view.Refresh then
        ns:SafeCall("view " .. tostring(self.activeTab) .. " refresh", view.Refresh, view)
    end
    self:ScheduleProgress()
end

-- The gauges count every tab: they are drawn on the next frame, after the view, and only
-- while the window is shown.
function MainFrame:ScheduleProgress()
    if self.progressScheduled then return end
    self.progressScheduled = true
    C_Timer.After(0, function()
        self.progressScheduled = nil
        ns:SafeCall("progress", self.RefreshProgress, self)
    end)
end

function MainFrame:RefreshProgress()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local progress = ns.Progress:Compute(self:View())
    self.progress = progress
    for _, tab in ipairs(TABS) do
        local counts = progress[tab.id]
        frame.tabs[tab.id].progress:SetProgress(counts.done, counts.total)
    end
    local overall = progress.overall
    if overall then
        frame.ring:SetProgress(math.floor(overall * 1000), 1000, overall >= 1 and L.COMPLETE or L.OVERALL)
    else
        frame.ring:SetProgress(0, 0, "")
    end
end

function MainFrame:SetFooter(text)
    if self.frame then self.frame.footer:SetText(text or "") end
end

function MainFrame:Toggle()
    local frame = self:Frame()
    frame:SetShown(not frame:IsShown())
end

function MainFrame:SetScale(scale)
    ns.Database:Settings().scale = scale
    if self.frame then self.frame:SetScale(scale) end
end

ns:RegisterMessage("AC_PROGRESS_CHANGED", function() MainFrame:Refresh() end)
ns:RegisterMessage("AC_NAMES_UPDATED", function() MainFrame:Refresh() end)
ns:RegisterMessage("AC_COLLECTIONS_CHANGED", function() MainFrame:Refresh() end)
