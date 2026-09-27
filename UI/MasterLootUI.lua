-- Nofoxy MasterLootUI
-- Renders the Master Loot tab: BuildMasterItemPanel and RefreshMasterLootTab.
-- Reads from NofoxyML (domain) and NofoxyItem objects.

local panelPool = {}  -- { [itemKey] = panelFrame }

local function ResetPanel(panel)
    for _, child in ipairs({ panel:GetChildren() }) do
        child:Hide(); child:ClearAllPoints()
    end
    for _, region in ipairs({ panel:GetRegions() }) do
        region:Hide()
    end
    panel._mlTimerBg   = nil
    panel._mlTimerBar  = nil
    panel._mlTimerText = nil
    panel._mlRollStart = nil
    panel._mlDuration  = nil
    panel._mlItemKey   = nil
end

local function AcquirePanel(itemKey, content)
    local panel = panelPool[itemKey]
    if panel then
        ResetPanel(panel)
        panel:SetParent(content)
    else
        panel = CreateFrame("Frame", nil, content)
        panelPool[itemKey] = panel
    end
    panel:Show()
    return panel
end

local function ReleaseUnused(activeKeys)
    for itemKey, panel in pairs(panelPool) do
        if not activeKeys[itemKey] then
            panel:Hide()
            panel:ClearAllPoints()
            panel:SetParent(nil)
        end
    end
end

-- ============================================================
-- ---- Action state per item ----
-- ============================================================

local function GetItemAction(item, isML)
    if item:IsDone() then return nil end
    if isML then
        if item:IsRolling() then return "ml_rolling" end
        if item:IsTied()    then return "ml_tie" end
        if item.winner      then return "ml_winner" end
        if item.wasRolled   then return "ml_idle_reroll" end
        if item.srHolders and #item.srHolders > 0 then return "ml_sr_idle" end
        return "ml_idle"
    else
        local myName = UnitName("player")
        if item:IsRolling() and item.eligiblePlayers then
            if not item.eligiblePlayers[myName] then
                return "raider_not_eligible"
            end
            return item:HasRolled(myName) and "raider_rerolled" or "raider_reroll"
        end
        if item:IsRolling() then
            return item:HasRolled(myName) and "raider_rolled" or "raider_roll"
        end
        if item.wasRolled and not item.winner and not item:IsDone() then
            return "raider_tie_pending"
        end
        return nil
    end
end

-- ============================================================
-- ---- Sub-renderers ----
-- ============================================================

local BTN_GREEN  = { { 0.15, 0.35, 0.15 }, { 0.25, 0.45, 0.25 }, { 0.5, 1.0, 0.5 } }
local BTN_RED    = { { 0.25, 0.15, 0.15 }, { 0.35, 0.25, 0.25 }, { 1.0, 0.5, 0.5 } }
local BTN_ORANGE = { { 0.35, 0.20, 0.05 }, { 0.50, 0.30, 0.10 }, { 1.0, 0.75, 0.3 } }
local BTN_GOLD   = { { 0.35, 0.28, 0.05 }, { 0.50, 0.40, 0.10 }, { 1.0, 0.85, 0.3 } }

-- SR badge: shown above the status line whenever the item carries reservations.
local function RenderSRBadge(panel, layout, item, alpha)
    if not item.srHolders or #item.srHolders == 0 then return end
    local text = "Soft-Reserved: " .. table.concat(item.srHolders, ", ")
    local fs, h = LRMakeLabel(panel, text, 1.0 * alpha, 0.82 * alpha, 0.0, layout.y, nil, "GameFontNormalSmall")
    layout:Advance(h, 2)
end

local function RenderStatusLine(panel, layout, item, alpha)
    local rollCount   = item:RollCount()
    local rerollCount = item:RerollCount()
    local isML        = NofoxyML:IsML()
    local statusColor, statusText

    if item:IsRolling() then
        if item.eligiblePlayers and next(item.eligiblePlayers) then
            local names = {}
            for name in pairs(item.eligiblePlayers) do table.insert(names, name) end
            statusColor = { 1.0, 0.65, 0.2 }
            statusText  = (item.autoAward and "Rolling (auto-award): " or "Re-rolling: ") .. table.concat(names, " & ")
        else
            statusColor = { 1.0, 0.85, 0.2 }
            statusText  = "Rolling... (" .. rollCount .. " rolls)"
        end
    elseif not isML and item.wasRolled and not item.winner and not item:IsDone() then
        statusColor = { 1.0, 0.5, 0.2 }
        statusText  = "Tie! Waiting for re-roll..."
    elseif item:IsTied() then
        local tied = item:GetTiedWinners()
        statusColor = { 1.0, 0.5, 0.2 }
        statusText  = "Tie: " .. table.concat(tied.names, " & ") .. " (" .. tied.value .. " each)"
    elseif item.winner then
        statusColor = { 0.3, 1.0, 0.3 }
        statusText  = "Winner: " .. item.winner
    elseif rollCount > 0 then
        statusColor = { 0.8, 0.8, 0.8 }
        statusText  = "Rolls: " .. rollCount
    elseif item.srHolders and #item.srHolders > 0 then
        statusColor = { 1.0, 0.75, 0.2 }
        statusText  = "Reserved — not yet resolved"
    else
        statusColor = { 0.4, 0.4, 0.4 }
        statusText  = "No rolls"
    end

    if rerollCount > 0 then
        statusText = statusText .. " | " .. rerollCount .. " re-roll(s)"
    end

    local fs, fsH = LRMakeLabel(panel, statusText,
        statusColor[1] * alpha, statusColor[2] * alpha, statusColor[3] * alpha, layout.y)
    layout:Advance(fsH)
end

local function RenderTimerBar(panel, layout, item)
    if not item:IsRolling() or not item.rollStart then return end
    LRMakeTimerBar(panel, layout, NofoxyML.rollDuration, item.rollStart, "_ml", item.itemKey)
end

local function RenderAwardRow(panel, layout, item, awardLabel, winnerName)
    local BTN_H   = 20
    local TOP_GAP = 4
    local pp      = LR_PANEL_PADDING
    local atY     = layout.y - TOP_GAP
    local panelW  = panel:GetWidth()
    local arrowW  = 24
    local mainW   = panelW - pp * 2 - arrowW - 2

    local hasWinner = winnerName ~= nil
    local NC = hasWinner and { 0.08, 0.20, 0.38 } or { 0.18, 0.18, 0.18 }
    local HC = hasWinner and { 0.14, 0.32, 0.55 } or { 0.26, 0.26, 0.26 }
    local TC = hasWinner and { 0.50, 0.80, 1.00 } or { 0.65, 0.65, 0.65 }

    local mainBtn = LRMakeButton(panel, awardLabel, mainW, BTN_H, NC, HC, TC,
        function()
            if not winnerName then
                Nofoxy:Print("|cffff6040[Award]|r Pick a name from the " ..
                    "dropdown (the \"v\" button) first — nobody's selected yet.")
                return
            end
            local err = NofoxyML:AwardToWinner(item.itemKey, winnerName)
            if err then
                local msgs = {
                    ERR_NOT_ML         = "You are not the Master Looter.",
                    ERR_NO_ITEM        = "Item not found in session.",
                    ERR_NOT_CANDIDATE  = "Player is not a loot candidate.",
                    ERR_ITEM_NOT_FOUND = "Item not found in loot window or bags.",
                    ERR_NOT_IN_GROUP   = (winnerName or "?") .. " is not in your group.",
                    ERR_OUT_OF_RANGE   = "Move closer to " .. (winnerName or "?") .. ".",
                }
                Nofoxy:Print("|cffff6040[Award]|r " .. (msgs[err] or err))
            end
        end)
    mainBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", pp, atY)
    mainBtn:Show()

    local arrowBtn = LRMakeButton(panel, "v", arrowW, BTN_H,
        { 0.10, 0.10, 0.10 }, { 0.22, 0.22, 0.22 }, { 0.70, 0.70, 0.70 }, nil)
    arrowBtn:SetPoint("LEFT", mainBtn, "RIGHT", 2, 0)
    arrowBtn:Show()

    arrowBtn:SetScript("OnClick", function()
        local entries = NofoxyML:GetRaidRoster()
        LRToggleDropdown(arrowBtn, entries, function(selectedName)
            NofoxyML.pendingAward = NofoxyML.pendingAward or {}
            NofoxyML.pendingAward[item.itemKey] = selectedName
            if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
        end)
    end)

    layout:Advance(TOP_GAP + BTN_H + 4)
    return mainBtn
end

local function RenderActionButtons(panel, layout, item, action)
    if not action then return end

    local BTN_H   = 20
    local TOP_GAP = 4
    local BOT_GAP = 4
    local row     = LRHLayout(4)
    local atY     = layout.y - TOP_GAP
    local selfManaged = false

    if action == "ml_idle" then
        local startBtn = LRMakeButton(panel, "Start Roll", 70, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() NofoxyML:StartRoll(item.itemKey) end)
        local doneBtn = LRMakeButton(panel, "Done", 55, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() NofoxyML:ToggleDone(item.itemKey) end)
        row:Place(startBtn, panel, LR_PANEL_PADDING, atY)
        row:Place(doneBtn,  panel, LR_PANEL_PADDING, atY)
        startBtn:Show(); doneBtn:Show()

    elseif action == "ml_sr_idle" then
        -- Reserved item, sitting idle until you decide to act on it — this
        -- is the normal resting state for these now, not a fallback. One
        -- reserver: "Award" announces + awards in one click. Two or more:
        -- "Roll" announces + starts a roll restricted to just the reservers.
        local isSingular = (#item.srHolders == 1)
        local label = isSingular and "Award" or "Roll"
        local actionBtn = LRMakeButton(panel, label, 70, BTN_H,
            BTN_GOLD[1], BTN_GOLD[2], BTN_GOLD[3],
            function() NofoxyML:AnnounceSR(item.itemKey) end)
        local doneBtn = LRMakeButton(panel, "Done", 55, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() NofoxyML:ToggleDone(item.itemKey) end)
        row:Place(actionBtn, panel, LR_PANEL_PADDING, atY)
        row:Place(doneBtn,   panel, LR_PANEL_PADDING, atY)
        actionBtn:Show(); doneBtn:Show()

    elseif action == "ml_idle_reroll" then
        selfManaged = true
        local pending = NofoxyML.pendingAward and NofoxyML.pendingAward[item.itemKey]
        local awardLabel = pending and ("Award: " .. pending) or "Award to..."
        RenderAwardRow(panel, layout, item, awardLabel, pending)

        atY = layout.y - TOP_GAP
        row = LRHLayout(4)
        local rerollBtn = LRMakeButton(panel, "Re-Roll", 65, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() NofoxyML:StartRoll(item.itemKey) end)
        local doneBtn = LRMakeButton(panel, "Done", 55, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() NofoxyML:ToggleDone(item.itemKey) end)
        row:Place(rerollBtn, panel, LR_PANEL_PADDING, atY)
        row:Place(doneBtn,   panel, LR_PANEL_PADDING, atY)
        rerollBtn:Show(); doneBtn:Show()
        layout:Advance(TOP_GAP + BTN_H + BOT_GAP)

    elseif action == "ml_winner" then
        selfManaged = true
        local pending = NofoxyML.pendingAward and NofoxyML.pendingAward[item.itemKey]
        local target  = pending or item.winner
        local awardLabel = "Award: " .. (target or "?")
        RenderAwardRow(panel, layout, item, awardLabel, target)

        atY = layout.y - TOP_GAP
        row = LRHLayout(4)
        local rerollBtn = LRMakeButton(panel, "Re-Roll", 65, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() NofoxyML:StartRoll(item.itemKey) end)
        local doneBtn = LRMakeButton(panel, "Done", 55, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() NofoxyML:ToggleDone(item.itemKey) end)
        row:Place(rerollBtn, panel, LR_PANEL_PADDING, atY)
        row:Place(doneBtn,   panel, LR_PANEL_PADDING, atY)
        rerollBtn:Show(); doneBtn:Show()
        layout:Advance(TOP_GAP + BTN_H + BOT_GAP)

    elseif action == "ml_tie" then
        local rerollBtn = LRMakeButton(panel, "Re-roll", 65, BTN_H,
            BTN_ORANGE[1], BTN_ORANGE[2], BTN_ORANGE[3],
            function() NofoxyML:StartReRoll(item.itemKey) end)
        local endBtn  = LRMakeButton(panel, "End", 50, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() NofoxyML:EndRoll(item.itemKey) end)
        row:Place(rerollBtn, panel, LR_PANEL_PADDING, atY)
        row:Place(endBtn,   panel, LR_PANEL_PADDING, atY)
        rerollBtn:Show(); endBtn:Show()

    elseif action == "ml_rolling" then
        local endBtn  = LRMakeButton(panel, "End Roll", 65, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() NofoxyML:EndRoll(item.itemKey) end)
        local rollBtn = LRMakeButton(panel, "Roll!", 55, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() RandomRoll(1, 100) end)
        row:Place(endBtn,  panel, LR_PANEL_PADDING, atY)
        row:Place(rollBtn, panel, LR_PANEL_PADDING, atY)
        endBtn:Show(); rollBtn:Show()

    elseif action == "raider_roll" then
        local rollBtn = LRMakeButton(panel, "Roll!", 55, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() RandomRoll(1, 100) end)
        row:Place(rollBtn, panel, LR_PANEL_PADDING, atY)
        rollBtn:Show()

    elseif action == "raider_rolled" then
        local greyBtn = LRMakeDisabledButton(panel, "Rolled", 55, BTN_H)
        row:Place(greyBtn, panel, LR_PANEL_PADDING, atY)
        greyBtn:Show()

    elseif action == "raider_reroll" then
        local rerollBtn = LRMakeButton(panel, "Re-roll!", 65, BTN_H,
            BTN_ORANGE[1], BTN_ORANGE[2], BTN_ORANGE[3],
            function() RandomRoll(1, 100) end)
        row:Place(rerollBtn, panel, LR_PANEL_PADDING, atY)
        rerollBtn:Show()

    elseif action == "raider_rerolled" then
        local greyBtn = LRMakeDisabledButton(panel, "Re-rolled", 65, BTN_H)
        row:Place(greyBtn, panel, LR_PANEL_PADDING, atY)
        greyBtn:Show()

    elseif action == "raider_not_eligible" then
        local greyBtn = LRMakeDisabledButton(panel, "Not reserved", 90, BTN_H)
        row:Place(greyBtn, panel, LR_PANEL_PADDING, atY)
        greyBtn:Show()

    elseif action == "raider_tie_pending" then
        -- no button — status line already explains the state
    end

    if not selfManaged then
        layout:Advance(TOP_GAP + BTN_H + BOT_GAP)
    end
end

local function RenderRollList(panel, layout, item, alpha)
    local rollCount = item:RollCount()
    if rollCount == 0 then return end

    local sortedRolls = item:GetSortedRolls()
    local maxRows = item:IsRolling() and math.min(3, #sortedRolls) or #sortedRolls

    for i = 1, maxRows do
        local entry = sortedRolls[i]
        local isWin = (entry.name == item.winner)
        LRMakePlayerRow(panel, entry, isWin, nil, { 1.0, 0.85, 0.2 }, alpha, layout)
    end
end

local function RenderRerollWarning(panel, layout, item, alpha)
    if item:RerollCount() == 0 then return end
    local names = {}
    for playerName, info in pairs(item.rerolls) do
        table.insert(names, playerName .. " (" .. (info.value or "?") .. ")")
    end
    local warnTxt, warnH = LRMakeLabel(panel, "Re-rolls: " .. table.concat(names, ", "),
        1.0 * alpha, 0.4 * alpha, 0.2 * alpha, layout.y, nil, "GameFontHighlightSmall")
    layout:Advance(warnH)
end

-- ============================================================
-- ---- BuildMasterItemPanel ----
-- ============================================================

function BuildMasterItemPanel(panel, item, itemKey, yOffset, opts)
    opts = opts or {}
    local isDone = opts.isDone or item:IsDone()
    local isML   = opts.isML   or NofoxyML:IsML()
    local alpha  = isDone and 0.5 or 1.0
    local iconH  = LR_ICON_SIZE - 4

    panel:SetWidth(panel:GetParent():GetWidth())

    LRColorTex(panel, "BACKGROUND", 0.12, 0.12, 0.12, isDone and 0.2 or 0.6):SetAllPoints(panel)
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

    -- Gold accent border when soft-reserved, so it stands out from normal drops
    if item.srHolders and not isDone then
        local accent = LRColorTex(panel, "BORDER", 1.0, 0.82, 0.0, 0.5)
        accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        accent:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
        accent:SetWidth(2)
    end

    local layout = LRVLayout(panel, LRMakeItemHeader(panel, item, iconH, alpha), 0)

    RenderSRBadge(panel, layout, item, alpha)
    RenderStatusLine(panel, layout, item, alpha)
    RenderTimerBar(panel, layout, item)
    RenderActionButtons(panel, layout, item, GetItemAction(item, isML))
    RenderRollList(panel, layout, item, alpha)
    RenderRerollWarning(panel, layout, item, alpha)

    local totalH = -layout.y + LR_PANEL_PADDING
    panel:SetHeight(totalH)
    panel:SetPoint("TOPLEFT",  panel:GetParent(), "TOPLEFT",  0, yOffset)
    panel:SetPoint("TOPRIGHT", panel:GetParent(), "TOPRIGHT", 0, yOffset)

    return panel, totalH
end

-- ============================================================
-- ---- RefreshMasterLootTab ----
-- ============================================================

function RefreshMasterLootTab(content, frame)
    local session = NofoxyML:GetSession()
    local isML    = NofoxyML:IsML()
    local role    = NofoxyML:GetRole()
    local yOffset = -LR_CONTENT_MARGIN

    if session then
        local _, mH = LRMakeLabel(content, "Loot Method: Master", 0.7, 0.7, 0.7, yOffset)
        yOffset = yOffset - mH

        if role == "MasterLooter" then
            local _, rH = LRMakeLabel(content, "Role: MasterLooter", 1.0, 0.82, 0.0, yOffset)
            yOffset = yOffset - rH - 2
        elseif role == "Raider" then
            local _, rH = LRMakeLabel(content, "Role: Raider", 0.4, 0.7, 1.0, yOffset)
            yOffset = yOffset - rH - 2
        end
    end

    local activeKeys = {}

    local mlCount = 0
    if session then
        local activeItems = session:GetActiveItems(NofoxyML:GetFilterThreshold())
        mlCount = #activeItems
        for _, item in ipairs(activeItems) do
            activeKeys[item.itemKey] = true
            local panel = AcquirePanel(item.itemKey, content)
            local _, h = BuildMasterItemPanel(panel, item, item.itemKey, yOffset, { isML = isML })
            yOffset = yOffset - h - 4
        end
    end

    if session then
        local doneItems = session:GetDoneItems()
        if #doneItems > 0 then
            local sepY = yOffset - 10
            LRMakeSeparator(content, sepY, 4)
            yOffset = sepY - 1 - 22

            local clearBtn = LRMakeButton(content, "Clear Done", 80, 20,
                { 0.15, 0.15, 0.15 }, { 0.25, 0.25, 0.25 }, { 0.6, 0.6, 0.6 },
                function() NofoxyML:ClearDone() end)
            clearBtn:SetPoint("TOP", content, "TOP", 0, yOffset)
            clearBtn:Show()
            yOffset = yOffset - 24

            local lbl, lblH = LRMakeLabel(content, "Done (" .. #doneItems .. ")", 0.4, 0.4, 0.4, yOffset)
            yOffset = yOffset - lblH

            for _, item in ipairs(doneItems) do
                activeKeys[item.itemKey] = true
                local panel = AcquirePanel(item.itemKey, content)
                local _, h = BuildMasterItemPanel(panel, item, item.itemKey, yOffset,
                    { isDone = true, isML = isML })
                yOffset = yOffset - h - 4
            end
        end
    end

    local doneCount = session and #session:GetDoneItems() or 0
    if mlCount == 0 and doneCount == 0 then
        local emptyY = yOffset - 16
        local text
        if session then
            text = role == "Raider"
                and "Waiting for the Master Looter to open a corpse..."
                or  "No items looted yet — open a corpse with loot"
        else
            text = "Not in Master Loot mode.\nSet loot method to Master Loot to begin."
        end
        LRMakeEmptyState(content, text, emptyY)
        yOffset = emptyY - 24
    end

    if frame and frame.tabs and frame.tabs.master then
        frame.tabs.master.text:SetText("Master: " .. mlCount)
    end

    ReleaseUnused(activeKeys)
    return yOffset
end

-- ============================================================
-- ---- Timer update ----
-- ============================================================

function UpdateMasterLootTimers()
    for _, panel in pairs(panelPool) do
        if panel:IsShown() and panel._mlItemKey and panel._mlTimerBar and panel._mlRollStart then
            local elapsed   = GetTime() - panel._mlRollStart
            local duration  = panel._mlDuration or NofoxyML.rollDuration
            local remaining = math.max(0, duration - elapsed)
            local pct       = remaining / duration
            local barW      = panel:GetWidth() - LR_PANEL_PADDING * 2

            panel._mlTimerBar:SetWidth(barW * pct)

            if pct < 0.25 then
                panel._mlTimerBar:SetVertexColor(0.9, 0.2, 0.15, 0.8)
            elseif pct < 0.5 then
                panel._mlTimerBar:SetVertexColor(0.9, 0.7, 0.1, 0.8)
            else
                panel._mlTimerBar:SetVertexColor(0.4, 0.4, 0.4, 0.8)
            end

            if panel._mlTimerText then
                panel._mlTimerText:SetText(string.format("%d:%02d",
                    math.floor(remaining / 60), math.floor(remaining % 60)))
            end
        end
    end
end
