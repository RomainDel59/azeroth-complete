-- The logged-in character, and the race and class filters derived from it.

local _, ns = ...

local Player = {}
ns.Player = Player

-- Tests one bit of a mask that may exceed 32 bits (WoW Forever race bits go past 31,
-- which the client's 32-bit `bit` library cannot handle).
function ns.HasBit(mask, bitIndex)
    if not bitIndex or bitIndex < 0 then return false end
    local power = 2 ^ bitIndex
    return math.floor(mask / power) % 2 == 1
end

-- True when `mask` intersects `bits` (both possibly wider than 32 bits).
function ns.MasksIntersect(mask, bits)
    while mask > 0 and bits > 0 do
        if mask % 2 == 1 and bits % 2 == 1 then return true end
        mask = math.floor(mask / 2)
        bits = math.floor(bits / 2)
    end
    return false
end

function Player:Refresh()
    self.name = UnitName("player")
    self.realm = GetRealmName()
    self.key = string.format("%s-%s", self.name or "?", self.realm or "?")
    local _, classFile, classID = UnitClass("player")
    self.classFile = classFile
    self.classID = classID
    local _, _, raceID = UnitRace("player")
    self.raceID = raceID
    self.faction = UnitFactionGroup("player")
    self.level = UnitLevel("player")
    local races = ns.Data.Races
    self.raceBit = races and races.raceBits[raceID]
    ns.Log:Info("Player %s: race %s (bit %s), class %s (%s), level %s, %s", self.key, tostring(raceID),
        tostring(self.raceBit), tostring(classFile), tostring(classID), tostring(self.level), tostring(self.faction))
end

-- Race mask of a faction, used by the account view and the faction selector.
function Player:FactionRaces(faction)
    local races = ns.Data.Races
    if faction == ns.Const.Faction.HORDE then return races.hordeRaces end
    return races.allianceRaces
end

function Player:CanRace(mask)
    return mask == 0 or ns.HasBit(mask, self.raceBit)
end

-- Class masks use bit (classID - 1).
function Player:CanClass(mask)
    return mask == 0 or ns.HasBit(mask, (self.classID or 0) - 1)
end

ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
    Player.level = level
    if ns.Database.character then ns.Database.character.level = level end
    ns:SendMessage("AC_PROGRESS_CHANGED")
end)
