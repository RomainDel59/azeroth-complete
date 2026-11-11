-- Shared constants. The quest row layout and flags mirror tools/build_data.py.

local _, ns = ...

ns.Const = {
    -- Field indexes of ns.Data.Quests rows.
    Quest = {
        AREA = 1,           -- zone area id (>0), quest sort id (<0) or instance area id
        MIN_LEVEL = 2,
        LEVEL = 3,
        RACES = 4,          -- race bitmask, 0 = every race (may exceed 32 bits)
        CLASSES = 5,        -- class bitmask, 0 = every class
        FLAGS = 6,
        PRE_ALL = 7,        -- every quest of this list must be completed
        PRE_ANY = 8,        -- one quest of this list must be completed
        EXCLUSIVE = 9,      -- completing one of these closes this quest
        NEXT = 10,
        XP = 11,
        GIVER = 12,         -- { kind, id }
        ENDER = 13,         -- { kind, id }
        SKILL = 14,         -- { skillLine, rank }
        REPUTATION = 15,    -- { { factionID, value }, ... }
        BREADCRUMB_FOR = 16,
        NAME_FALLBACK = 17, -- English name, used only when the client cannot provide one
        CRAFT = 18,         -- skillLine of the profession that makes the item a crafting order asks for
    },

    QuestFlag = {
        REPEATABLE = 1,
        DAILY = 2,
        WEEKLY = 4,
        EVENT = 8,
        BREADCRUMB = 16,
    },

    -- Giver kinds of the GIVER and ENDER fields.
    Entity = { NPC = 1, OBJECT = 2, ITEM = 3 },

    -- Field indexes of profession recipe rows.
    Recipe = {
        SPELL = 1,
        MIN_RANK = 2,
        TRIVIAL_LOW = 3,
        TRIVIAL_HIGH = 4,
        AUTO_LEARNED = 5,
        CREATED_ITEM = 6,
        REAGENTS = 7,      -- { { itemID, count }, ... }
        SOURCES = 8,       -- { { item = recipeItem, vendors = {...}, npcDrops = {...}, ... }, ... }
    },

    -- Continent groups of quest zones.
    Continent = {
        EASTERN_KINGDOMS = 0,
        KALIMDOR = 1,
        BATTLEGROUNDS = 2,
        OTHER = 3,
        CATEGORIES = 4, -- quest sorts: classes, professions, events
    },

    Instance = { DUNGEON = 1, RAID = 2 },

    -- Quest statuses, from the most to the least advanced.
    Status = {
        DONE = "done",
        ACTIVE = "active",
        AVAILABLE = "available",
        LOCKED = "locked",
        REPEATABLE = "repeatable",
    },

    Tracking = { ACCOUNT = "account", CHARACTER = "character" },
    Faction = { ALLIANCE = "Alliance", HORDE = "Horde" },
}
