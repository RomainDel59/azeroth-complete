-- Slash commands: /azc and /azerothcomplete.

local _, ns = ...

local L = ns.L

local function say(message, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200" .. L.ADDON_TITLE .. "|r: " .. string.format(message, ...))
end

local commands = {}

commands[""] = function() ns.MainFrame:Toggle() end
commands.show = commands[""]

commands.help = function()
    for _, line in ipairs(L.HELP_LINES) do say("%s", line) end
end

commands.log = function(argument)
    local count = tonumber(argument) or 20
    for _, entry in ipairs(ns.Log:Tail(count)) do DEFAULT_CHAT_FRAME:AddMessage(entry) end
end

commands.debug = function()
    ns.Log:SetDebug(not ns.Log:IsDebug())
    say(ns.Log:IsDebug() and L.DEBUG_ON or L.DEBUG_OFF)
end

commands.diag = function()
    for _, line in ipairs(ns.Diagnostics:Report()) do say("%s", line) end
end

commands.scale = function(argument)
    local scale = tonumber(argument)
    if not scale or scale < 0.5 or scale > 2 then
        say(L.SCALE_USAGE)
        return
    end
    ns.MainFrame:SetScale(scale)
    say(L.SCALE_SET, scale)
end

commands.minimap = function()
    local hidden = not ns.Database:Settings().minimap.hidden
    ns.MinimapButton:SetHidden(hidden)
    say(hidden and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

commands.reset = function()
    ns.Database:ClearCache()
    ns.Log:Info("Text cache cleared on request")
    say(L.CACHE_CLEARED)
end

commands.clearlog = function()
    ns.Log:Clear()
    say(L.LOG_CLEARED)
end

commands.rescan = function()
    ns.Quests:Snapshot()
    ns.Professions:Refresh("rescan")
    ns.Collections:Invalidate()
    say(L.RESCANNED)
end

SLASH_AZEROTHCOMPLETE1 = "/azc"
SLASH_AZEROTHCOMPLETE2 = "/azerothcomplete"
SlashCmdList.AZEROTHCOMPLETE = function(input)
    local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    local handler = commands[command]
    if not handler then
        say(L.UNKNOWN_COMMAND, command)
        handler = commands.help
    end
    ns:SafeCall("command " .. command, handler, argument)
end
