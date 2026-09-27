-- Nofoxy OptionsUI
-- Renders the Options tab.

local QUALITY_TIERS = {
    { id = 0, label = "Poor",     color = { 0.62, 0.62, 0.62 } },
    { id = 1, label = "Common",   color = { 1.00, 1.00, 1.00 } },
    { id = 2, label = "Uncommon", color = { 0.12, 1.00, 0.00 } },
    { id = 3, label = "Rare",     color = { 0.00, 0.44, 0.87 } },
    { id = 4, label = "Epic",     color = { 0.64, 0.21, 0.93 } },
    { id = 5, label = "Legendary",color = { 1.00, 0.50, 0.00 } },
}

local function GetQualityLabel(quality)
    for _, tier in ipairs(QUALITY_TIERS) do
        if tier.id == quality then return tier.label end
    end
    return "Unknown"
end

local function RenderQualityPicker(content, yOffset, currentValue, onPick, maxTier)
    local btnW = (content:GetWidth() - LR_PANEL_PADDING * 2 - 4 * 5) / 6
    local btnH = 20
    local row  = LRHLayout(4)
    local atY  = yOffset

    for _, tier in ipairs(QUALITY_TIERS) do
        if not maxTier or tier.id <= maxTier then
            local isActive = (tier.id == currentValue)
            local nc = isActive and { tier.color[1] * 0.4, tier.color[2] * 0.4, tier.color[3] * 0.4 }
                                  or { 0.15, 0.15, 0.15 }
            local hc = { tier.color[1] * 0.5, tier.color[2] * 0.5, tier.color[3] * 0.5 }
            local tc = isActive and { tier.color[1], tier.color[2], tier.color[3] } or { 0.5, 0.5, 0.5 }
            local btn = LRMakeButton(content, string.sub(tier.label, 1, 3), btnW, btnH, nc, hc, tc,
                function() onPick(tier.id) end)
            row:Place(btn, content, LR_PANEL_PADDING, atY)
            btn:Show()
        end
    end
    return btnH
end

function RefreshOptionsTab(content, frame)
    local yOffset = -LR_CONTENT_MARGIN

    local version = GetAddOnMetadata("NofoxysLoot", "Version") or ""
    if version ~= "" then
        local verLbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        verLbl:SetPoint("TOPRIGHT", content, "TOPRIGHT", -LR_CONTENT_MARGIN, yOffset)
        verLbl:SetText("Nofoxy v" .. version)
        verLbl:SetTextColor(0.4, 0.4, 0.4)
        yOffset = yOffset - 18
    end

    -- ============================================================
    -- ---- Auto-Loot panel ----
    -- ============================================================

    local alTitle, alTH = LRMakeLabel(content, "Auto-Loot", 0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - alTH - 2

    local alPanel = LRMakePanel(content, 0.6)
    alPanel:SetWidth(content:GetWidth())
    local alLayout = LRVLayout(alPanel, -(LR_PANEL_PADDING + 14), 0)

    local alOn = Nofoxy.db and Nofoxy.db.autoLootEnabled
    LRMakeToggleButton(alPanel, alOn,
        "Auto-Loot: ENABLED — click to disable",
        "Auto-Loot: DISABLED — click to enable",
        function(newChecked)
            Nofoxy.db.autoLootEnabled = newChecked
            Nofoxy:PrintQuiet("Auto-Loot " .. (newChecked and "enabled" or "disabled"))
            NofoxyUI:Refresh()
        end, alLayout.y)
    alLayout:Advance(24 + 6)

    if alOn then
        local threshold = Nofoxy.db.autoLootThreshold or 0
        local tc = LR_QUALITY_COLORS[threshold] or LR_QUALITY_COLORS[0]
        local lbl, lblH = LRMakeLabel(alPanel,
            "Auto-hand to yourself: " .. GetQualityLabel(threshold) .. " quality and below",
            tc.r, tc.g, tc.b, alLayout.y)
        alLayout:Advance(lblH, 4)

        local btnH = RenderQualityPicker(alPanel, alLayout.y, threshold, function(id)
            Nofoxy.db.autoLootThreshold = id
            Nofoxy:PrintQuiet("Auto-Loot threshold set to " .. GetQualityLabel(id) .. " and below")
            NofoxyUI:Refresh()
        end, 3)
        alLayout:Advance(btnH + LR_PANEL_PADDING)

        LRMakeSeparator(alPanel, alLayout.y, 4)
        alLayout:Advance(1, 8)

        local boeOn = Nofoxy.db.autoLootBoE
        LRMakeToggleButton(alPanel, boeOn,
            "Also auto-loot non-BoP items: ON",
            "Also auto-loot non-BoP items: OFF",
            function(newChecked)
                Nofoxy.db.autoLootBoE = newChecked
                Nofoxy:PrintQuiet("Auto-loot non-BoP items " .. (newChecked and "enabled" or "disabled"))
                NofoxyUI:Refresh()
            end, alLayout.y)
        alLayout:Advance(24 + 4)

        local boeNote, boeNoteH = LRMakeLabel(alPanel,
            "Catches items that are unbound or Bind-on-Equip — regardless of quality — since those are always " ..
            "freely tradeable/sellable, no matter what. This is the setting you want for recipes, patterns, and " ..
            "bags: many of those are plain white (Common) quality, so the quality slider above can't tell them " ..
            "apart from real junk, but they're basically never Bind-on-Pickup. True Bind-on-Pickup drops NEVER " ..
            "auto-loot under this, no matter how low their quality is — they'll always show up on the Master " ..
            "Loot tab for you to roll.",
            0.4, 0.4, 0.4, alLayout.y - 2, nil, "GameFontHighlightSmall")
        alLayout:Advance(boeNoteH, 6)

        local note, nH = LRMakeLabel(alPanel,
            "Soft-Reserved items are never auto-looted under either setting, regardless of quality.",
            0.4, 0.4, 0.4, alLayout.y - 2, nil, "GameFontHighlightSmall")
        alLayout:Advance(nH)
    else
        local note, nH = LRMakeLabel(alPanel,
            "When enabled, items at or below the chosen quality go straight to your own bags — no roll, no click.",
            0.4, 0.4, 0.4, alLayout.y - 2, nil, "GameFontHighlightSmall")
        alLayout:Advance(nH)
    end

    local alPanelH = -alLayout.y + LR_PANEL_PADDING
    alPanel:SetHeight(alPanelH)
    alPanel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    alPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    yOffset = yOffset - alPanelH - 8

    -- ============================================================
    -- ---- Master Loot Filters panel ----
    -- ============================================================

    local filterTitle, filterTH = LRMakeLabel(content, "Master Loot Filters", 0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - filterTH - 2

    local fPanel = LRMakePanel(content, 0.6)
    fPanel:SetWidth(content:GetWidth())
    local fLayout = LRVLayout(fPanel, -(LR_PANEL_PADDING + 14), 0)

    local fLabel, flH = LRMakeLabel(fPanel, "Minimum item quality to track:", 0.6, 0.6, 0.6, fLayout.y)
    fLayout:Advance(flH, 2)

    local currentFilter = NofoxyML and NofoxyML:GetFilterThreshold() or 2
    local fc = LR_QUALITY_COLORS[currentFilter] or LR_QUALITY_COLORS[2]
    local curLbl, clH = LRMakeLabel(fPanel, "Current: " .. GetQualityLabel(currentFilter), fc.r, fc.g, fc.b, fLayout.y)
    fLayout:Advance(clH, 8)

    local btnH2 = RenderQualityPicker(fPanel, fLayout.y, currentFilter, function(id)
        Nofoxy.db.qualityFilter = id
        Nofoxy:PrintQuiet("Quality filter set to " .. GetQualityLabel(id) .. " and above")
        if NofoxyML and NofoxyML:IsML() then NofoxyML:BroadcastFilter() end
        NofoxyUI:Refresh()
    end)
    fLayout:Advance(btnH2 + LR_PANEL_PADDING)

    local finfo, finfoH = LRMakeLabel(fPanel,
        "Soft-Reserved items always show, regardless of this filter.",
        0.4, 0.4, 0.4, fLayout.y - 2, nil, "GameFontHighlightSmall")
    fLayout:Advance(finfoH)

    local fPanelH = -fLayout.y + LR_PANEL_PADDING
    fPanel:SetHeight(fPanelH)
    fPanel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    fPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    yOffset = yOffset - fPanelH - 8

    -- ============================================================
    -- ---- Roll Settings panel ----
    -- ============================================================

    local rTitle, rTH = LRMakeLabel(content, "Roll Settings", 0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - rTH - 2

    local rPanel = LRMakePanel(content, 0.6)
    rPanel:SetWidth(content:GetWidth())
    local rLayout = LRVLayout(rPanel, -(LR_PANEL_PADDING + 14), 0)

    local dur = NofoxyML and NofoxyML.rollDuration or 30
    local durLbl, durH = LRMakeLabel(rPanel, "Roll duration: " .. dur .. "s (used for manual and Soft-Reserve rolls)",
        0.8, 0.8, 0.8, rLayout.y)
    rLayout:Advance(durH, 4)

    local durRow = LRHLayout(4)
    local durOptions = { 15, 20, 30, 45, 60 }
    local durBtnW = (rPanel:GetWidth() - LR_PANEL_PADDING * 2 - 4 * (#durOptions - 1)) / #durOptions
    for _, seconds in ipairs(durOptions) do
        local isActive = (seconds == dur)
        local nc = isActive and { 0.10, 0.30, 0.10 } or { 0.15, 0.15, 0.15 }
        local hc = { 0.20, 0.45, 0.20 }
        local tc = isActive and { 0.5, 1.0, 0.5 } or { 0.6, 0.6, 0.6 }
        local btn = LRMakeButton(rPanel, seconds .. "s", durBtnW, 20, nc, hc, tc,
            function()
                NofoxyML.rollDuration = seconds
                Nofoxy.db.rollDuration = seconds
                Nofoxy:PrintQuiet("Roll duration set to " .. seconds .. "s")
                NofoxyUI:Refresh()
            end)
        durRow:Place(btn, rPanel, LR_PANEL_PADDING, rLayout.y)
        btn:Show()
    end
    rLayout:Advance(20 + LR_PANEL_PADDING)

    local secureOn = Nofoxy.db == nil or Nofoxy.db.secureRollingItems ~= false
    LRMakeToggleButton(rPanel, secureOn,
        "Secure rolling items to your bags: ON",
        "Secure rolling items to your bags: OFF",
        function(newChecked)
            Nofoxy.db.secureRollingItems = newChecked
            Nofoxy:PrintQuiet("Secure rolling items to bags " .. (newChecked and "enabled" or "disabled"))
            NofoxyUI:Refresh()
        end, rLayout.y - 4)
    rLayout:Advance(24 + 4, 4)

    local secureNote, secureNoteH
    if secureOn then
        secureNote, secureNoteH = LRMakeLabel(rPanel,
            "The moment something starts rolling, it's pulled into your own bags right away, so Award always goes out through a quick trade — guaranteed to work regardless of what you do between the roll starting and ending.",
            0.4, 0.4, 0.4, rLayout.y - 2, nil, "GameFontHighlightSmall")
    else
        secureNote, secureNoteH = LRMakeLabel(rPanel,
            "Items stay put while rolling. Award tries to hand them out directly first, with no trade, and only falls back to a trade if that's no longer possible by the time you click it. Use this if you'd rather items not sit in your bags while a roll is open.",
            0.6, 0.45, 0.2, rLayout.y - 2, nil, "GameFontHighlightSmall")
    end
    rLayout:Advance(secureNoteH)

    local rPanelH = -rLayout.y + LR_PANEL_PADDING
    rPanel:SetHeight(rPanelH)
    rPanel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    rPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    yOffset = yOffset - rPanelH - 8

    -- ============================================================
    -- ---- Misc panel ----
    -- ============================================================

    local mTitle, mTH = LRMakeLabel(content, "Misc", 0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - mTH - 2

    local mPanel = LRMakePanel(content, 0.6)
    mPanel:SetWidth(content:GetWidth())
    local mLayout = LRVLayout(mPanel, -(LR_PANEL_PADDING + 14), 0)

    local locked = Nofoxy.db and Nofoxy.db.locked
    LRMakeToggleButton(mPanel, locked,
        "Window: LOCKED — click to unlock",
        "Window: UNLOCKED — click to lock",
        function(newChecked)
            Nofoxy.db.locked = newChecked
            NofoxyUI:UpdateMovable()
            NofoxyUI:Refresh()
        end, mLayout.y)
    mLayout:Advance(24 + 6)

    local minimapOn = Nofoxy.db == nil or Nofoxy.db.minimapShown ~= false
    LRMakeToggleButton(mPanel, minimapOn,
        "Minimap Button: SHOWN — click to hide",
        "Minimap Button: HIDDEN — click to show",
        function(newChecked)
            Nofoxy.db.minimapShown = newChecked
            NofoxyUI:SetMinimapButtonShown(newChecked)
            NofoxyUI:Refresh()
        end, mLayout.y)
    mLayout:Advance(24 + 6)

    local chatOn = Nofoxy.db and Nofoxy.db.chatMessagesEnabled ~= false
    LRMakeToggleButton(mPanel, chatOn,
        "Chat Messages: ON — click to silence",
        "Chat Messages: OFF — click to enable",
        function(newChecked)
            Nofoxy.db.chatMessagesEnabled = newChecked
            NofoxyUI:Refresh()
            if newChecked then Nofoxy:Print("Chat messages enabled") end
        end, mLayout.y)
    mLayout:Advance(24 + 2)

    local chatNote, chatNH = LRMakeLabel(mPanel,
        "Only mutes the redundant local echo of raid announcements (the Raid Warning / raid chat message itself still sends normally). Errors, import results, and command feedback always show.",
        0.4, 0.4, 0.4, mLayout.y - 2, nil, "GameFontHighlightSmall")
    mLayout:Advance(chatNH, 6)

    local debugOn = Nofoxy.db and Nofoxy.db.debug
    LRMakeToggleButton(mPanel, debugOn,
        "Debug logging: ON — click to disable",
        "Debug logging: OFF — click to enable",
        function(newChecked)
            Nofoxy.db.debug = newChecked
            NofoxyUI:Refresh()
        end, mLayout.y)
    mLayout:Advance(24 + 2)

    local mPanelH = -mLayout.y + LR_PANEL_PADDING
    mPanel:SetHeight(mPanelH)
    mPanel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    mPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
    yOffset = yOffset - mPanelH - 8

    return yOffset
end
