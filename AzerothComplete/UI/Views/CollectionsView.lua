-- Collections and Toys tabs: collection kinds on the left, their entries in the middle,
-- the selected entry on the right. The Toys tab is the same view limited to toys.

local _, ns = ...

local L = ns.L
local UI, Theme, Layout = ns.UI, ns.Theme, ns.Layout
local C = Theme.colors

local FILTERS = { "all", "missing", "collected" }

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

local function buildKindRow(row)
    UI.DecorateRow(row)
    row.icon = UI.FramedIcon(row, 30)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = UI.Text(row, 14)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.count = UI.Text(row, 13, C.gold, "body", "RIGHT")
    row.count:SetPoint("RIGHT", -10, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.bar = UI.ProgressBar(row, 3)
    row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, -2)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 7)
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

local function newView(kinds, titleKey)
    local View = {}

    function View:Build(frame)
        self.filter = "all"
        self.query = ""
        self.kind = kinds[1]
        local left, center, right = Layout.Columns(frame)

        Layout.Title(left, L[titleKey], 20, "LEFT")
        self.ring = UI.ProgressRing(left, 120)
        self.ring:SetPoint("TOP", 0, -48)
        self.kinds = UI.ScrollList(left, 48, buildKindRow, function(row, kind) self:FillKind(row, kind) end, 6)
        self.kinds:SetPoint("TOPLEFT", 16, -184)
        self.kinds:SetPoint("BOTTOMRIGHT", -8, 12)

        self.title = UI.Text(center, 26, C.gold, "fancy", "CENTER")
        self.title:SetPoint("TOPLEFT", 12, -14)
        self.title:SetPoint("TOPRIGHT", -12, -14)
        self.subtitle = UI.Text(center, 14, C.green, "body", "CENTER")
        self.subtitle:SetPoint("TOP", self.title, "BOTTOM", 0, -6)
        local options = {}
        for _, filter in ipairs(FILTERS) do options[#options + 1] = { value = filter, label = L["FILTER_" .. filter:upper()] } end
        self.filters = UI.ButtonGroup(center, 92, 22, options, function(value)
            self.filter = value
            self:RefreshEntries()
        end)
        self.filters:SetPoint("TOPLEFT", 18, -84)
        self.filters:Select("all")
        local search = UI.SearchBox(center, L.SEARCH, function(text)
            self.query = text
            self:RefreshEntries()
        end)
        search:SetPoint("LEFT", self.filters, "RIGHT", 10, 0)
        search:SetPoint("TOPRIGHT", center, "TOPRIGHT", -18, -84)
        search:SetHeight(22)
        self.entries = UI.ScrollList(center, 34, buildEntryRow, function(row, entry) self:FillEntry(row, entry) end, 3)
        self.entries:SetPoint("TOPLEFT", 18, -116)
        self.entries:SetPoint("BOTTOMRIGHT", -8, 34)
        self.count = UI.Text(center, 12, C.text, "body", "CENTER")
        self.count:SetPoint("BOTTOM", 0, 12)

        Layout.Title(right, L.DETAILS, 20)
        self.details = UI.DetailPanel(right)
        self.details:SetPoint("TOPLEFT", 16, -50)
        self.details:SetPoint("BOTTOMRIGHT", -8, 12)
    end

    function View:FillKind(row, kind)
        local summary = ns.Collections:Summary(kind)
        row.icon:SetIcon(Theme.icons[kind])
        row.name:SetText(kindLabel(kind))
        row.count:SetText(summary.available and string.format("%d / %d", summary.done, summary.total) or L.UNAVAILABLE)
        row.bar:SetProgress(summary.done, summary.total)
        row:SetState(self.kind == kind)
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
        local items, owned = {}, 0
        for _, entry in ipairs(entries or {}) do
            if entry.collected then owned = owned + 1 end
            local keep = self.filter == "all" or (self.filter == "collected" and entry.collected)
                or (self.filter == "missing" and not entry.collected)
            if keep and UI.Matches(entry.name, self.query) then items[#items + 1] = entry end
        end
        self.entries:SetItems(items, true)
        if entries then
            self.count:SetText(string.format(L.ENTRIES_LISTED, #items))
            self.subtitle:SetText(string.format(L.COLLECTED_COUNT, owned, #entries))
        else
            self.count:SetText("")
            self.subtitle:SetText(L.COLLECTION_UNAVAILABLE)
        end
        return entries
    end

    function View:Refresh()
        local done, total = 0, 0
        for _, kind in ipairs(kinds) do
            local summary = ns.Collections:Summary(kind)
            done, total = done + summary.done, total + summary.total
        end
        self.ring:SetProgress(done, total, L.COLLECTED_SHORT)
        self.kinds:SetItems(kinds, true)
        self.title:SetText(kindLabel(self.kind))
        local entries = self:RefreshEntries()
        local selected
        for _, entry in ipairs(entries or {}) do
            if entry.id == self.selectedEntry then selected = entry end
        end
        self:ShowEntry(selected)
        self.mainFrame:SetFooter(L.FOOTER_COLLECTIONS)
    end

    return View
end

ns.Views.Collections = newView({ "mounts", "pets", "sets", "titles" }, "COLLECTIONS_TITLE")
ns.Views.Toys = newView({ "toys" }, "TOYS_TITLE")
