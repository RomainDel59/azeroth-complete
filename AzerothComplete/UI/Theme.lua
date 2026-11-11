-- Visual theme: colors, fonts and icons shared by every widget.
--
-- Borders, check marks and the progress ring are drawn with plain color textures rather
-- than texture files, so the look does not depend on art the Forever client may lack.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.colors = {
    window = { 0.045, 0.035, 0.025, 0.97 },
    panel = { 0.075, 0.058, 0.04, 0.96 },
    panelDark = { 0.03, 0.024, 0.018, 0.96 },
    row = { 0.10, 0.08, 0.055, 0.9 },
    rowAlt = { 0.085, 0.067, 0.047, 0.9 },
    rowHover = { 0.16, 0.12, 0.07, 0.95 },
    selected = { 0.07, 0.28, 0.40, 0.95 },
    selectedBorder = { 0.25, 0.55, 0.75, 1 },
    border = { 0.62, 0.47, 0.20, 1 },
    borderDim = { 0.33, 0.25, 0.12, 1 },
    gold = { 1, 0.80, 0.25, 1 },
    goldDim = { 0.80, 0.64, 0.30, 1 },
    text = { 0.93, 0.88, 0.78, 1 },
    textDim = { 0.62, 0.57, 0.49, 1 },
    green = { 0.35, 0.86, 0.38, 1 },
    greenDark = { 0.10, 0.30, 0.12, 0.95 },
    greenBorder = { 0.30, 0.70, 0.32, 1 },
    yellow = { 1, 0.88, 0.30, 1 },
    orange = { 1, 0.55, 0.20, 1 },
    red = { 0.90, 0.25, 0.20, 1 },
    redDark = { 0.40, 0.08, 0.06, 1 },
    gray = { 0.55, 0.55, 0.55, 1 },
    blue = { 0.45, 0.70, 1, 1 },
    ringTrack = { 0.20, 0.17, 0.12, 0.9 },
}

-- Difficulty colors of recipes, as in the profession window.
Theme.difficulty = {
    orange = { 1, 0.50, 0.25, 1 },
    yellow = { 1, 1, 0, 1 },
    green = { 0.25, 0.75, 0.25, 1 },
    gray = { 0.50, 0.50, 0.50, 1 },
}

-- Fonts follow the client language (STANDARD_TEXT_FONT covers every alphabet the client
-- supports); the decorative serif is used only where it has the glyphs.
local WESTERN = { enUS = true, enGB = true, frFR = true, deDE = true, esES = true, esMX = true, itIT = true, ptBR = true }
Theme.fonts = {
    body = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    fancy = WESTERN[GetLocale()] and "Fonts\\MORPHEUS.TTF" or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"),
}

Theme.icons = {
    emblem = "Interface\\AddOns\\AzerothComplete\\Media\\Emblem",
    quests = "Interface\\Icons\\INV_Misc_Note_01",
    professions = "Interface\\Icons\\Trade_BlackSmithing",
    toys = "Interface\\Icons\\INV_Misc_Gift_01",
    dungeons = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    raids = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    achievements = "Interface\\Icons\\INV_Jewelry_Talisman_01",
    collections = "Interface\\Icons\\Ability_Mount_RidingHorse",
    alliance = "Interface\\Icons\\INV_BannerPVP_02",
    horde = "Interface\\Icons\\INV_BannerPVP_01",
    search = "Interface\\Common\\UI-Searchbox-Icon",
    question = "Interface\\Icons\\INV_Misc_QuestionMark",
    mounts = "Interface\\Icons\\Ability_Mount_RidingHorse",
    pets = "Interface\\Icons\\INV_Box_PetCarrier_01",
    sets = "Interface\\Icons\\INV_Chest_Plate03",
    titles = "Interface\\Icons\\INV_Scroll_03",
    boss = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01",
}

function Theme.Unpack(color)
    return color[1], color[2], color[3], color[4] or 1
end

-- Wraps text in a color escape sequence.
function Theme.Colorize(text, color)
    return string.format("|cff%02x%02x%02x%s|r", color[1] * 255, color[2] * 255, color[3] * 255, tostring(text))
end
