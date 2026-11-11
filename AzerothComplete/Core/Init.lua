-- Namespace, event dispatching and the addon lifecycle.
--
-- Every file receives the private namespace `ns` as its second vararg. Modules register
-- themselves with ns:RegisterModule and receive OnInitialize (saved variables ready) and
-- OnLogin (player data ready) calls. Game events and internal messages go through one
-- dispatcher so that every handler runs protected and its errors reach the log.

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.Data = ns.Data or {}
ns.modules = {}
ns.moduleOrder = {}

-------------------------------------------------------------------------------
-- Protected calls
-------------------------------------------------------------------------------

-- Runs fn protected; errors are logged with a traceback (the Log module may not exist yet
-- for the very first files, hence the fallback to the default error handler).
local failureCounts = {} -- ["context|first line"] = occurrences

local function reportFailure(context, message)
    local key = context .. "|" .. (message:match("^[^\n]*") or "")
    local count = (failureCounts[key] or 0) + 1
    failureCounts[key] = count
    if count == 1 then
        ns.Log:Error("%s failed: %s", context, message)
    elseif count % 100 == 0 then
        ns.Log:Error("%s failed %d times (last: %s)", context, count, message:match("^[^\n]*"))
    end
end

function ns:SafeCall(context, fn, ...)
    local args, count = { ... }, select("#", ...)
    local ok, result = xpcall(function() return fn(unpack(args, 1, count)) end, function(err)
        return tostring(err) .. "\n" .. (debugstack and debugstack(2, 12, 0) or "")
    end)
    if not ok then
        if self.Log then
            reportFailure(context, result)
        else
            geterrorhandler()(result)
        end
        return nil
    end
    return result
end

-------------------------------------------------------------------------------
-- Events and messages
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}   -- [event] = { handler, ... }
local messageHandlers = {} -- [message] = { handler, ... }

-- The client fires some game events (skill lines, quest log) before PLAYER_LOGIN, when the
-- character record does not exist yet. They are skipped: every module reads its state again
-- at login.
local LIFECYCLE_EVENTS = { ADDON_LOADED = true, PLAYER_LOGIN = true }
local loggedIn = false
local skippedBeforeLogin = {} -- [event] = count

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = eventHandlers[event]
    if not handlers then return end
    if not loggedIn and not LIFECYCLE_EVENTS[event] then
        skippedBeforeLogin[event] = (skippedBeforeLogin[event] or 0) + 1
        return
    end
    for i = 1, #handlers do
        ns:SafeCall("event " .. event, handlers[i], event, ...)
    end
end)

-- Registers a handler for a game event. Unknown events are logged instead of raising,
-- because the Forever client does not ship every retail event.
function ns:RegisterEvent(event, handler)
    if not eventHandlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            if self.Log then self.Log:Info("Event %s is not available on this client", event) end
            return false
        end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], handler)
    return true
end

-- Internal messages, used to tell the interface that some data changed.
function ns:RegisterMessage(message, handler)
    messageHandlers[message] = messageHandlers[message] or {}
    table.insert(messageHandlers[message], handler)
end

function ns:SendMessage(message, ...)
    local handlers = messageHandlers[message]
    if not handlers then return end
    for i = 1, #handlers do
        self:SafeCall("message " .. message, handlers[i], message, ...)
    end
end

-- Coalesces bursts of identical messages (quest log updates arrive in waves) into one
-- delivery after `delay` seconds.
local pendingMessages = {}
function ns:SendMessageDelayed(message, delay)
    if pendingMessages[message] then return end
    pendingMessages[message] = true
    C_Timer.After(delay or 0.25, function()
        pendingMessages[message] = nil
        ns:SendMessage(message)
    end)
end

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------

function ns:RegisterModule(name, module)
    module = module or {}
    module.name = name
    self.modules[name] = module
    self[name] = module -- reachable as ns.<Name>, like the core services
    table.insert(self.moduleOrder, module)
    return module
end

local function callModules(method)
    for _, module in ipairs(ns.moduleOrder) do
        if module[method] then
            ns:SafeCall(module.name .. "." .. method, module[method], module)
        end
    end
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

ns:RegisterEvent("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= ADDON_NAME then return end
    ns.Database:Initialize()
    ns.Log:Info("%s %s loaded (client %s, locale %s)", ADDON_NAME, ns.Compat.GetAddOnVersion(),
        ns.Compat.GetClientBuild(), GetLocale())
    callModules("OnInitialize")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns.Player:Refresh()
    ns.Database:TouchCharacter()
    loggedIn = true
    local skipped = {}
    for event, count in pairs(skippedBeforeLogin) do skipped[#skipped + 1] = event .. " x" .. count end
    if #skipped > 0 then
        table.sort(skipped)
        ns.Log:Info("Events skipped before login: %s", table.concat(skipped, ", "))
    end
    ns.Diagnostics:Run()
    callModules("OnLogin")
    ns:SendMessage("AC_DATA_READY")
end)
