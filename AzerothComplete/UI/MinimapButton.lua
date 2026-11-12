-- Minimap button and addon compartment entry. The button can be dragged around the
-- minimap; its angle is saved.

local _, ns = ...

local MinimapButton = ns:RegisterModule("MinimapButton")

local L = ns.L
local RADIUS = 104

local function place(button, angle)
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * RADIUS, math.sin(radians) * RADIUS)
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(L.ADDON_TITLE, 1, 0.82, 0.25)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP, 1, 1, 1, true)
    GameTooltip:Show()
end

function MinimapButton:OnLogin()
    local settings = ns.Database:Settings().minimap
    if not Minimap then return end
    local button = CreateFrame("Button", "AzerothCompleteMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    background:SetColorTexture(0, 0, 0, 0.6)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ns.Theme.icons.emblem)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function() ns.MainFrame:Toggle() end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = Minimap:GetCenter()
            settings.angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
            place(self, settings.angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    place(button, settings.angle)
    button:SetShown(not settings.hidden)
    self.button = button
end

function MinimapButton:SetHidden(hidden)
    ns.Database:Settings().minimap.hidden = hidden
    if self.button then self.button:SetShown(not hidden) end
end

-- Addon compartment (declared in the TOC).
function AzerothComplete_OnAddonCompartmentClick()
    ns.MainFrame:Toggle()
end

function AzerothComplete_OnAddonCompartmentEnter(_, button)
    showTooltip(button)
end

function AzerothComplete_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
