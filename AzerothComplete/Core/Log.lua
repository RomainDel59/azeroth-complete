-- Persistent log.
--
-- Entries are kept in the account saved variables (AzerothCompleteDB.log) so that they can
-- be read outside the game after a /reload or a logout, in
-- WTF/Account/<account>/SavedVariables/AzerothComplete.lua. The log is a bounded ring:
-- the oldest entries are dropped first. Debug entries are only kept when debug logging
-- is enabled (/azc debug).

local _, ns = ...

local Log = {}
ns.Log = Log

local MAX_ENTRIES = 3000
local TRIM_CHUNK = 200 -- the ring may exceed its size by this much before trimming
local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local CHAT_COLORS = { WARN = "ffd200", ERROR = "ff4040" }

local pending = {} -- entries written before the saved variables are available
local storage      -- the saved ring, once attached
local session = 0

local function format(message, ...)
    if select("#", ...) == 0 then return tostring(message) end
    local ok, text = pcall(string.format, message, ...)
    if ok then return text end
    -- A bad format string must never hide the original message.
    local parts = { tostring(message) }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    return table.concat(parts, " | ")
end

local function store(entry)
    if not storage then
        pending[#pending + 1] = entry
        return
    end
    local entries = storage.entries
    entries[#entries + 1] = entry
    if #entries > MAX_ENTRIES + TRIM_CHUNK then
        local kept = {}
        for i = #entries - MAX_ENTRIES + 1, #entries do kept[#kept + 1] = entries[i] end
        storage.entries = kept
    end
end

local function write(level, message, ...)
    if level == "DEBUG" and not (storage and storage.debug) then return end
    local text = format(message, ...)
    store(string.format("%s #%d %s %s", date("%Y-%m-%d %H:%M:%S"), session, level, text))
    if CHAT_COLORS[level] and not (storage and storage.quiet) then
        local firstLine = text:match("^[^\n]*")
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff%sAzeroth Complete|r: %s", CHAT_COLORS[level], firstLine))
    end
end

-- Attaches the saved ring; called once the saved variables are loaded.
function Log:Attach(saved)
    saved.entries = saved.entries or {}
    saved.session = (saved.session or 0) + 1
    session = saved.session
    storage = saved
    for _, entry in ipairs(pending) do store(entry) end
    pending = {}
end

function Log:SetDebug(enabled)
    if storage then storage.debug = enabled and true or nil end
end

function Log:IsDebug()
    return storage and storage.debug or false
end

function Log:Clear()
    if storage then storage.entries = {} end
end

-- Returns the last `count` entries, oldest first.
function Log:Tail(count)
    local entries = storage and storage.entries or pending
    local first = math.max(1, #entries - count + 1)
    local result = {}
    for i = first, #entries do result[#result + 1] = entries[i] end
    return result
end

function Log:Debug(message, ...) write("DEBUG", message, ...) end
function Log:Info(message, ...) write("INFO", message, ...) end
function Log:Warn(message, ...) write("WARN", message, ...) end
function Log:Error(message, ...) write("ERROR", message, ...) end

Log.LEVELS = LEVELS
