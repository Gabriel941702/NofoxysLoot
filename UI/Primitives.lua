-- Nofoxy UI Primitives
-- Shared constants, widget factories, and the class icon system.
-- All UI sub-modules read from this file. No game state here.
-- Compatible with WoW 3.3.5 (no SetColorTexture, no BackdropTemplate).
--
-- Everything here is prefixed LR_ / LR* so this addon never collides with
-- Looty's own LOOTY_* globals if both are installed side by side.

-- ============================================================
-- ---- Layout constants ----
-- ============================================================

LR_TAB_BAR_HEIGHT  = 24
LR_DEFAULT_WIDTH   = 420
LR_DEFAULT_HEIGHT  = 320
LR_ICON_SIZE       = 36
LR_CONTENT_MARGIN  = 4
LR_PANEL_PADDING   = 8
LR_SCROLL_WIDTH    = 14
LR_MIN_WIDTH       = 300
LR_MIN_HEIGHT      = 280

LR_WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

LR_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },
    [1] = { r = 1.00, g = 1.00, b = 1.00 },
    [2] = { r = 0.12, g = 1.00, b = 0.00 },
    [3] = { r = 0.00, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 },
    [5] = { r = 1.00, g = 0.50, b = 0.00 },
}

-- ============================================================
-- ---- Class icon system ----
-- ============================================================

local CLASS_ICON_TEX = "Interface\\WorldStateFrame\\ICONS-CLASSES"
local CLASS_TCOORDS  = {
    WARRIOR     = { 0,      0.25,   0,      0.25   },
    MAGE        = { 0.25,   0.5,    0,      0.25   },
    ROGUE       = { 0.5,    0.7656, 0,      0.25   },
    DRUID       = { 0.7656, 1.0,    0,      0.25   },
    HUNTER      = { 0,      0.25,   0.25,   0.5    },
    SHAMAN      = { 0.25,   0.5,    0.25,   0.5    },
    PRIEST      = { 0.5,    0.7656, 0.25,   0.5    },
    WARLOCK     = { 0.7656, 1.0,    0.25,   0.5    },
    PALADIN     = { 0,      0.25,   0.5,    0.7656 },
    DEATHKNIGHT = { 0.25,   0.5,    0.5,    0.7656 },
}

local classCache = {}

function LRRefreshClassCache()
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, cls = GetRaidRosterInfo(i)
            if name and cls then classCache[name] = cls end
        end
    else
        local self = UnitName("player")
        if self then
            local _, cls = UnitClass("player")
            classCache[self] = cls
        end
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local n    = UnitName(unit)
            if n then
                local _, cls = UnitClass(unit)
                classCache[n] = cls
            end
        end
    end
end

function LRGetPlayerClass(playerName)
    if classCache[playerName] then return classCache[playerName] end

    local classFileName
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, cls = GetRaidRosterInfo(i)
            if name == playerName then classFileName = cls; break end
        end
    else
        if UnitName("player") == playerName then
            local _, cls = UnitClass("player")
            classFileName = cls
        else
            for i = 1, GetNumPartyMembers() do
                local unit = "party" .. i
                if UnitName(unit) == playerName then
                    local _, cls = UnitClass(unit)
                    classFileName = cls; break
                end
            end
        end
    end

    if classFileName then classCache[playerName] = classFileName end
    return classFileName
end

-- Looks up a class by name from the known cache OR a class string passed
-- directly (used for SR holders, who may not be in the raid at all).
function LRResolveClass(playerName, explicitClass)
    if explicitClass and explicitClass ~= "" and CLASS_TCOORDS[explicitClass:upper()] then
        return explicitClass:upper()
    end
    return LRGetPlayerClass(playerName)
end

function LRApplyClassIcon(tex, playerName, explicitClass)
    local cls    = LRResolveClass(playerName, explicitClass)
    local coords = cls and CLASS_TCOORDS[cls]
    if coords then
        tex:SetTexture(CLASS_ICON_TEX)
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    return false
end

-- ============================================================
-- ---- Layout cursors ----
-- ============================================================

function LRVLayout(parent, startY, gap, width)
    local c = {
        parent  = parent,
        y       = startY,
        gap     = gap or 0,
        width   = width or (parent and parent:GetWidth()) or 0,
        _start  = startY,
    }

    function c:Advance(h, customGap)
        if h == 0 then return self.y end
        local before = self.y
        self.y = self.y - h - (customGap ~= nil and customGap or self.gap)
        return before
    end

    function c:Consumed()
        return self._start - self.y
    end

    return c
end

function LRHLayout(gap)
    local c = { gap = gap or 4, _prev = nil, width = 0 }

    function c:Place(widget, parent, startX, atY)
        if not self._prev then
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", startX, atY)
        else
            widget:SetPoint("LEFT", self._prev, "RIGHT", self.gap, 0)
            self.width = self.width + self.gap
        end
        self.width = self.width + widget:GetWidth()
        self._prev = widget
    end

    function c:Reset()
        self._prev = nil
        self.width = 0
    end

    return c
end

-- ============================================================
-- ---- Widget factory functions ----
-- ============================================================

function LRColorTex(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(LR_WHITE_TEX)
    tex:SetVertexColor(r, g, b, a or 1)
    return tex
end

function LRMakePanel(parent, bgAlpha)
    local panel = CreateFrame("Frame", nil, parent)
    local bg = LRColorTex(panel, "BACKGROUND", 0.12, 0.12, 0.12, bgAlpha or 0.6)
    bg:SetAllPoints(panel)

    local function border(pt1, pt2, isH)
        local t = LRColorTex(panel, "BORDER", 0.20, 0.20, 0.20, 0.5)
        t:SetPoint(pt1, panel, pt1, 0, 0)
        t:SetPoint(pt2, panel, pt2, 0, 0)
        if isH then t:SetHeight(1) else t:SetWidth(1) end
    end
    border("TOPLEFT",    "TOPRIGHT",    true)
    border("BOTTOMLEFT", "BOTTOMRIGHT", true)
    border("TOPLEFT",    "BOTTOMLEFT",  false)
    border("TOPRIGHT",   "BOTTOMRIGHT", false)

    return panel
end

function LRMakeSeparator(parent, yOffset, margin)
    margin = margin or 4
    local sep = LRColorTex(parent, "BORDER", 0.25, 0.25, 0.25, 0.4)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  margin,  yOffset)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -margin, yOffset)
    sep:SetHeight(1)
    return 1
end

function LRMakeLabel(parent, text, r, g, b, yOffset, xOffset, font)
    xOffset = xOffset or LR_PANEL_PADDING
    font    = font or "GameFontNormalSmall"
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  xOffset,  yOffset)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -xOffset, yOffset)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(parent:GetWidth() - xOffset * 2)
    fs:SetWordWrap(true)
    fs:SetNonSpaceWrap(true)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    return fs, math.max(16, fs:GetHeight())
end

function LRMakeButton(parent, label, w, h, normalColor, hoverColor, textColor, onClick)
    h = h or 20
    local nc = normalColor
    local hc = hoverColor

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:EnableMouse(true)

    local bg = LRColorTex(btn, "BACKGROUND", nc[1], nc[2], nc[3], 0.8)
    bg:SetAllPoints(btn)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    txt:SetText(label)
    txt:SetTextColor(textColor[1], textColor[2], textColor[3])

    btn:SetScript("OnEnter", function() bg:SetVertexColor(hc[1], hc[2], hc[3], 0.8) end)
    btn:SetScript("OnLeave", function() bg:SetVertexColor(nc[1], nc[2], nc[3], 0.8) end)
    if onClick then btn:SetScript("OnClick", onClick) end

    return btn
end

function LRMakeDisabledButton(parent, label, w, h)
    h = h or 20
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:EnableMouse(false)

    local bg = LRColorTex(btn, "BACKGROUND", 0.15, 0.15, 0.15, 0.6)
    bg:SetAllPoints(btn)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    txt:SetText(label)
    txt:SetTextColor(0.4, 0.4, 0.4)

    return btn
end

function LRMakeToggleButton(parent, checked, checkedLabel, uncheckedLabel, onClick, layoutY)
    local label = checked and checkedLabel or uncheckedLabel
    local nc = checked and { 0.05, 0.20, 0.35 } or { 0.15, 0.15, 0.15 }
    local hc = checked and { 0.10, 0.35, 0.55 } or { 0.25, 0.25, 0.25 }
    local tc = checked and { 0.4, 0.75, 1.0 }  or { 0.7, 0.7, 0.7  }

    local togW = parent:GetWidth() - LR_PANEL_PADDING * 2
    local togH = 24
    local btn = LRMakeButton(parent, label, togW, togH, nc, hc, tc,
        function() onClick(not checked) end)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", LR_PANEL_PADDING, layoutY)
    btn:Show()
    return btn, togH
end

function LRMakeTab(parent, label, w, tabID, anchorRel, anchorPt, anchorOffset, onClick, getCurrentTab)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, LR_TAB_BAR_HEIGHT - 2)
    btn:SetPoint("LEFT", anchorRel, anchorPt, anchorOffset, 0)
    btn:EnableMouse(true)
    btn._tabID = tabID
    btn:SetScript("OnClick", onClick)

    local indicator = LRColorTex(btn, "BORDER", 0.12, 0.12, 0.12, 0.0)
    indicator:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
    indicator:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    indicator:SetHeight(2)
    btn.indicator = indicator

    local hover = LRColorTex(btn, "HIGHLIGHT", 0.25, 0.25, 0.25, 0.3)
    hover:SetAllPoints(btn)
    hover:Hide()
    btn.hoverBg = hover
    btn:SetScript("OnEnter", function()
        local ct = getCurrentTab and getCurrentTab() or ""
        if ct ~= tabID then btn.hoverBg:Show() end
    end)
    btn:SetScript("OnLeave", function() btn.hoverBg:Hide() end)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    txt:SetText(label)
    btn.text = txt

    return btn
end

function LRMakeTimerBar(panel, layout, duration, startTime, prefix, itemKey)
    if not duration or not startTime then return end
    local barH = 5

    local bg = LRColorTex(panel, "BACKGROUND", 0.1, 0.1, 0.1, 0.8)
    bg:SetHeight(barH)
    bg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  LR_PANEL_PADDING,  layout.y)
    bg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LR_PANEL_PADDING, layout.y)

    local remaining = duration - (GetTime() - startTime)
    remaining = math.max(0, remaining)
    local pct  = remaining / duration
    local barW = (panel:GetWidth() or 300) - LR_PANEL_PADDING * 2

    local bar = LRColorTex(panel, "ARTWORK", 0.4, 0.4, 0.4, 0.8)
    bar:SetHeight(barH)
    bar:SetWidth(barW * pct)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", LR_PANEL_PADDING, layout.y)

    local txt = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LR_PANEL_PADDING, layout.y - 2)
    txt:SetJustifyH("RIGHT")
    txt:SetText(string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))

    panel[prefix .. "TimerBg"]   = bg
    panel[prefix .. "TimerBar"]  = bar
    panel[prefix .. "TimerText"] = txt
    panel[prefix .. "RollStart"] = startTime
    panel[prefix .. "Duration"]  = duration
    if itemKey then
        panel[prefix .. "ItemKey"] = itemKey
    end

    layout:Advance(barH + 4)
end

function LRMakePlayerRow(parent, entry, isWin, rowIcon, secColor, alpha, layout)
    local rowH = 16
    local y    = layout.y

    if isWin then
        local winBg = LRColorTex(parent, "BACKGROUND", 0.12, 0.60, 0.12, 0.25 * alpha)
        winBg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
        winBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        winBg:SetHeight(rowH)
    end

    local cIcon = parent:CreateTexture(nil, "ARTWORK")
    cIcon:SetSize(14, 14)
    cIcon:SetPoint("TOPLEFT", parent, "TOPLEFT", LR_PANEL_PADDING, y)
    LRApplyClassIcon(cIcon, entry.name)

    local rIcon = parent:CreateTexture(nil, "ARTWORK")
    rIcon:SetSize(14, 14)
    rIcon:SetPoint("LEFT", cIcon, "RIGHT", 2, 0)
    rIcon:SetTexture(rowIcon or "Interface\\Buttons\\UI-GroupLoot-Dice-Up")

    local pName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pName:SetPoint("LEFT", rIcon, "RIGHT", 3, 0)
    pName:SetPoint("RIGHT", parent, "RIGHT", -LR_PANEL_PADDING, 0)
    pName:SetJustifyH("LEFT")
    pName:SetText(entry.name .. " (" .. tostring(entry.value or "?") .. ")")
    if isWin then
        pName:SetTextColor(0.2 * alpha, 1.0 * alpha, 0.2 * alpha)
    else
        pName:SetTextColor(secColor[1] * alpha, secColor[2] * alpha, secColor[3] * alpha)
    end

    layout:Advance(rowH + 1)
end

function LRMakeEmptyState(parent, text, yOffset)
    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT",  parent, "TOPLEFT",  LR_PANEL_PADDING,  yOffset)
    empty:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -LR_PANEL_PADDING, yOffset)
    empty:SetJustifyH("CENTER")
    empty:SetWordWrap(true)
    empty:SetText(text)
    empty:SetTextColor(0.35, 0.35, 0.35)
    return 24
end

-- ============================================================
-- ---- Custom dropdown (roster picker for manual Award) ----
-- ============================================================

local DROPDOWN_ROW_H   = 18
local DROPDOWN_MAX_VIS = 12
local DROPDOWN_WIDTH   = 160
local DROPDOWN_PAD     = 6

local _activeDropdown = nil

local function CloseActiveDropdown()
    if _activeDropdown and _activeDropdown:IsShown() then
        _activeDropdown:Hide()
    end
    _activeDropdown = nil
end

local _clickCatcher
local function EnsureClickCatcher()
    if _clickCatcher then return end
    _clickCatcher = CreateFrame("Frame", "LRDropdownClickCatcher", UIParent)
    _clickCatcher:SetAllPoints(UIParent)
    _clickCatcher:SetFrameLevel(99)
    _clickCatcher:EnableMouse(true)
    _clickCatcher:Hide()
    _clickCatcher:SetScript("OnMouseDown", function()
        CloseActiveDropdown()
        _clickCatcher:Hide()
    end)
end

function LRMakeDropdown(anchor, entries, onSelect)
    EnsureClickCatcher()

    local rowCount = math.min(#entries, DROPDOWN_MAX_VIS)
    local totalH   = rowCount * DROPDOWN_ROW_H + DROPDOWN_PAD * 2

    local dd = CreateFrame("Frame", nil, UIParent)
    dd:SetSize(DROPDOWN_WIDTH, totalH)
    dd:SetFrameLevel(101)
    dd:Hide()

    local bg = LRColorTex(dd, "BACKGROUND", 0.08, 0.08, 0.08, 0.97)
    bg:SetAllPoints(dd)

    local function border(pt1, pt2, isH)
        local t = LRColorTex(dd, "BORDER", 0.30, 0.30, 0.30, 0.7)
        t:SetPoint(pt1, dd, pt1, 0, 0)
        t:SetPoint(pt2, dd, pt2, 0, 0)
        if isH then t:SetHeight(1) else t:SetWidth(1) end
    end
    border("TOPLEFT",    "TOPRIGHT",    true)
    border("BOTTOMLEFT", "BOTTOMRIGHT", true)
    border("TOPLEFT",    "BOTTOMLEFT",  false)
    border("TOPRIGHT",   "BOTTOMRIGHT", false)

    dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)

    for i, entry in ipairs(entries) do
        if i > DROPDOWN_MAX_VIS then break end
        local yOff = -DROPDOWN_PAD - (i - 1) * DROPDOWN_ROW_H

        local row = CreateFrame("Button", nil, dd)
        row:SetSize(DROPDOWN_WIDTH - 2, DROPDOWN_ROW_H)
        row:SetPoint("TOPLEFT", dd, "TOPLEFT", 1, yOff)
        row:EnableMouse(true)

        local hoverBg = LRColorTex(row, "HIGHLIGHT", 0.25, 0.25, 0.40, 0.5)
        hoverBg:SetAllPoints(row)
        hoverBg:Hide()

        local cIcon = row:CreateTexture(nil, "ARTWORK")
        cIcon:SetSize(14, 14)
        cIcon:SetPoint("LEFT", row, "LEFT", DROPDOWN_PAD, 0)
        if entry.class then
            LRApplyClassIcon(cIcon, entry.name, entry.class)
        else
            cIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  cIcon, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", row,   "RIGHT", -DROPDOWN_PAD, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(entry.name)
        lbl:SetTextColor(0.90, 0.90, 0.90)

        row:SetScript("OnEnter", function()
            hoverBg:Show()
            lbl:SetTextColor(1, 1, 1)
        end)
        row:SetScript("OnLeave", function()
            hoverBg:Hide()
            lbl:SetTextColor(0.90, 0.90, 0.90)
        end)
        row:SetScript("OnClick", function()
            CloseActiveDropdown()
            _clickCatcher:Hide()
            onSelect(entry.name)
        end)
    end

    function dd:Open()
        CloseActiveDropdown()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        local absBottom = self:GetBottom()
        if absBottom and absBottom < 0 then
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
        end
        _activeDropdown = self
        _clickCatcher:SetFrameLevel(self:GetFrameLevel() - 1)
        _clickCatcher:Show()
        self:Show()
    end

    function dd:Close()
        CloseActiveDropdown()
        _clickCatcher:Hide()
    end

    return dd
end

function LRToggleDropdown(anchor, entries, onSelect)
    if _activeDropdown and _activeDropdown:IsShown() then
        CloseActiveDropdown()
        _clickCatcher:Hide()
        return
    end
    local dd = LRMakeDropdown(anchor, entries, onSelect)
    dd:Open()
    return dd
end

-- ============================================================
-- ---- Item header: icon + quality border + name + tooltip ----
-- ============================================================

function LRMakeItemHeader(parent, item, iconH, alpha)
    alpha    = alpha or 1.0
    local qc = LR_QUALITY_COLORS[item.quality] or LR_QUALITY_COLORS[2]
    local pp = LR_PANEL_PADDING

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconH, iconH)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", pp, -pp)
    icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetAlpha(alpha)

    local border = LRColorTex(parent, "BORDER", qc.r, qc.g, qc.b, 0.5 * alpha)
    border:SetSize(iconH + 2, iconH + 2)
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)

    local displayName = item.link or item.name or "Unknown"
    if item.quantity and item.quantity > 1 then
        displayName = displayName .. " (x" .. item.quantity .. ")"
    end

    local nameFont = (iconH <= 28) and "GameFontNormalSmall" or "GameFontNormal"
    local name = parent:CreateFontString(nil, "OVERLAY", nameFont)
    name:SetPoint("LEFT",  icon,   "RIGHT", 8,   0)
    name:SetPoint("RIGHT", parent, "RIGHT", -pp, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(true)
    name:SetText(displayName)
    name:SetTextColor(qc.r * alpha, qc.g * alpha, qc.b * alpha)

    if item.link then
        parent:EnableMouse(true)
        parent:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end)
        parent:SetScript("OnLeave", function() GameTooltip:Hide() end)
        parent:SetScript("OnMouseUp", function(_, button)
            SetItemRef(item.link, item.link, button)
        end)
    end

    return -(pp + iconH + 6)
end

-- ============================================================
-- ---- Multi-line paste box (for Soft Reserve CSV import) ----
-- ============================================================
-- Deliberately does NOT use Blizzard's UIPanelScrollFrameTemplate — that
-- template builds child widget names from the frame's own name via XML
-- $parent substitution, which is finicky to get right blind. Instead this
-- hand-rolls a bare ScrollFrame + EditBox with mouse-wheel scrolling,
-- mirroring the same scroll approach already used for the main window.
--
-- Returns: holder frame (has :GetText/:SetText/:Clear), consumedHeight
function LRMakePasteBox(parent, width, height, yOffset, name)
    name = name or "LRPasteBox" .. (LR_PasteBoxCounter or 0)
    LR_PasteBoxCounter = (LR_PasteBoxCounter or 0) + 1

    local holder = CreateFrame("Frame", name .. "Holder", parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", LR_PANEL_PADDING, yOffset)
    holder:SetSize(width, height)

    local bg = LRColorTex(holder, "BACKGROUND", 0.05, 0.05, 0.05, 0.9)
    bg:SetAllPoints(holder)
    local function border(pt1, pt2, isH)
        local t = LRColorTex(holder, "BORDER", 0.25, 0.25, 0.25, 0.6)
        t:SetPoint(pt1, holder, pt1, 0, 0)
        t:SetPoint(pt2, holder, pt2, 0, 0)
        if isH then t:SetHeight(1) else t:SetWidth(1) end
    end
    border("TOPLEFT",    "TOPRIGHT",    true)
    border("BOTTOMLEFT", "BOTTOMRIGHT", true)
    border("TOPLEFT",    "BOTTOMLEFT",  false)
    border("TOPRIGHT",   "BOTTOMRIGHT", false)

    -- Plain ScrollFrame, no template — nothing here depends on frame names.
    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", holder)
    scroll:SetPoint("TOPLEFT",     holder, "TOPLEFT",     4, -4)
    scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 4)
    scroll:EnableMouseWheel(true)

    local editBox = CreateFrame("EditBox", name .. "EditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(width - 12)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(2, 2, 2, 2)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur      = self:GetVerticalScroll()
        local maxScrl  = math.max(0, (editBox:GetHeight() or 0) - self:GetHeight())
        local newScrl  = math.max(0, math.min(maxScrl, cur - delta * 20))
        self:SetVerticalScroll(newScrl)
    end)

    -- Clicking anywhere in the box focuses the edit box, since the visible
    -- area is the ScrollFrame, not the EditBox itself.
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    holder.editBox = editBox
    holder.scroll  = scroll

    function holder:GetText() return editBox:GetText() or "" end
    function holder:SetText(t) editBox:SetText(t or "") end
    function holder:Clear() editBox:SetText(""); scroll:SetVerticalScroll(0) end

    return holder, height
end
