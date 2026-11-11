-- Dungeons and Raids tabs: instances on the left, the instance summary with its bosses and
-- quests in the middle, the selected boss or quest on the right.

local _, ns = ...

local L = ns.L
local UI, Theme, Layout, QuestWidgets = ns.UI, ns.Theme, ns.Layout, ns.QuestWidgets
local C = Theme.colors
local Kind = ns.Const.Instance


local function buildInstanceCard(row)
    UI.ArtCard(row)
end

local function buildEntryRow(row)
    QuestWidgets.BuildRow(row)
    row.icon = UI.FramedIcon(row, 22)
    row.icon:SetPoint("LEFT", 8, 0)
    row.header = UI.Text(row, 13, C.gold)
    row.header:SetPoint("LEFT", 10, 0)
end

local function newView(kind)
    local View = {}

    function View:Build(frame)
        self.expanded = {}
        local left, center, right = Layout.Columns(frame)

        Layout.Title(left, kind == Kind.RAID and L.RAIDS or L.DUNGEONS, 20, "LEFT")
        local search = UI.SearchBox(left, L.SEARCH_INSTANCE, function(text)
            self.query = text
            self:Refresh()
        end)
        search:SetPoint("TOPLEFT", 16, -48)
        search:SetPoint("TOPRIGHT", -16, -48)
        self.instances = UI.ScrollList(left, UI.ART_CARD_HEIGHT, buildInstanceCard, function(row, instance)
            self:FillCard(row, instance)
        end, 6)
        self.instances:SetPoint("TOPLEFT", 16, -86)
        self.instances:SetPoint("BOTTOMRIGHT", -8, 12)

        self.title = UI.Text(center, 26, C.gold, "fancy", "CENTER")
        self.title:SetPoint("TOPLEFT", 12, -14)
        self.title:SetPoint("TOPRIGHT", -12, -14)
        self.banner = Layout.Banner(center, 150)
        self.banner:SetPoint("TOPLEFT", 16, -52)
        self.banner:SetPoint("TOPRIGHT", -16, -52)
        self.entries = UI.ScrollList(center, 32, buildEntryRow, function(row, item) self:FillEntry(row, item) end, 3)
        self.entries:SetPoint("TOPLEFT", self.banner, "BOTTOMLEFT", 0, -12)
        self.entries:SetPoint("BOTTOMRIGHT", -8, 14)

        Layout.Title(right, L.DETAILS, 20)
        self.details = UI.DetailPanel(right)
        self.details:SetPoint("TOPLEFT", 16, -50)
        self.details:SetPoint("BOTTOMRIGHT", -8, 12)
    end

    function View:FillCard(row, instance)
        local summary = ns.Instances:Summary(instance, self.mainFrame:View())
        row.name:SetText(ns.Instances:Name(instance))
        row.count:SetText(string.format("%d / %d", summary.done, summary.total))
        local complete = summary.total > 0 and summary.done >= summary.total
        row.count:SetTextColor(Theme.Unpack(complete and C.green or C.text))
        row.levels:SetText(instance.levels and QuestWidgets.LevelText(instance.levels[1], instance.levels[2]) or "")
        if not row.art:SetLoadingScreen(instance.art, instance.artFramed) then row.art:Clear() end
        row.border:SetColor(self.selected == instance and C.gold or (complete and C.greenBorder or C.borderDim))
        row:SetScript("OnClick", function()
            self.selected = instance
            self.selectedEntry = nil
            self.entries.offset = 0
            self:Refresh()
        end)
    end

    -- Entries of the middle list: a bosses header and bosses, then a quests header and quests.
    function View:BuildEntries(instance, view)
        local items = {}
        if #instance.bosses > 0 then
            items[#items + 1] = { kind = "header", text = L.BOSSES }
            for _, encounterID in ipairs(instance.bosses) do items[#items + 1] = { kind = "boss", id = encounterID } end
        end
        local questItems = QuestWidgets.BuildItems(instance.chains, view, self.expanded)
        if #questItems > 0 then
            items[#items + 1] = { kind = "header", text = L.QUESTS }
            for _, item in ipairs(questItems) do items[#items + 1] = item end
        end
        return items
    end

    function View:FillEntry(row, item)
        local isHeader, isBoss = item.kind == "header", item.kind == "boss"
        row.header:SetShown(isHeader)
        row.icon:SetShown(isBoss)
        for _, region in ipairs({ row.name, row.level, row.right }) do region:SetShown(not isHeader) end
        row.check:Hide()
        row.marker:Hide()
        row.expand:Hide()
        row:SetScript("OnClick", nil)
        if isHeader then
            row.header:SetText(item.text:upper())
            row:SetState(false, { bg = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 } })
            return
        end
        if isBoss then
            local defeated = ns.Instances:Defeated(self.mainFrame:View().tracking)[item.id]
            row.icon:SetIcon(Theme.icons.boss)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
            row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
            row.name:SetText(ns.Names.Encounter(item.id) or ("#" .. item.id))
            row.name:SetTextColor(Theme.Unpack(defeated and C.green or C.text))
            row.level:SetText("")
            row.right:SetText(defeated and L.DEFEATED or "")
            row.right:SetTextColor(Theme.Unpack(C.green))
            row.check:SetShown(defeated)
            row:SetState(self.selectedEntry == item.id and self.selectedKind == "boss")
            row:SetScript("OnClick", function() self:SelectEntry(item) end)
            return
        end
        QuestWidgets.FillRow(row, item, self.mainFrame:View(), self.selectedKind == "quest" and self.selectedEntry or nil)
        row:SetScript("OnClick", function() self:SelectEntry(item) end)
    end

    function View:SelectEntry(item)
        if item.kind == "chain" then self.expanded[item.id] = not self.expanded[item.id] end
        self.selectedEntry = item.id
        self.selectedKind = item.kind == "boss" and "boss" or "quest"
        self:Refresh()
    end

    function View:ShowBoss(encounterID)
        local panel = self.details
        panel:Clear("boss:" .. encounterID)
        local defeated = ns.Instances:Defeated(self.mainFrame:View().tracking)[encounterID]
        panel:Title(Theme.icons.boss, ns.Names.Encounter(encounterID) or ("#" .. encounterID),
            defeated and L.DEFEATED or L.NOT_DEFEATED, C.gold, defeated and C.green or C.orange)
        panel:Line(ns.Instances:Name(self.selected), C.text, 12)
        panel:Space(6)
        panel:Line(L.BOSS_TRACKING_NOTE, C.textDim, 11)
        panel:Finish()
    end

    function View:Refresh()
        local view = self.mainFrame:View()
        local list = {}
        for _, instance in ipairs(ns.Instances:List(kind)) do
            if UI.Matches(ns.Instances:Name(instance), self.query) then list[#list + 1] = instance end
        end
        if not self.selected then self.selected = list[1] end
        self.instances:SetItems(list, true)

        local instance = self.selected
        if not instance then
            self.title:SetText("")
            self.entries:SetItems({})
            self.details:Clear()
            self.details:Line(L.NO_INSTANCE, C.textDim)
            self.details:Finish()
            return
        end
        local name = ns.Instances:Name(instance)
        local summary = ns.Instances:Summary(instance, view)
        self.title:SetText(name)
        local banner = self.banner
        banner.name:SetText(name:upper())
        local parts = { kind == Kind.RAID and L.RAID or L.DUNGEON }
        if instance.levels then parts[#parts + 1] = QuestWidgets.LevelText(instance.levels[1], instance.levels[2]) end
        if instance.players and instance.players > 0 then parts[#parts + 1] = string.format(L.PLAYERS, instance.players) end
        banner.subtitle:SetText(table.concat(parts, "  ·  "))
        banner.caption:SetText(string.format(L.INSTANCE_CAPTION, summary.bossesDone, summary.bosses, summary.questsDone, summary.quests))
        banner.ring:SetProgress(summary.done, summary.total, summary.total > 0 and summary.done >= summary.total and L.COMPLETE or L.DONE)
        if not banner.art:SetLoadingScreen(instance.art, instance.artFramed) then banner.art:Clear() end

        self.entries:SetItems(self:BuildEntries(instance, view), true)
        if self.selectedKind == "boss" and self.selectedEntry then
            self:ShowBoss(self.selectedEntry)
        elseif self.selectedKind == "quest" and self.selectedEntry then
            QuestWidgets.ShowDetails(self.details, self.selectedEntry, view)
        else
            self.details:Clear()
            self.details:Line(L.SELECT_ENTRY, C.textDim)
            self.details:Finish()
        end
        self.mainFrame:SetFooter(L.FOOTER_INSTANCES)
    end

    return View
end

ns.Views.Dungeons = newView(Kind.DUNGEON)
ns.Views.Raids = newView(Kind.RAID)
