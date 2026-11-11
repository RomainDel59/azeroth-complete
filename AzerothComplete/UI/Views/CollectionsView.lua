-- Collections tab, on the page of every tab: the kinds of collection on the left (mounts,
-- pets, toys, appearance sets, titles), the selected kind and entry in the middle, the
-- entries of the kind on the right.

local _, ns = ...

local View = {}
ns.Views.Collections = View

local L = ns.L
local UI, Theme, Layout = ns.UI, ns.Theme, ns.Layout
local C = Theme.colors

local KINDS = ns.Collections.KINDS

-- Client label and addon fallback of each collection kind.
local KIND_LABELS = {
    mounts = { "MOUNTS", "COLLECTION_MOUNTS" },
    pets = { "PETS", "COLLECTION_PETS" },
    toys = { "TOY_BOX", "COLLECTION_TOYS" },
    sets = { "WARDROBE_SETS", "COLLECTION_SETS" },
    titles = { "PAPERDOLL_SIDEBAR_TITLES", "COLLECTION_TITLES" },
}

local function kindLabel(kind)
    local label = KIND_LABELS[kind]
    return ns:GameLabel(label[1], label[2])
end

local function buildKindCard(row)
    UI.ArtCard(row)
end

local function buildEntryRow(row)
    UI.DecorateRow(row)
    row.icon = UI.FramedIcon(row, 26)
    row.icon:SetPoint("LEFT", 6, 0)
    row.name = UI.Text(row, 13)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.check = UI.Glyph(row, "check", 16, C.green)
    row.check:SetPoint("RIGHT", -8, 0)
    row.right = UI.Text(row, 11, C.orange, "body", "RIGHT")
    row.right:SetPoint("RIGHT", row.check, "LEFT", -6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
end

function View:Build(frame)
    self.query, self.kindQuery = "", ""
    self.kind = KINDS[1]
    local page = Layout.Page(frame, {
        groupsTitle = L.COLLECTIONS_TITLE,
        groupSearch = L.SEARCH,
        onGroupSearch = function(text)
            self.kindQuery = text
            self:Refresh()
        end,
        buildGroup = buildKindCard,
        fillGroup = function(row, kind) self:FillKind(row, kind) end,
        detailsTitle = L.SELECTED_ENTRY,
        itemSearch = L.SEARCH,
        onItemSearch = function(text)
            self.query = text
            self:RefreshEntries()
        end,
        filterKey = "collections",
        onFilter = function() self:RefreshEntries() end,
        buildItem = buildEntryRow,
        fillItem = function(row, entry) self:FillEntry(row, entry) end,
        itemSpacing = 3,
    })
    self.page = page
    self.kinds, self.entries, self.filters = page.groups, page.items, page.filters
    self.title, self.banner, self.details = page.title, page.banner, page.details
    self.entriesTitle, self.count = page.itemsTitle, page.footer
end

function View:FillKind(row, kind)
    local summary = ns.Collections:Summary(kind)
    row.name:SetText(kindLabel(kind))
    row.levels:SetText(summary.available and "" or L.UNAVAILABLE)
    local complete = summary.total > 0 and summary.done >= summary.total
    row.count:SetText(summary.available and string.format("%d / %d", summary.done, summary.total) or "")
    row.count:SetTextColor(Theme.Unpack(complete and C.green or C.text))
    if not row.art:SetArtwork(ns.Data.Artwork.collections[kind]) then row.art:Clear() end
    row.border:SetColor(self.kind == kind and C.gold or (complete and C.greenBorder or C.borderDim))
    row:SetScript("OnClick", function()
        self.kind = kind
        self.selectedEntry = nil
        self.entries.offset = 0
        self:Refresh()
    end)
end

function View:FillEntry(row, entry)
    row.icon:SetIcon(entry.icon or Theme.icons[self.kind])
    row.name:SetText(entry.name)
    row.name:SetTextColor(Theme.Unpack(entry.collected and C.green or C.text))
    row.check:SetShown(entry.collected)
    if entry.collected then
        row.right:SetText("")
    elseif entry.pieces and entry.pieces > 0 then
        row.right:SetText(string.format("%d / %d", entry.owned, entry.pieces))
    else
        row.right:SetText(L.TO_OBTAIN:upper())
    end
    row:SetState(self.selectedEntry == entry.id)
    row:SetScript("OnClick", function()
        self.selectedEntry = entry.id
        self.entries:Redraw()
        self:ShowEntry(entry)
    end)
end

function View:ShowEntry(entry)
    local panel = self.details
    panel:Clear(entry and (self.kind .. ":" .. tostring(entry.id)) or nil)
    if not entry then
        panel:Line(L.SELECT_ENTRY, C.textDim)
        panel:Finish()
        return
    end
    panel:Title(entry.icon or Theme.icons[self.kind], entry.name, entry.collected and L.COLLECTED or L.NOT_COLLECTED,
        C.gold, entry.collected and C.green or C.orange)
    if entry.faction then
        panel:Line(entry.faction == "Horde" and L.FACTION_HORDE or L.FACTION_ALLIANCE, C.textDim, 11)
    end
    if entry.pieces and entry.pieces > 0 then
        panel:Line(string.format(L.SET_PIECES, entry.owned, entry.pieces), C.text, 12)
    end
    if entry.description and entry.description ~= "" then
        panel:Space(4)
        panel:Line(entry.description, C.text, 12)
    end
    panel:Heading(L.HOW_TO_OBTAIN)
    panel:Line(entry.source and entry.source ~= "" and entry.source or L.SOURCE_UNKNOWN, entry.source and C.text or C.textDim, 12)
    if entry.item then
        panel:Space(6)
        panel:IconLine(entry.icon, entry.name, nil, C.gold, nil, function(tooltip) tooltip:SetHyperlink("item:" .. entry.item) end)
    end
    panel:Finish()
end

function View:RefreshEntries()
    local entries = ns.Collections:Entries(self.kind)
    local items = {}
    for _, entry in ipairs(entries or {}) do
        if self.filters:Keeps(entry.collected) and UI.Matches(entry.name, self.query) then items[#items + 1] = entry end
    end
    self.entries:SetItems(items, true)
    self.count:SetText(entries and string.format(L.ENTRIES_LISTED, #items) or "")
    return entries
end

function View:Refresh()
    local done, total = 0, 0
    local kinds = {}
    for _, kind in ipairs(KINDS) do
        local summary = ns.Collections:Summary(kind)
        done, total = done + summary.done, total + summary.total
        if UI.Matches(kindLabel(kind), self.kindQuery) then kinds[#kinds + 1] = kind end
    end
    self.page.groupsCount:SetText(string.format("%d / %d", done, total))
    self.kinds:SetItems(kinds, true)

    local name = kindLabel(self.kind)
    local summary = ns.Collections:Summary(self.kind)
    self.title:SetText(name)
    local banner = self.banner
    banner.name:SetText(name:upper())
    banner.subtitle:SetText(string.format("%s  ·  %s", L.COLLECTIONS_TITLE, L.TRACKING_ACCOUNT))
    banner.caption:SetText(summary.available and string.format(L.COLLECTED_COUNT, summary.done, summary.total)
        or L.COLLECTION_UNAVAILABLE)
    banner.ring:SetProgress(summary.done, summary.total, summary.total > 0 and summary.done >= summary.total and L.COMPLETE or L.DONE)
    if not banner.art:SetArtwork(ns.Data.Artwork.collections[self.kind]) then banner.art:Clear() end
    self.entriesTitle:SetText(name:upper())

    local entries = self:RefreshEntries()
    local selected
    for _, entry in ipairs(entries or {}) do
        if entry.id == self.selectedEntry then selected = entry end
    end
    self:ShowEntry(selected)
    self.mainFrame:SetFooter(L.FOOTER_COLLECTIONS)
end
