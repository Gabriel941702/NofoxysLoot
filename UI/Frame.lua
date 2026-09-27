-- Nofoxy UI Frame
-- Main window, scroll system, tab bar, and the Refresh/UpdateTimers loop.
-- Delegates tab content rendering to MasterLootUI, SoftResUI and OptionsUI.

local UI = {}
NofoxyUI = UI

local currentTab = "master"

function UI:Create()
    if NofoxyFrame then return NofoxyFrame end

    local W  = LR_DEFAULT_WIDTH
    local H  = LR_DEFAULT_HEIGHT
    local TH = LR_TAB_BAR_HEIGHT
    local CM = LR_CONTENT_MARGIN
    local SW = LR_SCROLL_WIDTH

    local frame = CreateFrame("Frame", "NofoxyFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:Hide()

    local bg = LRColorTex(frame, "BACKGROUND", 0.08, 0.08, 0.08, 1.0)
    bg:SetAllPoints(frame)

    local topLine = LRColorTex(frame, "BORDER", 0.2, 0.2, 0.2, 0.8)
    topLine:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topLine:SetHeight(1)

    -- ---- Scroll area ----
    local scrollFrame = CreateFrame("ScrollFrame", "NofoxyScroll", frame)
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     CM, -(TH + 1))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(CM + SW + 2), CM)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", "NofoxyContent", scrollFrame)
    content:SetWidth(W - CM * 2 - SW - 2)
    content:SetHeight(20)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- ---- Scrollbar ----
    local scrollBar = CreateFrame("Frame", nil, frame)
    scrollBar:SetWidth(SW)
    scrollBar:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -CM, -(TH + 1))
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CM, CM)
    frame.scrollBar = scrollBar

    local track = LRColorTex(scrollBar, "BACKGROUND", 0.06, 0.06, 0.06, 0.8)
    track:SetAllPoints(scrollBar)

    local thumb = CreateFrame("Button", nil, scrollBar)
    thumb:SetWidth(SW - 4)
    thumb:SetPoint("LEFT", scrollBar, "LEFT", 2, 0)
    thumb:SetHeight(40)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbBg = LRColorTex(thumb, "ARTWORK", 0.22, 0.22, 0.22, 0.9)
    thumbBg:SetAllPoints(thumb)

    local thumbOffset = 0
    thumb:SetScript("OnDragStart", function()
        local _, thumbTop = thumb:GetCenter()
        local sbTop = scrollBar:GetTop()
        if not sbTop then sbTop = scrollBar:GetParent():GetTop() - TH end
        thumbOffset = thumbTop - sbTop
        thumb.isDragging = true
    end)
    thumb:SetScript("OnDragStop", function() thumb.isDragging = false end)
    thumb:SetScript("OnUpdate", function()
        if not thumb.isDragging then return end
        local mouseY = GetCursorPosition() / (scrollBar:GetEffectiveScale() or 1)
        local sbTop  = scrollBar:GetTop()
        local sbBot  = scrollBar:GetBottom()
        if not sbTop or not sbBot then return end
        local trackH  = sbTop - sbBot - thumb:GetHeight()
        if trackH <= 0 then return end
        local newTop  = math.max(sbTop, math.min(sbBot + thumb:GetHeight(), mouseY + thumbOffset))
        local offset  = (sbTop - newTop) / trackH
        local maxOff  = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(offset * maxOff)
    end)
    scrollBar.thumb = thumb

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur    = self:GetVerticalScroll()
        local maxOff = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxOff, cur - delta * 30)))
    end)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        scrollFrame:SetVerticalScroll(offset)
        UI:UpdateThumb()
    end)

    -- ---- Tab bar ----
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabBar:SetHeight(TH)

    local tabBarBg = LRColorTex(tabBar, "BACKGROUND", 0.11, 0.11, 0.11, 1.0)
    tabBarBg:SetAllPoints(tabBar)
    local tabSep = LRColorTex(tabBar, "BORDER", 0.2, 0.2, 0.2, 0.6)
    tabSep:SetPoint("BOTTOMLEFT",  tabBar, "BOTTOMLEFT",  0, 0)
    tabSep:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabSep:SetHeight(1)

    frame.tabs = {}

    local mlTab = LRMakeTab(tabBar, "Master: 0", 90, "master",
        tabBar, "LEFT", 6, function() UI:SwitchTab("master") end,
        function() return currentTab end)
    frame.tabs.master = mlTab

    local srTab = LRMakeTab(tabBar, "Soft Reserves", 100, "softres",
        mlTab, "RIGHT", 0, function() UI:SwitchTab("softres") end,
        function() return currentTab end)
    frame.tabs.softres = srTab

    local optTab = LRMakeTab(tabBar, "Options", 65, "options",
        srTab, "RIGHT", 0, function() UI:SwitchTab("options") end,
        function() return currentTab end)
    frame.tabs.options = optTab

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 1)
    closeBtn:SetSize(24, 24)

    -- ---- Drag ----
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetMovable(true)
    frame:SetScript("OnDragStart", function(self)
        if not Nofoxy.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Nofoxy:SaveWindowState()
    end)

    -- ---- Resize grip ----
    frame:SetResizable(true)
    frame:SetMinResize(LR_MIN_WIDTH, LR_MIN_HEIGHT)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")

    local gripIcon = grip:CreateTexture(nil, "OVERLAY")
    gripIcon:SetSize(14, 14)
    gripIcon:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 2)
    gripIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local w = frame:GetWidth()
        local h = frame:GetHeight()
        if w < LR_MIN_WIDTH then frame:SetWidth(LR_MIN_WIDTH) end
        if h < LR_MIN_HEIGHT then frame:SetHeight(LR_MIN_HEIGHT) end
        content:SetWidth(frame:GetWidth() - CM * 2 - SW - 2)
        Nofoxy:SaveWindowState()
        UI:Refresh()
    end)
    frame.grip = grip

    -- ---- Timer loop ----
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed >= 0.25 then
            self._elapsed = 0
            UI:UpdateTimers()
        end
    end)

    NofoxyFrame = frame
    UI:SwitchTab("master")
    return frame
end

-- ============================================================
-- ---- Tab switching ----
-- ============================================================

function UI:SwitchTab(tab)
    currentTab = tab
    local frame = NofoxyFrame
    if not frame then return end

    local function activate(t)
        t.indicator:SetVertexColor(0.35, 0.35, 0.35, 1.0)
        t.text:SetTextColor(0.85, 0.85, 0.85)
    end
    local function deactivate(t)
        t.indicator:SetVertexColor(0.12, 0.12, 0.12, 0.0)
        t.text:SetTextColor(0.4, 0.4, 0.4)
    end

    if tab == "master" then
        activate(frame.tabs.master); deactivate(frame.tabs.softres); deactivate(frame.tabs.options)
    elseif tab == "softres" then
        deactivate(frame.tabs.master); activate(frame.tabs.softres); deactivate(frame.tabs.options)
    else
        deactivate(frame.tabs.master); deactivate(frame.tabs.softres); activate(frame.tabs.options)
    end

    if frame.scrollFrame then frame.scrollFrame:SetVerticalScroll(0) end
    UI:Refresh()
end

function UI:GetCurrentTab() return currentTab end

-- ============================================================
-- ---- Refresh ----
-- ============================================================

function UI:Refresh()
    local frame = NofoxyFrame
    if not frame or not frame.content then return end

    local content      = frame.content
    local contentWidth = frame:GetWidth() - LR_CONTENT_MARGIN * 2 - LR_SCROLL_WIDTH - 2
    content:SetWidth(contentWidth)

    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide(); child:ClearAllPoints()
    end
    for _, region in ipairs({ content:GetRegions() }) do
        region:Hide()
    end

    local finalY
    if currentTab == "master" then
        finalY = RefreshMasterLootTab(content, frame)
    elseif currentTab == "softres" then
        finalY = RefreshSoftResTab(content, frame)
    else
        finalY = RefreshOptionsTab(content, frame)
    end

    content:SetHeight(math.max(-finalY + LR_CONTENT_MARGIN, 20))

    local sf = frame.scrollFrame
    if sf and frame.scrollBar then
        local cH = content:GetHeight()
        local vH = sf:GetHeight()
        if cH > vH then
            frame.scrollBar:Show()
            frame.scrollBar.thumb:Show()
            UI:UpdateThumb()
        else
            frame.scrollBar.thumb:Hide()
            sf:SetVerticalScroll(0)
        end
    end

    UI:UpdateTabCounts()
end

function UI:UpdateThumb()
    local frame = NofoxyFrame
    if not frame then return end
    local sf = frame.scrollFrame
    local sb = frame.scrollBar
    if not sf or not sb then return end

    local thumb   = sb.thumb
    local cH      = sf:GetScrollChild():GetHeight()
    local vH      = sf:GetHeight()
    local maxScrl = math.max(1, cH - vH)
    local pct     = sf:GetVerticalScroll() / maxScrl
    local trackH  = sb:GetHeight()
    local thumbH  = math.max(20, math.min(trackH, vH / cH * trackH))
    thumb:SetHeight(thumbH)
    thumb:SetPoint("TOP", sb, "TOP", 0, -(pct * (trackH - thumbH)))
end

function UI:UpdateTabCounts()
    local frame = NofoxyFrame
    if not frame then return end

    local ml = NofoxyML
    if ml and frame.tabs.master then
        frame.tabs.master.text:SetText("Master: " .. ml:GetActiveItemCount())
    end
    local sr = NofoxySR
    if sr and frame.tabs.softres then
        frame.tabs.softres.text:SetText("SR: " .. sr.itemCount)
    end
end

function UI:UpdateTimers()
    local frame = NofoxyFrame
    if not frame or not frame:IsShown() then return end
    if currentTab == "master" then
        UpdateMasterLootTimers()
    end
end

function UI:UpdateMovable()
    local frame = NofoxyFrame
    if not frame then return end
    frame:SetMovable(not Nofoxy.db.locked)
    frame:SetResizable(not Nofoxy.db.locked)
    if frame.grip then frame.grip:EnableMouse(not Nofoxy.db.locked) end
end
