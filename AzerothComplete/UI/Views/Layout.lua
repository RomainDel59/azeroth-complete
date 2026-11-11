-- Layout shared by the views: three columns, the summary banner and the page of a tab.

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

-- Summary banner, as high as its three lines of text: the name, a subtitle and a caption over
-- the artwork, the progress ring on the right.
Layout.BANNER_HEIGHT = 96

function Layout.Banner(parent, height)
    local banner = CreateFrame("Frame", nil, parent)
    banner:SetHeight(height)
    banner.art = UI.Art(banner)
    banner.art:SetAllPoints()
    -- Texts run from the top to the bottom of the banner: the whole artwork is darkened.
    banner.art:DarkenFully(0.85, 0.45)
    local overlay = banner.art.overlay
    UI.Border(overlay, ns.Theme.colors.border)
    banner.name = UI.Text(overlay, 20, ns.Theme.colors.gold, "body")
    banner.name:SetPoint("TOPLEFT", 16, -14)
    banner.name:SetPoint("TOPRIGHT", -(height + 8), -14)
    banner.subtitle = UI.Text(overlay, 13, ns.Theme.colors.text)
    banner.subtitle:SetPoint("TOPLEFT", banner.name, "BOTTOMLEFT", 0, -6)
    banner.subtitle:SetPoint("TOPRIGHT", banner.name, "BOTTOMRIGHT", 0, -6)
    banner.caption = UI.Text(overlay, 15, ns.Theme.colors.text)
    banner.caption:SetPoint("BOTTOMLEFT", 16, 14)
    banner.caption:SetPoint("BOTTOMRIGHT", -(height + 8), 14)
    banner.ring = UI.ProgressRing(overlay, height - 12)
    banner.ring:SetPoint("RIGHT", -12, 0)
    return banner
end

-- Page of every tab, laid out as the quests tab: the groups on the left (title, search,
-- optional controls, cards), the selected group in the middle (title, banner, then the
-- details of the selected item), the items of the group on the right (title, search, state
-- filter, list, count). Views fill it; they do not lay out their own widgets.
--
-- `spec`: groupsTitle, groupSearch, onGroupSearch(text), controlsHeight and
-- buildControls(left, top) for widgets between the search and the cards, as the state
-- filter stands under the search of the items, buildGroup(row) and
-- fillGroup(row, group) for the cards, detailsTitle, itemSearch, onItemSearch(text),
-- filterKey and onFilter() for the state filter, itemHeight, buildItem(row),
-- fillItem(row, item) and itemSpacing for the item rows.
function Layout.Page(frame, spec)
    local C = ns.Theme.colors
    local page = {}
    local left, center, right = Layout.Columns(frame)
    page.left, page.center, page.right = left, center, right

    -- Left: the groups
    page.groupsTitle = Layout.Title(left, spec.groupsTitle, 20, "LEFT")
    page.groupsCount = UI.Text(left, 13, C.gold, "body", "RIGHT")
    page.groupsCount:SetPoint("TOPRIGHT", -16, -20)
    page.groupSearch = UI.SearchBox(left, spec.groupSearch, spec.onGroupSearch)
    page.groupSearch:SetPoint("TOPLEFT", 16, -44)
    page.groupSearch:SetPoint("TOPRIGHT", -16, -44)
    local top = -80
    if spec.buildControls then
        spec.buildControls(left, top)
        top = top - spec.controlsHeight
    end
    page.groups = UI.ScrollList(left, UI.ART_CARD_HEIGHT, spec.buildGroup, spec.fillGroup, 6)
    page.groups:SetPoint("TOPLEFT", 16, top)
    page.groups:SetPoint("BOTTOMRIGHT", -8, 12)

    -- Middle: the selected group and the selected item
    page.title = UI.Text(center, 26, C.gold, "fancy", "CENTER")
    page.title:SetPoint("TOPLEFT", 12, -14)
    page.title:SetPoint("TOPRIGHT", -12, -14)
    page.banner = Layout.Banner(center, Layout.BANNER_HEIGHT)
    page.banner:SetPoint("TOPLEFT", 16, -52)
    page.banner:SetPoint("TOPRIGHT", -16, -52)
    local detailBox = UI.Panel(center, C.panelDark, C.borderDim)
    detailBox:SetPoint("TOPLEFT", page.banner, "BOTTOMLEFT", 0, -14)
    detailBox:SetPoint("BOTTOMRIGHT", -16, 14)
    page.detailsTitle = UI.Heading(detailBox, 16, spec.detailsTitle, "fancy")
    page.detailsTitle:SetPoint("TOP", 0, -10)
    page.details = UI.DetailPanel(detailBox)
    page.details:SetPoint("TOPLEFT", 14, -36)
    page.details:SetPoint("BOTTOMRIGHT", -8, 10)

    -- Right: the items of the group
    page.itemsTitle = Layout.Title(right, "", 18)
    page.itemSearch = UI.SearchBox(right, spec.itemSearch, spec.onItemSearch)
    page.itemSearch:SetPoint("TOPLEFT", 14, -44)
    page.itemSearch:SetPoint("TOPRIGHT", -14, -44)
    page.filters = UI.StateFilter(right, spec.filterKey, spec.onFilter)
    page.filters:SetPoint("TOPLEFT", 14, -74)
    page.items = UI.ScrollList(right, spec.itemHeight or 34, spec.buildItem, spec.fillItem, spec.itemSpacing or 4)
    page.items:SetPoint("TOPLEFT", 14, -104)
    page.items:SetPoint("BOTTOMRIGHT", -6, 36)
    page.footer = UI.Text(right, 12, C.text, "body", "CENTER")
    page.footer:SetPoint("BOTTOM", 0, 12)
    return page
end
