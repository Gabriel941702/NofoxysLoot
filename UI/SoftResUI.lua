-- Nofoxy SoftResUI
-- Renders the Soft Reserves tab: paste box + import buttons + status +
-- a scrollable list of every item currently on reserve.

local pasteBoxRef   = nil  -- created once, reused every refresh so typed/pasted
                            -- text survives tab switches and doesn't get wiped
                            -- out on every button click that triggers a re-render.
local statusTextRef = nil

-- Reservation-list rows are pooled by itemID and reused across refreshes —
-- for a full raid's worth of reservations (150+ unique items) rebuilding
-- every frame/texture/fontstring from scratch on every tab switch or
-- re-import was the actual cause of the "import takes ages" slowdown, not
-- the CSV parsing itself. Each row is also lighter than before (a single
-- background tint instead of a 5-texture bordered panel) to cut the
-- per-item object count further.
local rowPool = {}  -- itemID -> { frame=, bg=, nameFS=, holderFS= }

local function AcquireRow(itemID, parent)
    local row = rowPool[itemID]
    if not row then
        local frame = CreateFrame("Frame", nil, parent)
        local bg = LRColorTex(frame, "BACKGROUND", 0.14, 0.14, 0.14, 0.45)
        bg:SetAllPoints(frame)

        local nameFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(true)
        nameFS:SetNonSpaceWrap(true)

        local holderFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        holderFS:SetJustifyH("LEFT")
        holderFS:SetWordWrap(true)
        holderFS:SetNonSpaceWrap(true)

        row = { frame = frame, bg = bg, nameFS = nameFS, holderFS = holderFS }
        rowPool[itemID] = row
    else
        row.frame:SetParent(parent)
    end
    row.frame:Show()
    return row
end

local function ReleaseUnusedRows(activeIDs)
    for itemID, row in pairs(rowPool) do
        if not activeIDs[itemID] then
            row.frame:Hide()
            row.frame:ClearAllPoints()
        end
    end
end

local function SetPooledLabel(fs, parent, text, r, g, b, xOffset, yOffset)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  xOffset,  yOffset)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -xOffset, yOffset)
    fs:SetWidth(parent:GetWidth() - xOffset * 2)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    return math.max(16, fs:GetHeight())
end

local function SetStatus(fs, text, r, g, b)
    if not fs then return end
    fs:SetText(text)
    fs:SetTextColor(r or 0.6, g or 0.6, b or 0.6)
end

function RefreshSoftResTab(content, frame)
    local yOffset = -LR_CONTENT_MARGIN

    local title, tH = LRMakeLabel(content, "Import Soft Reserves", 0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - tH - 2

    local intro, iH = LRMakeLabel(content,
        "Paste your softres.it CSV export (or a WeakAura reservation export) below, then click Import. " ..
        "This replaces any previously-imported list.",
        0.55, 0.55, 0.55, yOffset, nil, "GameFontHighlightSmall")
    yOffset = yOffset - iH - 6

    -- ---- Paste box (created once, reused on every subsequent refresh) ----
    local boxHeight = 120
    local boxWidth  = content:GetWidth() - LR_PANEL_PADDING * 2
    if not pasteBoxRef then
        pasteBoxRef = LRMakePasteBox(content, boxWidth, boxHeight, yOffset, "NofoxySRPasteBox")
    else
        pasteBoxRef:SetParent(content)
        pasteBoxRef:ClearAllPoints()
        pasteBoxRef:SetPoint("TOPLEFT", content, "TOPLEFT", LR_PANEL_PADDING, yOffset)
        pasteBoxRef:SetSize(boxWidth, boxHeight)
        pasteBoxRef.editBox:SetWidth(boxWidth - 12)
        pasteBoxRef:Show()
    end
    yOffset = yOffset - boxHeight - 8

    -- ---- Buttons row ----
    local row = LRHLayout(6)
    local btnY = yOffset

    local statusFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- (created after buttons below so layout math is simpler; declared here for closure capture)

    local importBtn = LRMakeButton(content, "Import", 90, 22,
        { 0.10, 0.30, 0.10 }, { 0.16, 0.42, 0.16 }, { 0.6, 1.0, 0.6 },
        function()
            local text = pasteBoxRef:GetText()
            local n, items, msg = NofoxySR:ImportAuto(text)
            SetStatus(statusTextRef, msg, n > 0 and 0.5 or 1.0, n > 0 and 1.0 or 0.4, n > 0 and 0.5 or 0.4)
            if n > 0 then pasteBoxRef:Clear() end
            NofoxyUI:Refresh()
        end)
    local csvBtn = LRMakeButton(content, "Force CSV", 90, 22,
        { 0.15, 0.15, 0.15 }, { 0.25, 0.25, 0.25 }, { 0.7, 0.7, 0.7 },
        function()
            local text = pasteBoxRef:GetText()
            local n, items, msg = NofoxySR:ImportCSV(text)
            SetStatus(statusTextRef, msg, n > 0 and 0.5 or 1.0, n > 0 and 1.0 or 0.4, n > 0 and 0.5 or 0.4)
            if n > 0 then pasteBoxRef:Clear() end
            NofoxyUI:Refresh()
        end)
    local waBtn = LRMakeButton(content, "Force WeakAura", 110, 22,
        { 0.15, 0.15, 0.15 }, { 0.25, 0.25, 0.25 }, { 0.7, 0.7, 0.7 },
        function()
            local text = pasteBoxRef:GetText()
            local n, items, msg = NofoxySR:ImportWeakAura(text)
            SetStatus(statusTextRef, msg, n > 0 and 0.5 or 1.0, n > 0 and 1.0 or 0.4, n > 0 and 0.5 or 0.4)
            if n > 0 then pasteBoxRef:Clear() end
            NofoxyUI:Refresh()
        end)
    local clearBtn = LRMakeButton(content, "Clear All", 80, 22,
        { 0.25, 0.12, 0.12 }, { 0.35, 0.18, 0.18 }, { 1.0, 0.6, 0.6 },
        function()
            NofoxySR:Clear()
            SetStatus(statusTextRef, "All soft reserves cleared.", 0.8, 0.5, 0.4)
            NofoxyUI:Refresh()
        end)

    row:Place(importBtn, content, LR_PANEL_PADDING, btnY)
    row:Place(csvBtn,    content, LR_PANEL_PADDING, btnY)
    row:Place(waBtn,     content, LR_PANEL_PADDING, btnY)
    row:Place(clearBtn,  content, LR_PANEL_PADDING, btnY)
    importBtn:Show(); csvBtn:Show(); waBtn:Show(); clearBtn:Show()

    yOffset = yOffset - 22 - 6

    -- ---- Status line ----
    statusFS:SetPoint("TOPLEFT",  content, "TOPLEFT",  LR_PANEL_PADDING,  yOffset)
    statusFS:SetPoint("TOPRIGHT", content, "TOPRIGHT", -LR_PANEL_PADDING, yOffset)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetWordWrap(true)
    if NofoxySR:HasAny() then
        statusFS:SetText(string.format("Loaded: %d reservation(s) across %d item(s).",
            NofoxySR.reserveCount, NofoxySR.itemCount))
        statusFS:SetTextColor(0.5, 0.8, 1.0)
    else
        statusFS:SetText("No soft reserves loaded yet.")
        statusFS:SetTextColor(0.5, 0.5, 0.5)
    end
    statusTextRef = statusFS
    yOffset = yOffset - math.max(16, statusFS:GetHeight()) - 8

    -- ---- Reservation list ----
    LRMakeSeparator(content, yOffset - 2, 4)
    yOffset = yOffset - 10

    local listTitle, ltH = LRMakeLabel(content,
        "Reserved Items (" .. NofoxySR.itemCount .. ")", 0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - ltH - 4

    local list = NofoxySR:GetSortedList()
    if #list == 0 then
        LRMakeEmptyState(content, "Nothing imported yet.", yOffset - 8)
        yOffset = yOffset - 32
        ReleaseUnusedRows({})
    else
        local activeIDs = {}
        for _, entry in ipairs(list) do
            activeIDs[entry.itemID] = true
            local row = AcquireRow(entry.itemID, content)
            local frame = row.frame

            frame:SetWidth(content:GetWidth())

            local nameH = SetPooledLabel(row.nameFS, frame,
                entry.itemName .. " |cff888888(" .. entry.itemID .. ")|r",
                1.0, 1.0, 1.0, LR_PANEL_PADDING - 2, -(LR_PANEL_PADDING - 2))

            local names = {}
            for _, h in ipairs(entry.holders) do
                table.insert(names, h.name .. (h.note and h.note ~= "" and (" [" .. h.note .. "]") or ""))
            end
            local holderText = table.concat(names, ", ")
            local holderH = SetPooledLabel(row.holderFS, frame, holderText,
                0.7, 0.7, 0.3, LR_PANEL_PADDING - 2, -(LR_PANEL_PADDING - 2 + nameH + 2))

            local panelH = (LR_PANEL_PADDING - 2) + nameH + 2 + holderH + (LR_PANEL_PADDING - 4)
            frame:SetHeight(panelH)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
            frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

            yOffset = yOffset - panelH - 3
        end
        ReleaseUnusedRows(activeIDs)
    end

    return yOffset
end
