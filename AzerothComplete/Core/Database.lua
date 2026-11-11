-- Saved variables.
--
-- AzerothCompleteDB (account) holds the settings, the log, the text caches and one record
-- per character, so that the account view can merge the progress of every character the
-- addon has seen. Each record is written by its own character only.

local _, ns = ...

local Database = {}
ns.Database = Database

local SCHEMA_VERSION = 1

local DEFAULT_SETTINGS = {
    tracking = ns.Const.Tracking.CHARACTER,
    possibleOnly = true, -- character view: only what the character can do
    scale = 1,
    minimap = { angle = 200, hidden = false },
    showCompleted = true,
}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                copyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            copyDefaults(target[key], value)
        end
    end
end

function Database:Initialize()
    AzerothCompleteDB = AzerothCompleteDB or {}
    local db = AzerothCompleteDB
    db.log = db.log or {}
    ns.Log:Attach(db.log)

    if (db.schema or SCHEMA_VERSION) > SCHEMA_VERSION then
        ns.Log:Warn("Saved data comes from a newer version (schema %s)", tostring(db.schema))
    end
    db.schema = SCHEMA_VERSION
    db.settings = db.settings or {}
    copyDefaults(db.settings, DEFAULT_SETTINGS)
    db.characters = db.characters or {}
    db.cache = db.cache or {}

    -- Text caches depend on the client language and build: a new build may rename things.
    local build = ns.Compat.GetClientBuild()
    if db.cacheBuild ~= build then
        if db.cacheBuild then ns.Log:Info("Client build changed (%s -> %s): text cache cleared", db.cacheBuild, build) end
        db.cache = {}
        db.cacheBuild = build
    end
    local locale = GetLocale()
    db.cache[locale] = db.cache[locale] or {}

    self.db = db
    ns.Log:Debug("Saved variables ready: %d characters known", self:CountCharacters())
end

function Database:Settings()
    return self.db.settings
end

-- Text cache of the client language: Database:Cache("quests")[questID] = title.
function Database:Cache(kind)
    local cache = self.db.cache[GetLocale()]
    cache[kind] = cache[kind] or {}
    return cache[kind]
end

function Database:ClearCache()
    self.db.cache = { [GetLocale()] = {} }
end

function Database:CountCharacters()
    local count = 0
    for _ in pairs(self.db.characters) do count = count + 1 end
    return count
end

-- Creates or refreshes the record of the logged-in character.
function Database:TouchCharacter()
    local player = ns.Player
    local record = self.db.characters[player.key] or {}
    record.name = player.name
    record.realm = player.realm
    record.class = player.classFile
    record.race = player.raceID
    record.faction = player.faction
    record.level = player.level
    record.lastSeen = time()
    record.quests = record.quests or {}
    record.recipes = record.recipes or {}
    record.professions = record.professions or {}
    record.bosses = record.bosses or {}
    self.db.characters[player.key] = record
    self.character = record
end

function Database:Character()
    return self.character
end

-- Iterates over the records of every known character.
function Database:Characters()
    return pairs(self.db.characters)
end
