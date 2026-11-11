-- Localization.
--
-- Every user-facing string of the addon is a key of ns.L. Locale files register their
-- table with ns:RegisterLocale; English is the reference and the fallback, so a missing
-- translation shows the English text, and a missing English key shows the key itself and
-- is logged once. Texts about game content (quests, items, places...) never come from
-- these tables: the client provides them in its own language.

local _, ns = ...

local tables = {}
local reported = {}
local clientLocale = GetLocale()

-- Locales that share a translation: the client reports esMX and esES separately, and
-- enGB clients report enUS.
local ALIASES = { enGB = "enUS" }

function ns:RegisterLocale(locale, strings)
    tables[locale] = strings
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local active = tables[ALIASES[clientLocale] or clientLocale]
        local value = active and active[key] or (tables.enUS and tables.enUS[key])
        if value == nil then
            if not reported[key] then
                reported[key] = true
                if ns.Log then ns.Log:Warn("Missing localized string %q", tostring(key)) end
            end
            return tostring(key)
        end
        return value
    end,
})

-- A label the client itself defines (a global string such as TOY_BOX), so that the addon
-- uses the game's own wording; the addon's string `fallbackKey` is used when it is absent.
function ns:GameLabel(globalName, fallbackKey)
    local value = globalName and _G[globalName]
    if type(value) == "string" and value ~= "" then return value end
    return ns.L[fallbackKey]
end

-- Localized client strings shipped with the data, for the texts the API does not expose.
function ns:GameString(group, id)
    local strings = ns.Data.Strings
    if not strings then return nil end
    local active = strings[ALIASES[clientLocale] or clientLocale]
    local value = active and active[group] and active[group][id]
    if value == nil and strings.enUS and strings.enUS[group] then value = strings.enUS[group][id] end
    return value
end
