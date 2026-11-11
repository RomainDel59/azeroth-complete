-- Three-column layout shared by the views: navigation on the left, the main content in the
-- middle, details on the right.

local _, ns = ...

local Layout = {}
ns.Layout = Layout

local UI = ns.UI

Layout.LEFT_WIDTH = 300
Layout.RIGHT_WIDTH = 390
Layout.GAP = 12

-- Creates the three panels in `parent` and returns them; `rightWidth` and `leftWidth`
-- may override the defaults.
function Layout.Columns(parent, leftWidth, rightWidth)
    leftWidth = leftWidth or Layout.LEFT_WIDTH
    rightWidth = rightWidth or Layout.RIGHT_WIDTH
    local left = UI.Panel(parent)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(leftWidth)

    local right = UI.Panel(parent)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(rightWidth)

    local center = UI.Panel(parent)
    center:SetPoint("TOPLEFT", left, "TOPRIGHT", Layout.GAP, 0)
    center:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -Layout.GAP, 0)
    return left, center, right
end

-- Panel heading anchored at the top; left-aligned when `align` is "LEFT".
function Layout.Title(panel, text, size, align)
    local title = UI.Heading(panel, size or 20, text)
    if align == "LEFT" then
        title:SetJustifyH("LEFT")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", -16, -14)
    else
        title:SetPoint("TOPLEFT", 12, -14)
        title:SetPoint("TOPRIGHT", -12, -14)
    end
    return title
end

-- Summary banner: artwork, name, subtitle, progress ring and a caption under the name.
function Layout.Banner(parent, height)
    local banner = CreateFrame("Frame", nil, parent)
    banner:SetHeight(height)
    banner.art = UI.Art(banner)
    banner.art:SetAllPoints()
    banner.art.shadeFraction = 0.7
    local overlay = banner.art.overlay
    UI.Border(overlay, ns.Theme.colors.border)
    banner.name = UI.ArtText(overlay, 20, ns.Theme.colors.gold, "body")
    banner.name:SetPoint("TOPLEFT", 16, -16)
    banner.name:SetPoint("TOPRIGHT", -150, -16)
    banner.subtitle = UI.ArtText(overlay, 13, ns.Theme.colors.text)
    banner.subtitle:SetPoint("TOPLEFT", banner.name, "BOTTOMLEFT", 0, -6)
    banner.subtitle:SetPoint("TOPRIGHT", banner.name, "BOTTOMRIGHT", 0, -6)
    banner.caption = UI.ArtText(overlay, 15, ns.Theme.colors.text)
    banner.caption:SetPoint("BOTTOMLEFT", 16, 14)
    banner.caption:SetPoint("BOTTOMRIGHT", -150, 14)
    banner.ring = UI.ProgressRing(overlay, math.min(130, height - 20))
    banner.ring:SetPoint("RIGHT", -16, 0)
    return banner
end
