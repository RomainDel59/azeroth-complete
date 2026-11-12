-- Achievements, which WoW Forever presents as Legacy challenges. Everything is read from
-- the client: categories, achievements, criteria and completion.

local _, ns = ...

local Achievements = ns:RegisterModule("Achievements")

local Tracking = ns.Const.Tracking
local STATISTIC_FLAG = 0x1

function Achievements:Available()
    return GetCategoryList ~= nil and GetCategoryInfo ~= nil and GetAchievementInfo ~= nil
        and GetCategoryNumAchievements ~= nil
end

local function isStatistic(flags)
    return flags and flags % (STATISTIC_FLAG * 2) >= STATISTIC_FLAG
end

-- Categories with at least one achievement: { id, name, parent, achievements = { ids } }.
function Achievements:Categories()
    if self.categories then return self.categories end
    local categories = {}
    if not self:Available() then return categories end
    for _, categoryID in ipairs(GetCategoryList() or {}) do
        local name, parentID = GetCategoryInfo(categoryID)
        local ids = {}
        for i = 1, GetCategoryNumAchievements(categoryID, true) or 0 do
            local id, _, _, _, _, _, _, _, flags = GetAchievementInfo(categoryID, i)
            if id and not isStatistic(flags) then ids[#ids + 1] = id end
        end
        if #ids > 0 then
            categories[#categories + 1] = { id = categoryID, name = name or ("#" .. categoryID), parent = parentID, achievements = ids }
        end
    end
    ns.Log:Debug("Achievements: %d categories", #categories)
    self.categories = categories
    return categories
end

-- Achievement details: { id, name, points, completed, description, icon, reward, criteria, date }.
function Achievements:Get(achievementID, tracking)
    local id, name, points, completed, month, day, year, description, _, icon, reward, _, earnedByMe = GetAchievementInfo(achievementID)
    if not id then return nil end
    local done = completed
    if tracking == Tracking.CHARACTER and earnedByMe ~= nil then done = earnedByMe end
    local entry = { id = id, name = name, points = points, completed = done and true or false,
        description = description, icon = icon, reward = reward ~= "" and reward or nil }
    if completed and year then entry.date = string.format("%02d/%02d/%02d", day, month, year) end
    return entry
end

function Achievements:Criteria(achievementID)
    local criteria = {}
    if not (GetAchievementNumCriteria and GetAchievementCriteriaInfo) then return criteria end
    for i = 1, GetAchievementNumCriteria(achievementID) or 0 do
        local text, _, completed, quantity, required = GetAchievementCriteriaInfo(achievementID, i)
        criteria[#criteria + 1] = { text = text, completed = completed, quantity = quantity, required = required }
    end
    return criteria
end

local summaries = {} -- [tracking .. category id] = summary, cleared on progress changes

function Achievements:Summary(category, tracking)
    local key = tostring(tracking) .. ":" .. category.id
    if summaries[key] then return summaries[key] end
    local done = 0
    for _, id in ipairs(category.achievements) do
        local entry = self:Get(id, tracking)
        if entry and entry.completed then done = done + 1 end
    end
    summaries[key] = { done = done, total = #category.achievements }
    return summaries[key]
end

ns:RegisterMessage("AC_PROGRESS_CHANGED", function() summaries = {} end)

-- Categories out of the character's reach, in the character filter: those named after
-- another class, or after a profession the character has not learned. [categoryID] = true.
function Achievements:OutOfReach(categories, view)
    local hidden = {}
    if not ns.Quests:UsesCharacterFilter(view) then return hidden end
    local byName = {}
    for classID in pairs(ns.Data.Artwork.classes) do
        local name = ns.Compat.GetClassName(classID)
        if name then byName[name] = classID ~= ns.Player.classID end
    end
    for skillLine in pairs(ns.Data.Professions) do
        local name = ns.Names.SkillLine(skillLine)
        if name then byName[name] = not ns.Professions:HasLearned(skillLine) end
    end
    for _, category in ipairs(categories) do
        if byName[category.name] then hidden[category.id] = true end
    end
    return hidden
end

function Achievements:Invalidate()
    self.categories = nil
    ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 0.5)
end

ns:RegisterEvent("ACHIEVEMENT_EARNED", function(_, id)
    ns.Log:Info("Achievement %s earned", tostring(id))
    Achievements:Invalidate()
end)
ns:RegisterEvent("CRITERIA_UPDATE", function() ns:SendMessageDelayed("AC_PROGRESS_CHANGED", 2) end)
