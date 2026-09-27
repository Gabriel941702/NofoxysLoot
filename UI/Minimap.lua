-- Nofoxy Minimap Button
-- A small draggable button on the minimap edge that toggles the main
-- window. No external libraries (LibDBIcon etc.) — hand-built to match
-- how the rest of this addon is put together.

local UI = NofoxyUI  -- already created by Frame.lua, which loads before this

local button

local function UpdatePosition()
    if not button then return end
    local angle = math.rad(Nofoxy.db.minimapAngle or 225)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function UI:CreateMinimapButton()
    if button then return end

    button = CreateFrame("Button", "NofoxysLootMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the default icon border a touch

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetSize(30, 30)
    highlight:SetPoint("CENTER", 0, 1)
    highlight:SetBlendMode("ADD")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            Nofoxy.db.minimapAngle = angle
            UpdatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(self, mouseButton)
        if not NofoxyFrame then return end
        if NofoxyFrame:IsShown() then NofoxyFrame:Hide() else NofoxyFrame:Show() end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Nofoxy's Loot")
        GameTooltip:AddLine("Click to toggle window", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag to move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    self:SetMinimapButtonShown(Nofoxy.db.minimapShown ~= false)
end

function UI:SetMinimapButtonShown(shown)
    if not button then return end
    if shown then button:Show() else button:Hide() end
end
