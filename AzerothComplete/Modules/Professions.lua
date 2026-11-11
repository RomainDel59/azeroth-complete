-- Profession progress: ranks and learned recipes.
--
-- Learned recipes are read in two ways, whichever the client supports: by asking whether
-- each catalogue recipe is a known spell, and by reading the profession window when it
-- opens. Both feed the character's record, so the account view can merge every character.

local _, ns = ...

local Professions = ns:RegisterModule("Professions")

local R = ns.Const.Recipe
local Tracking = ns.Const.Tracking

local KIND_ORDER = { primary = 1, secondary = 2, gathering = 3 }

-- Professions sorted for display: crafting first, then secondary skills, then gathering.
function Professions:List()
    if self.list then return self.list end
    local list = {}
    for skillLine, profession in pairs(ns.Data.Professions) do
        list[#list + 1] = { skillLine = skillLine, kind = profession.kind, icon = profession.icon,
            recipes = profession.recipes }
    end
    table.sort(list, function(a, b)
        if KIND_ORDER[a.kind] ~= KIND_ORDER[b.kind] then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
        return (ns.Names.SkillLine(a.skillLine) or "") < (ns.Names.SkillLine(b.skillLine) or "")
    end)
    self.list = list
    return list
end

function Professions:Get(skillLine)
    return ns.Data.Professions[skillLine]
end

-------------------------------------------------------------------------------
-- Reading the character
-------------------------------------------------------------------------------

local recipeOwner -- [spellID] = skillLine

local function ownerOf(spellID)
    if not recipeOwner then
        recipeOwner = {}
        for skillLine, profession in pairs(ns.Data.Professions) do
            for _, recipe in ipairs(profession.recipes) do recipeOwner[recipe[R.SPELL]] = skillLine end
        end
    end
    return recipeOwner[spellID]
end

function Professions:ReadRanks()
    local record = ns.Database:Character()
    local ranks = ns.Compat.GetProfessionRanks()
    -- Without any skill read, the client API does not match: nothing is filtered on it.
    self.ranksRead = next(ranks) ~= nil
    if not self.ranksRead and not self.unreadLogged then
        self.unreadLogged = true
        ns.Log:Warn("No skill could be read from the client: professions are not used to filter")
    end
    local result = {}
    for skillLine in pairs(ns.Data.Professions) do
        local name = ns.Names.SkillLine(skillLine)
        local entry = name and ranks[name]
        if not entry then
            for _, candidate in pairs(ranks) do
                if candidate.skillLine == skillLine then entry = candidate break end
            end
        end
        if entry then result[skillLine] = { rank = entry.rank, maxRank = entry.maxRank } end
    end
    -- A profession that was read before and is now absent has been unlearned: its recipes
    -- go with it. Nothing is forgotten when no rank at all could be read (API mismatch).
    if next(result) then
        for skillLine in pairs(record.professions or {}) do
            if not result[skillLine] then self:Forget(skillLine) end
        end
    end
    record.professions = result
    return result
end

function Professions:Forget(skillLine)
    local record = ns.Database:Character()
    local profession = ns.Data.Professions[skillLine]
    local removed = 0
    for _, recipe in ipairs(profession and profession.recipes or {}) do
        if record.recipes[recipe[R.SPELL]] then
            record.recipes[recipe[R.SPELL]] = nil
            removed = removed + 1
        end
    end
    ns.Log:Info("Profession %d unlearned: %d recipes forgotten", skillLine, removed)
end

-- Asks the client about every catalogue recipe. Every profession is scanned, not only the
-- ones whose rank was read: rank detection matches localized names and may miss one.
function Professions:ScanKnownSpells()
    local record = ns.Database:Character()
    local found = 0
    for _, profession in pairs(ns.Data.Professions) do
        for _, recipe in ipairs(profession.recipes) do
            local spellID = recipe[R.SPELL]
            if ns.Compat.IsSpellKnown(spellID) then
                if not record.recipes[spellID] then found = found + 1 end
                record.recipes[spellID] = true
            end
        end
    end
    return found
end

-- Reads the open profession window, with the API generation the client has.
function Professions:ScanTradeSkillWindow()
    local record = ns.Database:Character()
    local found, method = 0, nil
    local function learn(spellID)
        if spellID and ownerOf(spellID) and not record.recipes[spellID] then
            record.recipes[spellID] = true
            found = found + 1
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        method = "C_TradeSkillUI"
        for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
            if info and info.learned then learn(recipeID) end
        end
    elseif GetNumTradeSkills and GetTradeSkillInfo then
        method = "GetTradeSkillInfo"
        for i = 1, GetNumTradeSkills() do
            local _, kind = GetTradeSkillInfo(i)
            if kind ~= "header" then
                local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
                learn(link and tonumber(link:match("enchant:(%d+)")))
            end
        end
    end
    if GetNumCrafts and GetCraftInfo then
        method = (method and method .. "+" or "") .. "GetCraftInfo"
        for i = 1, GetNumCrafts() do
            local link = GetCraftRecipeLink and GetCraftRecipeLink(i)
            learn(link and tonumber(link:match("enchant:(%d+)")))
        end
    end
    return found, method
end

function Professions:Refresh(reason)
    local ranks = self:ReadRanks()
    local fromSpells = self:ScanKnownSpells()
    local read = {}
    for skillLine, rank in pairs(ranks) do
        read[#read + 1] = string.format("%d=%s/%s", skillLine, tostring(rank.rank), tostring(rank.maxRank))
    end
    ns.Log:Debug("Professions refreshed (%s): ranks [%s], %d new recipes from known spells", reason,
        table.concat(read, " "), fromSpells)
    ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 0.3)
end

function Professions:OnLogin()
    self:Refresh("login")
end

-- The profession window fires its update events on every search keystroke and craft: the
-- window is read once things have been quiet for a second.
local tradeSkillPending = false
local function onTradeSkill(event)
    if tradeSkillPending then return end
    tradeSkillPending = true
    C_Timer.After(1, function()
        tradeSkillPending = false
        ns:SafeCall("Professions.window", function()
            local found, method = Professions:ScanTradeSkillWindow()
            ns.Log:Debug("Profession window read (%s via %s): %d new recipes", event, tostring(method), found)
            Professions:Refresh(event)
        end)
    end)
end

ns:RegisterEvent("TRADE_SKILL_SHOW", onTradeSkill)
ns:RegisterEvent("TRADE_SKILL_LIST_UPDATE", onTradeSkill)
ns:RegisterEvent("TRADE_SKILL_UPDATE", onTradeSkill)
ns:RegisterEvent("CRAFT_SHOW", onTradeSkill)
ns:RegisterEvent("NEW_RECIPE_LEARNED", function() Professions:Refresh("new recipe") end)
ns:RegisterEvent("SKILL_LINES_CHANGED", function() Professions:Refresh("skill lines") end)
ns:RegisterEvent("LEARNED_SPELL_IN_TAB", function() Professions:Refresh("learned spell") end)

-------------------------------------------------------------------------------
-- Views
-------------------------------------------------------------------------------

-- Learned recipe set of a tracking mode.
local mergedKnown -- account-wide set, rebuilt after each progress change

function Professions:Known(tracking)
    if tracking ~= Tracking.ACCOUNT then return ns.Database:Character().recipes end
    if not mergedKnown then
        mergedKnown = {}
        for _, record in ns.Database:Characters() do
            for spellID in pairs(record.recipes or {}) do mergedKnown[spellID] = true end
        end
    end
    return mergedKnown
end

ns:RegisterMessage("AC_PROGRESS_CHANGED", function() mergedKnown = nil end)

-- Whether the character has learned a profession; true when the skills cannot be read.
function Professions:HasLearned(skillLine)
    if not self.ranksRead then return true end
    return ns.Database:Character().professions[skillLine] ~= nil
end

-- Professions shown in a view: in the character filter, only the learned ones.
function Professions:Shown(view)
    local list = self:List()
    if not ns.Quests:UsesCharacterFilter(view) then return list end
    local shown = {}
    for _, profession in ipairs(list) do
        if self:HasLearned(profession.skillLine) then shown[#shown + 1] = profession end
    end
    return shown
end

-- Best rank of a profession in a tracking mode: { rank, maxRank } or nil.
function Professions:Rank(skillLine, tracking)
    if tracking ~= Tracking.ACCOUNT then return ns.Database:Character().professions[skillLine] end
    local best
    for _, record in ns.Database:Characters() do
        local entry = record.professions and record.professions[skillLine]
        if entry and (not best or entry.rank > best.rank) then best = entry end
    end
    return best
end

function Professions:Summary(skillLine, known)
    local profession = ns.Data.Professions[skillLine]
    local done = 0
    for _, recipe in ipairs(profession.recipes) do
        if known[recipe[R.SPELL]] then done = done + 1 end
    end
    return { done = done, total = #profession.recipes }
end

-- Difficulty color key of a recipe at a rank: "orange", "yellow", "green", "gray".
function Professions.Difficulty(recipe, rank)
    if not rank then return nil end
    local low, high = recipe[R.TRIVIAL_LOW], recipe[R.TRIVIAL_HIGH]
    if rank >= high and high > 0 then return "gray" end
    if rank >= math.floor((low + high) / 2) and low > 0 then return "green" end
    if rank >= low and low > 0 then return "yellow" end
    return "orange"
end
