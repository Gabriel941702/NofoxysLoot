-- Nofoxy Core
-- Pure event bus and addon lifecycle.
-- No domain logic lives here — delegates to MasterLoot, SoftRes, AutoLoot.
-- Core.lua loads LAST in the toc so that all domain and UI modules are
-- already defined when events fire.

local addon = CreateFrame("Frame", "NofoxyCore", UIParent)
Nofoxy = addon

local DEFAULT_SAVED = {
    windowPos          = { x = nil, y = nil },
    windowSize         = { w = nil, h = nil },
    locked             = false,
    debug              = false,
    qualityFilter      = 2,      -- Uncommon (green) minimum by default
    autoLootEnabled    = false,
    autoLootThreshold  = 0,      -- Poor (grey) and below, by default — deliberately
                                 -- conservative, since many recipes/patterns are
                                 -- plain white (Common) quality and shouldn't be
                                 -- silently swept away with real trash.
    autoLootBoE        = false,  -- also auto-loot anything that's NOT Bind on
                                 -- Pickup (no-bind or Bind on Equip), regardless
                                 -- of quality — catches most recipes/bags safely
                                 -- since those are freely tradeable either way.
    rollDuration       = 30,
    chatMessagesEnabled = true,
    secureRollingItems = true,
    minimapShown       = true,
    minimapAngle       = 225,
    softReserves       = {},
}

addon.db = {}

-- ============================================================
-- ---- Event dispatch ----
-- ============================================================

function addon:OnEvent(event, ...)
    if self[event] then self[event](self, event, ...) end
end
addon:SetScript("OnEvent", addon.OnEvent)

-- ============================================================
-- ---- Lifecycle ----
-- ============================================================

function addon:PLAYER_LOGIN()
    self.db = Nofoxy_SavedVars or {}
    for k, v in pairs(DEFAULT_SAVED) do
        if self.db[k] == nil then self.db[k] = v end
    end

    -- Master Loot events
    self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self:RegisterEvent("TRADE_SHOW")
    self:RegisterEvent("TRADE_CLOSED")
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    -- Build window
    NofoxyUI:Create()
    if NofoxyUI.CreateMinimapButton then
        NofoxyUI:CreateMinimapButton()
    end
    LRRefreshClassCache()

    -- Load persisted data into domain modules
    NofoxySR:LoadFromDB(self.db)
    NofoxyML.rollDuration = self.db.rollDuration or 30
    NofoxyML:Initialize()

    -- Restore window position / size
    if self.db.windowPos.x and self.db.windowPos.y then
        NofoxyFrame:ClearAllPoints()
        NofoxyFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            self.db.windowPos.x, self.db.windowPos.y)
    end
    if self.db.windowSize.w and self.db.windowSize.h then
        NofoxyFrame:SetSize(self.db.windowSize.w, self.db.windowSize.h)
    end
    NofoxyUI:UpdateMovable()

    self:Print("Loaded. Type /nofoxy, /nfx, or /karu to toggle the window.")
end

function addon:SaveWindowState()
    if not NofoxyFrame then return end
    local left = NofoxyFrame:GetLeft()
    local top  = NofoxyFrame:GetTop()
    if left and top then
        self.db.windowPos.x = left
        self.db.windowPos.y = top - UIParent:GetHeight()
    end
    local w, h = NofoxyFrame:GetWidth(), NofoxyFrame:GetHeight()
    if w and h then
        self.db.windowSize.w = w
        self.db.windowSize.h = h
    end
    NofoxySR:SaveToDB(self.db)
    Nofoxy_SavedVars = self.db
end

function addon:PLAYER_LOGOUT()
    self:SaveWindowState()
end

-- ============================================================
-- ---- Master Loot events → MasterLoot module ----
-- ============================================================

function addon:PARTY_LOOT_METHOD_CHANGED()
    NofoxyML:OnLootMethodChanged()
end

function addon:LOOT_OPENED()
    NofoxyML:OnLootOpened()
end

function addon:LOOT_CLOSED()
    NofoxyML:OnLootClosed()
end

function addon:CHAT_MSG_SYSTEM(event, message)
    NofoxyParser:ProcessSystemMessage(message)
end

function addon:CHAT_MSG_ADDON(event, prefix, message, distribution, sender)
    if prefix ~= "NOFOXY" then return end
    NofoxyML:OnAddonMessage(prefix, message, distribution, sender)
end

function addon:GROUP_ROSTER_UPDATE()
    NofoxyML:ResolveRole()
    LRRefreshClassCache()
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function addon:GET_ITEM_INFO_RECEIVED(event, itemID, success)
    if success then NofoxyML:OnItemInfoReceived(itemID) end
end

function addon:TRADE_SHOW()
    NofoxyML:OnTradeShow()
end

function addon:TRADE_CLOSED()
    NofoxyML:OnTradeClosed()
end

-- ============================================================
-- ---- Utility ----
-- ============================================================

function addon:Print(...)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffNofoxy|r " .. strjoin(" ", ...))
end

-- Same as Print, but respects the "Chat Messages" mute toggle. Used ONLY
-- for the passive local echo of things already announced elsewhere (raid
-- chat/raid warning roll announcements, the login banner) — never for
-- errors, import results, or direct command/button feedback, since muting
-- those would hide the reason something didn't work.
function addon:PrintQuiet(...)
    if self.db and self.db.chatMessagesEnabled == false then return end
    self:Print(...)
end

-- ============================================================
-- ---- Slash commands ----
-- ============================================================

SLASH_NOFOXY1 = "/nofoxy"
SLASH_NOFOXY2 = "/nfx"
SLASH_NOFOXY3 = "/karu"

SlashCmdList["NOFOXY"] = function(msg)
    -- Deliberately NOT lowercasing the whole message — a shift-clicked item
    -- link contains case-sensitive markup (|H vs |h mean different things),
    -- so lowercasing it would corrupt the link. Only the command keyword
    -- itself gets lowercased for matching; everything after it (the "rest")
    -- keeps its original casing intact for commands that need it.
    local trimmed = (msg or ""):trim()
    local firstWord, rest = trimmed:match("^(%S*)%s*(.-)$")
    firstWord = (firstWord or ""):lower()
    rest = rest or ""

    if firstWord == "" then
        if not NofoxyFrame then
            addon:Print("Window not ready — check /framestack for errors")
            return
        end
        if NofoxyFrame:IsShown() then NofoxyFrame:Hide() else NofoxyFrame:Show() end

    elseif firstWord == "lock" then
        addon.db.locked = not addon.db.locked
        addon:PrintQuiet("Window " .. (addon.db.locked and "locked" or "unlocked"))
        NofoxyUI:UpdateMovable()

    elseif firstWord == "clear" then
        NofoxyML:ClearDone()

    elseif firstWord == "test" then
        NofoxyML:InjectTestRolls()

    elseif firstWord == "srtest" then
        NofoxyML:InjectSRTest()

    elseif firstWord == "ashkandi" or firstWord == "troll" then
        NofoxyML:InjectAshkandiTroll()

    elseif firstWord == "roll" then
        NofoxyML:AddBagItemToRoll(rest)

    elseif firstWord == "debug" then
        addon.db.debug = not addon.db.debug
        addon:Print("Debug " .. (addon.db.debug and "ON" or "OFF"))

    elseif firstWord == "sr" and rest:lower() == "clear" then
        NofoxySR:Clear()
        addon:PrintQuiet("Soft reserves cleared.")
        if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end

    else
        addon:Print("Commands: (/nofoxy, /nfx, and /karu all work the same)")
        addon:Print("  /nfx            — Toggle window")
        addon:Print("  /nfx lock       — Toggle window lock")
        addon:Print("  /nfx clear      — Clear done Master Loot items")
        addon:Print("  /nfx roll       — Add a bag item to roll for (type this, then shift-click the item)")
        addon:Print("  /nfx sr clear   — Clear all imported Soft Reserves")
        addon:Print("  /nfx test       — Inject mock Master Loot data")
        addon:Print("  /nfx srtest     — Seed sample Soft Reserves + simulate the full SR flow")
        addon:Print("  /nfx ashkandi   — Start a real (fake) roll for Ashkandi, Greatsword of the Brotherhood")
        addon:Print("  /nfx debug      — Toggle debug logging")
    end
end

addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_LOGOUT")
