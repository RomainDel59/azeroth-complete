-- Collections: mounts, companions, toys, appearance sets and titles.
--
-- The shipped identifier lists come from the client tables; every name, icon, source text
-- and collected state is read from the client. An entry the client does not describe
-- (hidden or unavailable on this character) is left out. Mounts, companions, toys and
-- appearances are account-wide in WoW Forever; titles belong to each character.

local _, ns = ...

local Collections = ns:RegisterModule("Collections")

-- Each kind returns its entries: { id, name, icon, collected, source, description }.
local readers = {}

readers.mounts = function()
    local journal = C_MountJournal
    if not (journal and journal.GetMountInfoByID) then return nil end
    local ids = journal.GetMountIDs and journal.GetMountIDs() or ns.Data.Collections.mounts
    local entries = {}
    for _, mountID in ipairs(ids) do
        local name, spellID, icon, _, _, _, _, isFactionSpecific, faction, shouldHide, isCollected = journal.GetMountInfoByID(mountID)
        if name and not (shouldHide and not isCollected) then
            local _, description, source = nil, nil, nil
            if journal.GetMountInfoExtraByID then _, description, source = journal.GetMountInfoExtraByID(mountID) end
            entries[#entries + 1] = { id = mountID, spell = spellID, name = name, icon = icon, collected = isCollected,
                source = source, description = description,
                faction = isFactionSpecific and (faction == 0 and "Horde" or "Alliance") or nil }
        end
    end
    return entries
end

local unnamedPetLogged = false

readers.pets = function()
    local journal = C_PetJournal
    if not (journal and journal.GetPetInfoBySpeciesID) then return nil end
    local entries = {}
    for _, speciesID in ipairs(ns.Data.Collections.pets) do
        local name, icon, _, _, source, description, _, _, _, _, obtainable = journal.GetPetInfoBySpeciesID(speciesID)
        if name ~= nil and type(name) ~= "string" then
            -- Some species of the client tables come back with another value as their name:
            -- they are left out, and the first one is described once in the log.
            if not unnamedPetLogged then
                unnamedPetLogged = true
                local returns = { journal.GetPetInfoBySpeciesID(speciesID) }
                local types = {}
                for i = 1, select("#", journal.GetPetInfoBySpeciesID(speciesID)) do types[i] = type(returns[i]) end
                ns.Log:Info("Pet species %d has no text name; the client returns: %s", speciesID, table.concat(types, ", "))
            end
            name = nil
        end
        if name and obtainable ~= false then
            local owned = journal.GetNumCollectedInfo and journal.GetNumCollectedInfo(speciesID) or 0
            entries[#entries + 1] = { id = speciesID, name = name, icon = icon, collected = (owned or 0) > 0,
                source = source, description = description }
        end
    end
    return entries
end

readers.toys = function()
    local hasToy = PlayerHasToy
    if not hasToy then return nil end
    local entries = {}
    for _, itemID in ipairs(ns.Data.Collections.toys) do
        local name, icon
        if C_ToyBox and C_ToyBox.GetToyInfo then
            local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
            name, icon = toyName, toyIcon
        end
        name = name or ns.Names.Item(itemID)
        icon = icon or ns.Compat.GetItemIcon(itemID)
        if name then
            entries[#entries + 1] = { id = itemID, item = itemID, name = name, icon = icon, collected = hasToy(itemID),
                source = ns:GameString("toySources", itemID) }
        end
    end
    return entries
end

readers.sets = function()
    local sets = C_TransmogSets
    if not (sets and sets.GetSetInfo) then return nil end
    local entries = {}
    for _, setID in ipairs(ns.Data.Collections.sets) do
        local info = sets.GetSetInfo(setID)
        if info and info.name then
            local collected = info.collected
            local pieces, owned = 0, 0
            if sets.GetSetPrimaryAppearances then
                for _, appearance in ipairs(sets.GetSetPrimaryAppearances(setID) or {}) do
                    pieces = pieces + 1
                    if appearance.collected then owned = owned + 1 end
                end
            end
            entries[#entries + 1] = { id = setID, name = info.name, icon = nil, collected = collected,
                description = info.description or info.label, pieces = pieces, owned = owned }
        end
    end
    return entries
end

readers.titles = function()
    if not (GetTitleName and IsTitleKnown) then return nil end
    local entries = {}
    for _, titleID in ipairs(ns.Data.Collections.titles) do
        local name = GetTitleName(titleID)
        if name and name ~= "" then
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            entries[#entries + 1] = { id = titleID, name = name, collected = IsTitleKnown(titleID) and true or false }
        end
    end
    return entries
end

Collections.KINDS = { "mounts", "pets", "toys", "sets", "titles" }

local cache = {}

-- Entries of a kind, sorted collected-last then by name; nil when the client lacks the API.
function Collections:Entries(kind)
    if cache[kind] then return cache[kind] end
    local entries = ns:SafeCall("Collections." .. kind, readers[kind])
    if entries then
        -- A client API that returns its values in another order than expected puts something
        -- else than a text in the name: such entries are left out and reported.
        local valid, rejected = {}, nil
        for _, entry in ipairs(entries) do
            if type(entry.name) == "string" then
                valid[#valid + 1] = entry
            else
                rejected = rejected or { count = 0, id = entry.id, type = type(entry.name) }
                rejected.count = rejected.count + 1
            end
        end
        if rejected then
            ns.Log:Warn("Collection %s: %d entries without a text name (first: id %s, name is a %s)",
                kind, rejected.count, tostring(rejected.id), rejected.type)
        end
        entries = valid
        table.sort(entries, function(a, b)
            if a.collected ~= b.collected then return not a.collected end
            return a.name < b.name
        end)
        local owned = 0
        for _, entry in ipairs(entries) do if entry.collected then owned = owned + 1 end end
        ns.Log:Debug("Collection %s: %d/%d", kind, owned, #entries)
    else
        ns.Log:Info("Collection %s is not available on this client", kind)
    end
    cache[kind] = entries or false
    return cache[kind] or nil
end

function Collections:Summary(kind)
    local entries = self:Entries(kind)
    if not entries then return { done = 0, total = 0, available = false } end
    local done = 0
    for _, entry in ipairs(entries) do if entry.collected then done = done + 1 end end
    return { done = done, total = #entries, available = true }
end

function Collections:Invalidate(kind)
    if kind then cache[kind] = nil else cache = {} end
    ns:SendMessageDelayed("AC_COLLECTIONS_CHANGED", 0.5)
end

ns:RegisterEvent("NEW_MOUNT_ADDED", function() Collections:Invalidate("mounts") end)
ns:RegisterEvent("COMPANION_LEARNED", function() Collections:Invalidate() end)
ns:RegisterEvent("NEW_PET_ADDED", function() Collections:Invalidate("pets") end)
ns:RegisterEvent("PET_JOURNAL_LIST_UPDATE", function() Collections:Invalidate("pets") end)
ns:RegisterEvent("TOYS_UPDATED", function() Collections:Invalidate("toys") end)
ns:RegisterEvent("NEW_TOY_ADDED", function() Collections:Invalidate("toys") end)
ns:RegisterEvent("TRANSMOG_COLLECTION_UPDATED", function() Collections:Invalidate("sets") end)
ns:RegisterEvent("KNOWN_TITLES_UPDATE", function() Collections:Invalidate("titles") end)
-- Names arriving late (toys use item names) may complete entries that were skipped.
ns:RegisterMessage("AC_NAMES_UPDATED", function() cache.toys = nil end)
