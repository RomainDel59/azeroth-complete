-- Reusable widgets. Every view is assembled from these, so the look stays consistent and
-- a change of style happens in one place.

local _, ns = ...

local UI = {}
ns.UI = UI

local Theme = ns.Theme
local C = Theme.colors

-------------------------------------------------------------------------------
-- Primitives
-------------------------------------------------------------------------------

function UI.Solid(parent, layer, color, subLevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel)
    texture:SetColorTexture(Theme.Unpack(color))
    return texture
end

-- One-pixel border made of four textures, recolorable with border:SetColor(color).
function UI.Border(frame, color, thickness, layer)
    thickness = thickness or 1
    local border = {}
    local function edge()
        local texture = frame:CreateTexture(nil, layer or "BORDER")
        border[#border + 1] = texture
        return texture
    end
    local top, bottom, left, right = edge(), edge(), edge(), edge()
    top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(thickness)
    function border.SetColor(_, newColor)
        for i = 1, 4 do border[i]:SetColorTexture(Theme.Unpack(newColor)) end
    end
    function border.SetShown(_, shown)
        for i = 1, 4 do border[i]:SetShown(shown) end
    end
    border:SetColor(color or C.border)
    return border
end

function UI.Text(parent, size, color, family, justify, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(Theme.fonts[family or "body"], size or 12, "")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetTextColor(Theme.Unpack(color or C.text))
    text:SetJustifyH(justify or "LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    return text
end

-- Text that wraps on several lines inside a fixed width.
function UI.Paragraph(parent, size, color, width)
    local text = UI.Text(parent, size, color)
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
    text:SetJustifyV("TOP")
    if width then text:SetWidth(width) end
    return text
end

function UI.Icon(parent, size, path)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if path then icon:SetTexture(path) end
    return icon
end

-- Icon framed by a thin border, as item buttons are.
function UI.FramedIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    UI.Solid(frame, "BACKGROUND", C.panelDark)
    frame.icon = UI.Icon(frame, size - 2)
    frame.icon:SetPoint("CENTER")
    frame.border = UI.Border(frame, C.borderDim)
    function frame.SetIcon(_, path)
        frame.icon:SetTexture(path or Theme.icons.question)
    end
    return frame
end

-------------------------------------------------------------------------------
-- Glyphs drawn from bars: check mark, plus, minus, cross
-------------------------------------------------------------------------------

local function bar(frame, width, height, x, y, angle, color)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetColorTexture(Theme.Unpack(color))
    texture:SetSize(width, height)
    texture:SetPoint("CENTER", frame, "CENTER", x, y)
    if angle ~= 0 then texture:SetRotation(math.rad(angle)) end
    return texture
end

function UI.Glyph(parent, kind, size, color)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame.bars = {}
    local s = size
    if kind == "check" then
        frame.bars[1] = bar(frame, s * 0.42, s * 0.16, -s * 0.2, -s * 0.06, -45, color)
        frame.bars[2] = bar(frame, s * 0.80, s * 0.16, s * 0.12, s * 0.04, 52, color)
    elseif kind == "plus" or kind == "minus" then
        frame.bars[1] = bar(frame, s * 0.62, s * 0.16, 0, 0, 0, color)
        if kind == "plus" then frame.bars[2] = bar(frame, s * 0.16, s * 0.62, 0, 0, 0, color) end
    elseif kind == "cross" then
        frame.bars[1] = bar(frame, s * 0.85, s * 0.15, 0, 0, 45, color)
        frame.bars[2] = bar(frame, s * 0.85, s * 0.15, 0, 0, -45, color)
    elseif kind == "arrow" then
        frame.bars[1] = bar(frame, s * 0.50, s * 0.16, 0, s * 0.15, -40, color)
        frame.bars[2] = bar(frame, s * 0.50, s * 0.16, 0, -s * 0.15, 40, color)
    end
    function frame.SetColor(_, newColor)
        for _, texture in ipairs(frame.bars) do texture:SetColorTexture(Theme.Unpack(newColor)) end
    end
    return frame
end

-- Small boxed "+" / "-" used to expand quest chains.
function UI.ExpandBox(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    UI.Solid(frame, "BACKGROUND", C.redDark)
    UI.Border(frame, C.goldDim)
    frame.plus = UI.Glyph(frame, "plus", size, C.gold)
    frame.plus:SetPoint("CENTER")
    frame.minus = UI.Glyph(frame, "minus", size, C.gold)
    frame.minus:SetPoint("CENTER")
    function frame.SetExpanded(_, expanded)
        frame.plus:SetShown(not expanded)
        frame.minus:SetShown(expanded)
    end
    frame:SetExpanded(false)
    return frame
end

-------------------------------------------------------------------------------
-- Panels and buttons
-------------------------------------------------------------------------------

-- Dark panel with a gold border and a faint inner glow at the top.
function UI.Panel(parent, color, borderColor)
    local frame = CreateFrame("Frame", nil, parent)
    frame.bg = UI.Solid(frame, "BACKGROUND", color or C.panel)
    frame.bg:SetAllPoints()
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("TOPRIGHT", -1, -1)
    glow:SetHeight(40)
    glow:SetColorTexture(1, 1, 1, 1)
    if glow.SetGradient and CreateColor then
        glow:SetGradient("VERTICAL", CreateColor(0.55, 0.40, 0.15, 0), CreateColor(0.55, 0.40, 0.15, 0.10))
    else
        glow:SetAlpha(0.03)
    end
    frame.border = UI.Border(frame, borderColor or C.borderDim)
    return frame
end

-- Panel title, uppercase gold, centered.
function UI.Heading(parent, size, text, family)
    local heading = UI.Text(parent, size or 18, C.gold, family or "body", "CENTER")
    heading:SetText(text and text:upper() or "")
    return heading
end

-- Text button with a dark background, a gold border and an "active" state.
function UI.Button(parent, width, height, label, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.bg = UI.Solid(button, "BACKGROUND", C.panelDark)
    button.bg:SetAllPoints()
    button.border = UI.Border(button, C.borderDim)
    button.highlight = UI.Solid(button, "HIGHLIGHT", { 1, 0.85, 0.45, 0.08 })
    button.highlight:SetAllPoints()
    button.label = UI.Text(button, 12, C.text, "body", "CENTER")
    button.label:SetPoint("LEFT", 6, 0)
    button.label:SetPoint("RIGHT", -6, 0)
    button.label:SetText(label or "")
    function button.SetActive(self, active, activeColor)
        self.active = active
        if active then
            self.bg:SetColorTexture(Theme.Unpack(activeColor and activeColor.bg or { 0.22, 0.15, 0.06, 0.95 }))
            self.border:SetColor(activeColor and activeColor.border or C.border)
            self.label:SetTextColor(Theme.Unpack(activeColor and activeColor.text or C.gold))
        else
            self.bg:SetColorTexture(Theme.Unpack(C.panelDark))
            self.border:SetColor(C.borderDim)
            self.label:SetTextColor(Theme.Unpack(C.text))
        end
    end
    function button.SetLabel(self, text) self.label:SetText(text) end
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- Tab button: icon + label.
function UI.TabButton(parent, width, height, icon, label, onClick)
    local button = UI.Button(parent, width, height, label, onClick)
    button.icon = UI.FramedIcon(button, height - 8)
    button.icon:SetPoint("LEFT", 6, 0)
    button.icon:SetIcon(icon)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 8, 0)
    button.label:SetPoint("RIGHT", -6, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetFont(Theme.fonts.body, 13, "")
    return button
end

-- Square close button with a drawn cross.
function UI.CloseButton(parent, size, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    UI.Solid(button, "BACKGROUND", C.redDark):SetAllPoints()
    UI.Border(button, C.gold)
    local cross = UI.Glyph(button, "cross", size * 0.8, C.gold)
    cross:SetPoint("CENTER")
    local highlight = UI.Solid(button, "HIGHLIGHT", { 1, 0.3, 0.2, 0.25 })
    highlight:SetAllPoints()
    button:SetScript("OnClick", onClick)
    return button
end

-------------------------------------------------------------------------------
-- Progress
-------------------------------------------------------------------------------

-- Ring of small segments filled clockwise from the top, with the percentage inside.
function UI.ProgressRing(parent, size, segments)
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(size, size)
    segments = segments or 64
    ring.segments = {}
    local radius = size / 2 - 4
    local length = (2 * math.pi * radius) / segments * 0.8
    for i = 1, segments do
        local angle = (i - 0.5) / segments * 2 * math.pi
        local segment = ring:CreateTexture(nil, "ARTWORK")
        segment:SetSize(length, 6)
        segment:SetPoint("CENTER", ring, "CENTER", math.sin(angle) * radius, math.cos(angle) * radius)
        segment:SetRotation(-angle)
        segment:SetColorTexture(Theme.Unpack(C.ringTrack))
        ring.segments[i] = segment
    end
    local disc = UI.Solid(ring, "BACKGROUND", { 0, 0, 0, 0.45 })
    disc:SetPoint("CENTER")
    disc:SetSize(size * 0.74, size * 0.74)
    ring.percent = UI.Text(ring, math.floor(size * 0.27), C.green, "fancy", "CENTER")
    ring.percent:SetPoint("CENTER", 0, size * 0.06)
    ring.caption = UI.Text(ring, math.max(9, math.floor(size * 0.09)), C.text, "body", "CENTER")
    ring.caption:SetPoint("TOP", ring.percent, "BOTTOM", 0, -2)
    function ring.SetProgress(_, done, total, caption)
        local fraction = total > 0 and done / total or 0
        local filled = math.floor(fraction * segments + 0.5)
        local color = fraction >= 1 and C.gold or C.green
        for i = 1, segments do
            ring.segments[i]:SetColorTexture(Theme.Unpack(i <= filled and color or C.ringTrack))
        end
        ring.percent:SetText(total > 0 and string.format("%d%%", math.floor(fraction * 100)) or "-")
        ring.percent:SetTextColor(Theme.Unpack(color))
        ring.caption:SetText(caption or "")
    end
    return ring
end

-- Thin horizontal progress bar.
function UI.ProgressBar(parent, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(height or 4)
    UI.Solid(frame, "BACKGROUND", C.ringTrack):SetAllPoints()
    frame.fill = UI.Solid(frame, "ARTWORK", C.green)
    frame.fill:SetPoint("TOPLEFT")
    frame.fill:SetPoint("BOTTOMLEFT")
    function frame.SetProgress(_, done, total)
        local fraction = total > 0 and math.min(1, done / total) or 0
        frame.fraction = fraction
        frame.fill:SetShown(fraction > 0)
        frame.fill:SetWidth(math.max(1, (frame:GetWidth() or 0) * fraction))
        frame.fill:SetColorTexture(Theme.Unpack(fraction >= 1 and C.gold or C.green))
    end
    frame:SetScript("OnSizeChanged", function()
        if frame.fraction then frame.fill:SetWidth(math.max(1, (frame:GetWidth() or 0) * frame.fraction)) end
    end)
    return frame
end

-------------------------------------------------------------------------------
-- Artwork: zone maps, loading screens, or a plain gradient
-------------------------------------------------------------------------------

-- Frame that crops artwork to its own bounds. SetMap shows the world map art of a zone,
-- SetFile a single texture (a loading screen); without art, a gradient remains.
-- The game draws every child frame above the regions of its parent, so texts and borders
-- created on the parent would be hidden by the artwork: they belong on `frame.overlay`.
function UI.Art(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetClipsChildren(true)
    frame.fallback = UI.Solid(frame, "BACKGROUND", { 0.16, 0.12, 0.07, 1 })
    frame.fallback:SetAllPoints()
    frame.canvas = CreateFrame("Frame", nil, frame)
    frame.canvas:SetPoint("CENTER")
    frame.tiles = {}
    frame.exploration = {}
    frame.overlay = CreateFrame("Frame", nil, frame)
    frame.overlay:SetAllPoints()
    frame.overlay:SetFrameLevel(frame.canvas:GetFrameLevel() + 1)
    frame.shade = frame.overlay:CreateTexture(nil, "BACKGROUND")
    frame.shade:SetPoint("BOTTOMLEFT")
    frame.shade:SetPoint("BOTTOMRIGHT")
    frame.shade:SetColorTexture(0, 0, 0, 1)
    if frame.shade.SetGradient and CreateColor then
        frame.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.85), CreateColor(0, 0, 0, 0))
    else
        frame.shade:SetAlpha(0.4)
    end

    local function hideTiles()
        for _, tile in ipairs(frame.tiles) do tile:Hide() end
        for _, tile in ipairs(frame.exploration) do tile:Hide() end
    end

    function frame.SetShade(_, fraction)
        frame.shade:SetHeight(math.max(1, (frame:GetHeight() or 0) * fraction))
    end

    -- Darkens the whole artwork, more at the bottom than at the top, for frames that hold
    -- text from top to bottom.
    function frame.DarkenFully(_, bottomAlpha, topAlpha)
        frame.shadeFraction = 1
        if frame.shade.SetGradient and CreateColor then
            frame.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, bottomAlpha), CreateColor(0, 0, 0, topAlpha))
        end
    end

    -- The artwork is drawn once the frame has a size; until then the request stays pending
    -- and OnSizeChanged draws it.
    local function sized()
        local width = frame:GetWidth()
        return width and width > 0 and (frame:GetHeight() or 0) > 0
    end

    function frame.Clear()
        hideTiles()
        frame.request = nil
    end

    -- Size of a tile file: full tiles are 256 pixels, the last one of a row or column is the
    -- smallest power of two that holds the remainder, as the game lays them out.
    local OVERLAY_TILE = 256
    local function tileExtent(index, count, total)
        if index < count - 1 then return OVERLAY_TILE, OVERLAY_TILE end
        local pixels = total - OVERLAY_TILE * (count - 1)
        local file = 16
        while file < pixels do file = file * 2 end
        return pixels, file
    end

    -- Exploration overlays: the painted areas the game reveals over the bare parchment.
    local function drawExploration(overlays, scale)
        local used = 0
        for _, overlay in ipairs(overlays or {}) do
            local width, height, offsetX, offsetY, files = overlay[1], overlay[2], overlay[3], overlay[4], overlay[5]
            local columns = math.ceil(width / OVERLAY_TILE)
            local rows = math.ceil(height / OVERLAY_TILE)
            for index, fileID in ipairs(files) do
                used = used + 1
                local tile = frame.exploration[used]
                if not tile then
                    tile = frame.canvas:CreateTexture(nil, "BACKGROUND", nil, 2)
                    frame.exploration[used] = tile
                end
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                local pixelWidth, fileWidth = tileExtent(column, columns, width)
                local pixelHeight, fileHeight = tileExtent(row, rows, height)
                tile:ClearAllPoints()
                tile:SetSize(pixelWidth * scale, pixelHeight * scale)
                tile:SetPoint("TOPLEFT", frame.canvas, "TOPLEFT", (offsetX + column * OVERLAY_TILE) * scale,
                    -(offsetY + row * OVERLAY_TILE) * scale)
                tile:SetTexture(fileID)
                tile:SetTexCoord(0, pixelWidth / fileWidth, 0, pixelHeight / fileHeight)
                tile:Show()
            end
        end
    end

    -- Map tiles are laid out on a canvas that covers the frame, centered, keeping the ratio.
    local function drawMap(layer, textures, overlays, dimmed)
        local width, height = frame:GetWidth(), frame:GetHeight()
        local columns = math.ceil(layer.layerWidth / layer.tileWidth)
        local scale = math.max(width / layer.layerWidth, height / layer.layerHeight)
        local tileW, tileH = layer.tileWidth * scale, layer.tileHeight * scale
        frame.canvas:SetSize(layer.layerWidth * scale, layer.layerHeight * scale)
        for index, fileID in ipairs(textures) do
            local tile = frame.tiles[index]
            if not tile then
                tile = frame.canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
                frame.tiles[index] = tile
            end
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            tile:ClearAllPoints()
            tile:SetSize(tileW, tileH)
            tile:SetPoint("TOPLEFT", frame.canvas, "TOPLEFT", column * tileW, -row * tileH)
            tile:SetTexture(fileID)
            tile:SetTexCoord(0, 1, 0, 1)
            tile:SetVertexColor(dimmed and 0.45 or 1, dimmed and 0.45 or 1, dimmed and 0.45 or 1)
            tile:Show()
        end
        drawExploration(overlays, scale)
    end

    -- `top` and `bottom` keep a horizontal band of the texture, in fractions of its height.
    local function drawFile(fileID, ratio, top, bottom)
        local tile = frame.tiles[1] or frame.canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame.tiles[1] = tile
        top, bottom = top or 0, bottom or 1
        ratio = ratio / (bottom - top)
        local width, height = frame:GetWidth(), frame:GetHeight()
        local scale = math.max(width / ratio, height)
        frame.canvas:SetSize(scale * ratio, scale)
        tile:ClearAllPoints()
        tile:SetAllPoints(frame.canvas)
        tile:SetTexture(fileID)
        tile:SetTexCoord(0, 1, top, bottom)
        tile:SetVertexColor(1, 1, 1)
        tile:Show()
    end

    local function draw()
        local request = frame.request
        if not request or not sized() then return end
        hideTiles()
        if request.kind == "map" then
            drawMap(request.layer, request.textures, request.overlays, request.dimmed)
        else
            drawFile(request.fileID, request.ratio, request.top, request.bottom)
        end
    end

    -- Shows the world map art of a zone, fully explored, darkened when `dimmed` (a
    -- continent standing for a zone); returns false when the client has none for it.
    function frame.SetMap(_, uiMapID, dimmed)
        local key = "map:" .. tostring(uiMapID) .. (dimmed and ":dimmed" or "")
        if frame.request and frame.request.key == key then return true end
        local layer, textures
        if uiMapID then layer, textures = ns.Compat.GetMapArt(uiMapID) end
        if not layer then return false end
        frame.request = { key = key, kind = "map", layer = layer, textures = textures, dimmed = dimmed,
            overlays = ns.Data.MapOverlays and ns.Data.MapOverlays[uiMapID] }
        draw()
        return true
    end

    -- Shows a single texture covering the frame, cropped to keep its ratio (width / height),
    -- optionally reduced to the band between `top` and `bottom` (fractions of its height).
    function frame.SetFile(_, fileID, ratio, top, bottom)
        if not fileID or fileID == 0 then return false end
        local key = string.format("file:%s:%s:%s:%s", tostring(fileID), tostring(ratio), tostring(top), tostring(bottom))
        if frame.request and frame.request.key == key then return true end
        frame.request = { key = key, kind = "file", fileID = fileID, ratio = ratio or 16 / 9, top = top, bottom = bottom }
        draw()
        return true
    end

    -- Shows a loading screen. A framed one (the 4:3 images of the original client) keeps the
    -- painting between its parchment bands, which carry the game logo.
    function frame.SetLoadingScreen(_, fileID, framed)
        if framed then return frame:SetFile(fileID, 4 / 3, 0.23, 0.79) end
        return frame:SetFile(fileID, 16 / 9)
    end

    frame:SetScript("OnSizeChanged", function()
        draw()
        frame:SetShade(frame.shadeFraction or 0.6)
    end)
    return frame
end

-- List card with artwork, as high as its two lines of text: the name across the top, the
-- level range and the count below it, with a border and a hover glow, all drawn above the
-- artwork, which is darkened to keep both lines readable.
UI.ART_CARD_HEIGHT = 46

function UI.ArtCard(row)
    row.art = UI.Art(row)
    row.art:SetAllPoints()
    row.art:DarkenFully(0.8, 0.45)
    local overlay = row.art.overlay
    row.border = UI.Border(overlay, C.borderDim, 2)
    row.name = UI.Text(overlay, 14, C.text)
    row.name:SetPoint("TOPLEFT", 10, -7)
    row.name:SetPoint("TOPRIGHT", -10, -7)
    row.count = UI.Text(overlay, 12, C.text, "body", "RIGHT")
    row.count:SetPoint("BOTTOMRIGHT", -10, 7)
    row.levels = UI.Text(overlay, 11, C.goldDim)
    row.levels:SetPoint("BOTTOMLEFT", 10, 7)
    row.levels:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMLEFT", -6, 0)
    -- The highlight layer only follows the mouse on the button itself, under the artwork.
    row.hover = UI.Solid(overlay, "ARTWORK", { 1, 0.85, 0.45, 0.08 })
    row.hover:SetAllPoints()
    row.hover:Hide()
    row:HookScript("OnEnter", function() row.hover:Show() end)
    row:HookScript("OnLeave", function() row.hover:Hide() end)
end

-------------------------------------------------------------------------------
-- Scrolling
-------------------------------------------------------------------------------

-- Thin vertical scroll bar driven by a list or a scroll frame.
local function ScrollBar(parent, onScroll)
    local track = CreateFrame("Slider", nil, parent)
    track:SetWidth(8)
    track:SetOrientation("VERTICAL")
    UI.Solid(track, "BACKGROUND", { 0, 0, 0, 0.5 }):SetAllPoints()
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(Theme.Unpack(C.goldDim))
    thumb:SetSize(8, 30)
    track:SetThumbTexture(thumb)
    track:SetMinMaxValues(0, 0)
    track:SetValueStep(1)
    if track.SetObeyStepOnDrag then track:SetObeyStepOnDrag(true) end
    local muted = false
    track:SetScript("OnValueChanged", function(_, value)
        if not muted then onScroll(math.floor(value + 0.5)) end
    end)

    -- Sets the range and the value. The client places the thumb only when the value changes,
    -- so a range or a size given while the value stays the same would leave it hidden until
    -- the first scroll: the value goes to the other end of the range and back, silently.
    function track.Sync(_, value, maxValue)
        if maxValue then track:SetMinMaxValues(0, maxValue) end
        local low, high = track:GetMinMaxValues()
        value = math.max(low, math.min(high, value or track:GetValue()))
        muted = true
        track:SetValue(value == high and low or high)
        track:SetValue(value)
        muted = false
    end
    track:SetScript("OnSizeChanged", function() track:Sync() end)
    track:SetScript("OnShow", function() track:Sync() end)
    return track
end

-- Virtualized list: only the visible rows exist. `build(row)` creates a row's widgets
-- once; `fill(row, item, index)` shows an item in it. Items are any Lua values.
function UI.ScrollList(parent, rowHeight, build, fill, spacing)
    local list = CreateFrame("Frame", nil, parent)
    list.rowHeight = rowHeight
    list.spacing = spacing or 2
    list.items = {}
    list.rows = {}
    list.offset = 0

    list.content = CreateFrame("Frame", nil, list)
    list.content:SetPoint("TOPLEFT")
    list.content:SetPoint("BOTTOMRIGHT", -12, 0)

    local function visibleCount()
        local height = list:GetHeight() or 0
        return math.max(1, math.floor((height + list.spacing) / (rowHeight + list.spacing)))
    end

    function list.Redraw()
        local count = visibleCount()
        for i = 1, count do
            local row = list.rows[i]
            if not row then
                row = CreateFrame("Button", nil, list.content)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowHeight + list.spacing))
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * (rowHeight + list.spacing))
                row:EnableMouseWheel(true)
                row:SetScript("OnMouseWheel", function(_, delta) list:Scroll(-delta) end)
                build(row)
                list.rows[i] = row
            end
            local index = list.offset + i
            local item = list.items[index]
            if item ~= nil then
                row:Show()
                row.item, row.index = item, index
                ns:SafeCall("ScrollList.fill", fill, row, item, index)
            else
                row:Hide()
                row.item, row.index = nil, nil
            end
        end
        for i = count + 1, #list.rows do list.rows[i]:Hide() end
        local maxOffset = math.max(0, #list.items - count)
        list.scrollBar:SetShown(maxOffset > 0)
        list.scrollBar:Sync(list.offset, maxOffset)
    end

    -- A wheel notch moves one row.
    function list.Scroll(_, delta)
        local maxOffset = math.max(0, #list.items - visibleCount())
        local offset = math.max(0, math.min(maxOffset, list.offset + delta))
        if offset ~= list.offset then
            list.offset = offset
            list:Redraw()
        end
    end

    function list.SetItems(_, items, keepOffset)
        list.items = items or {}
        if not keepOffset then list.offset = 0 end
        local maxOffset = math.max(0, #list.items - visibleCount())
        list.offset = math.min(list.offset, maxOffset)
        list:Redraw()
    end

    -- Scrolls so that the item at `index` is visible.
    function list.Reveal(_, index)
        local count = visibleCount()
        if index <= list.offset then
            list.offset = index - 1
        elseif index > list.offset + count then
            list.offset = index - count
        end
        list:Redraw()
    end

    list.scrollBar = ScrollBar(list, function(value)
        if value ~= list.offset then
            list.offset = value
            list:Redraw()
        end
    end)
    list.scrollBar:SetPoint("TOPRIGHT")
    list.scrollBar:SetPoint("BOTTOMRIGHT")

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) list:Scroll(-delta) end)
    list:SetScript("OnSizeChanged", function() list:Redraw() end)
    return list
end

-- Standard selectable row: background, hover, selection and a left accent.
function UI.DecorateRow(row)
    row.bg = UI.Solid(row, "BACKGROUND", C.row)
    row.bg:SetAllPoints()
    row.border = UI.Border(row, C.borderDim)
    row.hover = UI.Solid(row, "HIGHLIGHT", { 1, 0.85, 0.45, 0.07 })
    row.hover:SetAllPoints()
    function row.SetState(self, selected, accent)
        if selected then
            self.bg:SetColorTexture(Theme.Unpack(C.selected))
            self.border:SetColor(C.selectedBorder)
        elseif accent then
            self.bg:SetColorTexture(Theme.Unpack(accent.bg))
            self.border:SetColor(accent.border)
        else
            self.bg:SetColorTexture(Theme.Unpack(C.row))
            self.border:SetColor(C.borderDim)
        end
    end
end

-------------------------------------------------------------------------------
-- Detail panel: a scrolling column of headings, lines, icons and buttons
-------------------------------------------------------------------------------

function UI.DetailPanel(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll.child = child
    scroll.widgets = {}   -- every widget ever created, reused by kind
    scroll.used = {}
    scroll.y = 0

    local bar = ScrollBar(scroll, function(value) scroll:SetVerticalScroll(value) end)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    scroll.bar = bar

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        local value = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 30))
        self:SetVerticalScroll(value)
        bar:SetValue(value)
    end)

    local function width()
        return math.max(50, (scroll:GetWidth() or 300) - 16)
    end

    local function acquire(kind, create)
        scroll.widgets[kind] = scroll.widgets[kind] or {}
        scroll.used[kind] = (scroll.used[kind] or 0) + 1
        local widget = scroll.widgets[kind][scroll.used[kind]]
        if not widget then
            widget = create()
            scroll.widgets[kind][scroll.used[kind]] = widget
        end
        widget:ClearAllPoints()
        widget:Show()
        return widget
    end

    -- Starts a rebuild. Redrawing the same `subject` (any key naming what is shown) keeps
    -- the scroll position; a new subject starts at the top.
    function scroll.Clear(_, subject)
        for _, widgets in pairs(scroll.widgets) do
            for _, widget in ipairs(widgets) do widget:Hide() end
        end
        scroll.used = {}
        scroll.y = 0
        scroll.keptScroll = subject ~= nil and subject == scroll.subject and scroll:GetVerticalScroll() or nil
        scroll.subject = subject
        if not scroll.keptScroll then
            scroll:SetVerticalScroll(0)
            bar:SetValue(0)
        end
    end

    local function place(widget, height, indent)
        widget:SetPoint("TOPLEFT", child, "TOPLEFT", indent or 0, -scroll.y)
        scroll.y = scroll.y + height
    end

    function scroll.Space(_, height)
        scroll.y = scroll.y + (height or 8)
    end

    -- A line of text, wrapped to the panel width; returns the font string.
    function scroll.Line(_, text, color, size, family, indent)
        local line = acquire("line", function() return UI.Paragraph(child, 12) end)
        line:SetFont(Theme.fonts[family or "body"], size or 12, "")
        line:SetTextColor(Theme.Unpack(color or C.text))
        line:SetWidth(width() - (indent or 0))
        line:SetText(text or "")
        place(line, (line:GetStringHeight() or 14) + 4, indent)
        return line
    end

    function scroll.Heading(_, text, color)
        scroll:Space(6)
        local line = scroll:Line(text and text:upper() or "", color or C.gold, 14)
        local rule = acquire("rule", function() return UI.Solid(child, "ARTWORK", C.borderDim) end)
        rule:SetSize(width(), 1)
        place(rule, 6)
        return line
    end

    -- Icon, text and optional right-aligned text on one row.
    function scroll.IconLine(_, icon, text, rightText, color, onClick, tooltip)
        local row = acquire("iconLine", function()
            local frame = CreateFrame("Button", nil, child)
            frame:SetHeight(26)
            frame.icon = UI.FramedIcon(frame, 22)
            frame.icon:SetPoint("LEFT", 0, 0)
            frame.text = UI.Text(frame, 12)
            frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
            frame.right = UI.Text(frame, 12, C.text, "body", "RIGHT")
            frame.right:SetPoint("RIGHT", -4, 0)
            frame.text:SetPoint("RIGHT", frame.right, "LEFT", -6, 0)
            frame.hover = UI.Solid(frame, "HIGHLIGHT", { 1, 0.85, 0.45, 0.07 })
            frame.hover:SetAllPoints()
            return frame
        end)
        row:SetWidth(width())
        row.icon:SetIcon(icon)
        row.text:SetText(text or "")
        row.text:SetTextColor(Theme.Unpack(color or C.text))
        row.right:SetText(rightText or "")
        row:SetScript("OnClick", onClick)
        row:SetScript("OnEnter", tooltip and function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltip(GameTooltip)
            GameTooltip:Show()
        end or nil)
        row:SetScript("OnLeave", tooltip and function() GameTooltip:Hide() end or nil)
        place(row, 28)
        return row
    end

    function scroll.Button(_, label, onClick)
        local button = acquire("button", function() return UI.Button(child, 160, 22, "") end)
        button:SetLabel(label)
        button:SetWidth(math.min(width(), math.max(120, (button.label:GetStringWidth() or 100) + 24)))
        button:SetScript("OnClick", onClick)
        place(button, 28)
        return button
    end

    -- Large title with an icon, as at the top of a recipe or achievement.
    function scroll.Title(_, icon, title, subtitle, titleColor, subtitleColor)
        local block = acquire("title", function()
            local frame = CreateFrame("Frame", nil, child)
            frame:SetHeight(56)
            frame.icon = UI.FramedIcon(frame, 50)
            frame.icon:SetPoint("LEFT")
            frame.title = UI.Paragraph(frame, 17)
            frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -4)
            frame.subtitle = UI.Text(frame, 11)
            frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
            return frame
        end)
        block:SetWidth(width())
        block.icon:SetShown(icon ~= false)
        if icon ~= false then block.icon:SetIcon(icon) end
        block.title:ClearAllPoints()
        if icon ~= false then
            block.title:SetPoint("TOPLEFT", block.icon, "TOPRIGHT", 10, -4)
            block.title:SetWidth(width() - 64)
        else
            block.title:SetPoint("TOPLEFT", 0, -4)
            block.title:SetWidth(width())
        end
        block.title:SetText(title or "")
        block.title:SetTextColor(Theme.Unpack(titleColor or C.gold))
        block.subtitle:SetText(subtitle and subtitle:upper() or "")
        block.subtitle:SetTextColor(Theme.Unpack(subtitleColor or C.orange))
        local height = math.max(56, (block.title:GetStringHeight() or 20) + 28)
        block:SetHeight(height)
        place(block, height + 4)
        return block
    end

    -- Ends a rebuild: sizes the scroll child and the scroll bar.
    function scroll.Finish()
        child:SetSize(width(), math.max(1, scroll.y))
        local maxScroll = math.max(0, scroll.y - (scroll:GetHeight() or 0))
        bar:SetShown(maxScroll > 0)
        local value = math.min(scroll.keptScroll or scroll:GetVerticalScroll() or 0, maxScroll)
        scroll:SetVerticalScroll(value)
        bar:Sync(value, maxScroll)
        scroll.keptScroll = nil
    end

    return scroll
end

-------------------------------------------------------------------------------
-- Inputs
-------------------------------------------------------------------------------

function UI.SearchBox(parent, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(26)
    box:SetAutoFocus(false)
    box:SetFont(Theme.fonts.body, 12, "")
    box:SetTextColor(Theme.Unpack(C.text))
    box:SetTextInsets(26, 8, 0, 0)
    UI.Solid(box, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints()
    UI.Border(box, C.borderDim)
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture(Theme.icons.search)
    local hint = UI.Text(box, 12, C.textDim)
    hint:SetPoint("LEFT", 26, 0)
    hint:SetText(placeholder or "")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        hint:SetShown(text == "")
        if onChange then onChange(text) end
    end)
    return box
end

-- Case- and accent-insensitive "contains" used by the search boxes.
local ACCENTS = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e",
    ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["í"] = "i", ["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["ù"] = "u",
    ["û"] = "u", ["ü"] = "u", ["ú"] = "u", ["ñ"] = "n", ["œ"] = "oe", ["’"] = "'",
    ["À"] = "a", ["Â"] = "a", ["Ç"] = "c", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Î"] = "i", ["Ô"] = "o",
    ["Û"] = "u", ["Œ"] = "oe",
}
function UI.Normalize(text)
    text = (text or ""):lower()
    text = text:gsub("[\195\197\226][\128-\191]+", function(char) return ACCENTS[char] or char end)
    return text
end

function UI.Matches(text, query)
    if not query or query == "" then return true end
    return UI.Normalize(text):find(UI.Normalize(query), 1, true) ~= nil
end

-- Short row of mutually exclusive buttons; returns the group with Select(value).
function UI.ButtonGroup(parent, width, height, options, onSelect, spacing)
    local group = CreateFrame("Frame", nil, parent)
    group:SetHeight(height)
    group.buttons = {}
    local x = 0
    for _, option in ipairs(options) do
        local button = UI.Button(group, width, height, option.label)
        button:SetPoint("LEFT", x, 0)
        button.value = option.value
        button:SetScript("OnClick", function() group:Select(option.value, true) end)
        group.buttons[#group.buttons + 1] = button
        x = x + width + (spacing or 4)
    end
    group:SetWidth(x - (spacing or 4))
    function group.Select(_, value, fromUser)
        group.value = value
        for _, button in ipairs(group.buttons) do button:SetActive(button.value == value) end
        if fromUser and onSelect then onSelect(value) end
    end
    return group
end
