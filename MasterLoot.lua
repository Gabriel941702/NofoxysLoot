-- Nofoxy MasterLoot Module
-- Owns: Item class, Session object, role detection, protocol send/receive,
-- roll lifecycle (manual AND soft-reserve-automatic), and award/trade.
-- No UI code. No event registration (Core delegates here).
--
-- MasterLoot references the Nofoxy global directly at call time only.

-- ============================================================
-- ---- Protocol constants ----
-- ============================================================
-- Field separator: ASCII \001 (SOH) — never appears in GUIDs, item IDs, or names.
--
-- Item identity key: "{GUID}:{itemID}"  e.g. "Creature-0-1234-5678:18815"
--
-- ITEM\001itemKey\001link                                    -> item exists
-- SR\001itemKey\001name1\001name2...                         -> item is soft-reserved by these (valid, in-raid) names
-- ROLL_START\001itemKey\001kind[\001name1\001name2...]       -> kind: "open" | "sr" | "tie"
-- ROLL_END\001itemKey\001winnerName                          -> roll closed ("none" = no winner / tie)
-- ITEM_DONE\001itemKey                                       -> item finalized
-- FILTER\001qualityValue                                     -> ML broadcasts filter change
-- CLEAR                                                       -> session ended

local SEP = "\001"

local function SplitBySep(message)
    local parts = {}
    for seg in string.gmatch(message, "[^" .. SEP .. "]+") do
        table.insert(parts, seg)
    end
    return parts
end

-- Strips a "-RealmName" suffix and normalizes case before comparing player
-- names. Different WoW APIs (and especially different private-server
-- cores) are inconsistent about whether names come back with a realm
-- suffix, so comparing raw strings can silently fail to match even when
-- it's obviously the same person — which breaks candidate lookups,
-- roster checks, and Soft-Reserve matching with no visible error at all.
-- Always compare names through this, never with a bare ==.
local function NormalizeName(name)
    if not name then return nil end
    name = name:match("^([^-]+)") or name
    return name:lower()
end

-- Sends a raid announcement, degrading gracefully if the ML isn't a raid
-- leader/officer (RAID_WARNING silently fails to send for anyone else).
local function SendAnnounce(msg)
    local channel
    if GetNumRaidMembers() > 0 then
        channel = (IsRaidLeader() or IsRaidOfficer()) and "RAID_WARNING" or "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        channel = nil
    end
    if channel then
        SendChatMessage(msg, channel)
    end
    -- Always respect the mute toggle here, even solo with no channel to
    -- send to — "Chat Messages: OFF" should mean off, full stop, not
    -- "off except when there's nobody else around to see it in raid chat."
    Nofoxy:PrintQuiet(msg)
end

-- ============================================================
-- ---- Item class ----
-- ============================================================

local Item = {}
Item.__index = Item

function Item.new(itemKey, link, texture, quality, name, slot)
    return setmetatable({
        itemKey          = itemKey,
        link             = link   or "",
        texture          = texture or "",
        quality          = quality or 2,
        name             = name   or "Unknown",
        slot             = slot   or 0,
        infoLoaded       = true,
        quantity         = 1,
        rolls            = {},    -- { [playerName] = { value, time } }
        rerolls          = {},    -- duplicate rolls
        rolling          = false,
        rollStart        = nil,
        isDone           = false,
        winner           = nil,
        wasRolled        = nil,
        eligiblePlayers  = nil,   -- set during SR/tie rolls: { [name] = true }
        srHolders        = nil,   -- array of names who soft-reserved this item
        autoAward        = false, -- true when this item's roll should auto-award the winner
        heldByML         = false, -- true once SecureItemToSelf has pulled it into the ML's bags
    }, Item)
end

function Item:IsRolling() return self.rolling == true end
function Item:IsDone()    return self.isDone == true end

function Item:RollCount()
    local n = 0
    for _ in pairs(self.rolls) do n = n + 1 end
    return n
end

function Item:RerollCount()
    local n = 0
    for _ in pairs(self.rerolls) do n = n + 1 end
    return n
end

function Item:HasRolled(playerName)
    return self.rolls[playerName] ~= nil
end

function Item:GetTiedWinners()
    local bestValue = 0
    local names = {}
    for playerName, info in pairs(self.rolls) do
        if info.value and info.value > bestValue then
            bestValue = info.value
            names = { playerName }
        elseif info.value and info.value == bestValue then
            table.insert(names, playerName)
        end
    end
    if #names <= 1 then return nil end
    return { names = names, value = bestValue }
end

function Item:IsTied()
    return self:GetTiedWinners() ~= nil
end

function Item:ResetForReroll()
    local tied = self:GetTiedWinners()
    if not tied then return end
    self.rolling   = false
    self.rollStart = nil
    self.winner    = nil
    self.eligiblePlayers = {}
    for _, name in ipairs(tied.names) do
        self.eligiblePlayers[name] = true
    end
end

function Item:GetWinner()
    local bestPlayer, bestValue = nil, 0
    for playerName, info in pairs(self.rolls) do
        if info.value and info.value > bestValue then
            bestValue  = info.value
            bestPlayer = playerName
        end
    end
    return bestPlayer, bestValue
end

function Item:GetSortedRolls()
    local list = {}
    for playerName, info in pairs(self.rolls) do
        table.insert(list, { name = playerName, value = info.value })
    end
    table.sort(list, function(a, b)
        local va = a.value or -1
        local vb = b.value or -1
        if va ~= vb then return va > vb end
        return a.name < b.name
    end)
    return list
end

function Item:RecordRoll(playerName, value)
    if not self.rolling then return "no_active_roll" end
    if self.eligiblePlayers and not self.eligiblePlayers[playerName] then
        return "not_eligible"
    end
    if self.rolls[playerName] then
        self.rerolls[playerName] = { value = value, time = GetTime() }
        return "reroll"
    end
    self.rolls[playerName] = { value = value, time = GetTime() }
    return "ok"
end

NofoxyItem = Item

-- ============================================================
-- ---- Session object ----
-- ============================================================

local Session = {}
Session.__index = Session

function Session.new(role)
    return setmetatable({
        role         = role,   -- "MasterLooter" | "Raider"
        items        = {},     -- { [itemKey] = Item }
        currentRoll  = nil,
        mlName       = nil,    -- (Raider side only)
        qualityFilter = nil,
    }, Session)
end

function Session:IsML()     return self.role == "MasterLooter" end
function Session:IsRaider() return self.role == "Raider"       end

function Session:GetItem(itemKey) return self.items[itemKey] end

function Session:GetCurrentRollingItem()
    if self.currentRoll then return self.items[self.currentRoll] end
    return nil
end

function Session:GetActiveItems(minQuality)
    local list = {}
    for _, item in pairs(self.items) do
        if not item:IsDone() then
            if not minQuality or not item.infoLoaded
                or item.quality >= minQuality
                or item:RollCount() > 0
                or item.wasRolled
                or item.srHolders
            then
                table.insert(list, item)
            end
        end
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

function Session:GetDoneItems()
    local list = {}
    for _, item in pairs(self.items) do
        if item:IsDone() then table.insert(list, item) end
    end
    table.sort(list, function(a, b) return a.slot > b.slot end)
    return list
end

function Session:GetActiveItemCount()
    local n = 0
    for _, item in pairs(self.items) do
        if not item:IsDone() then n = n + 1 end
    end
    return n
end

function Session:ClearDone()
    for key, item in pairs(self.items) do
        if item:IsDone() then self.items[key] = nil end
    end
end

-- ============================================================
-- ---- MasterLoot module ----
-- ============================================================

local MasterLoot = {}
NofoxyML    = MasterLoot

MasterLoot.session      = nil
MasterLoot.lootMethod   = nil
MasterLoot.rollDuration = 30
MasterLoot.rollTimer    = nil
MasterLoot.pendingAward = {}   -- { [itemKey] = playerName } manual dropdown override

MasterLoot.pendingItemInfo   = {}
MasterLoot.pendingRetryTimer = nil

MasterLoot.msgThrottle  = 0.1
MasterLoot.lastMsgTime  = 0
MasterLoot.pendingMsgs  = {}
MasterLoot.sendTimer    = nil

MasterLoot.tradeState = nil

function MasterLoot:IsActive() return self.session ~= nil end
function MasterLoot:IsML()     return self.session ~= nil and self.session:IsML() end
function MasterLoot:IsRaider() return self.session ~= nil and self.session:IsRaider() end
function MasterLoot:GetRole()  return self.session and self.session.role or nil end

-- ============================================================
-- ---- Role resolution ----
-- ============================================================

local function DetectLootMethod()
    return GetLootMethod()
end

local function DetectIsML()
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end

    local myName = UnitName("player")
    if raidMaster then
        local mlName = GetRaidRosterInfo(raidMaster)
        return NormalizeName(mlName) == NormalizeName(myName)
    end
    return partyMaster == 0
end

function MasterLoot:ResolveRole()
    local method = DetectLootMethod()
    self.lootMethod = method

    if method ~= "master" then
        self.session = nil
        return
    end

    local role = DetectIsML() and "MasterLooter" or "Raider"

    if self.session then
        self.session.role = role
    else
        self.session = Session.new(role)
    end

    if Nofoxy.db and Nofoxy.db.debug then
        Nofoxy:Print(string.format("[ML] ResolveRole: method=%s role=%s", method, role))
    end
end

function MasterLoot:Initialize()
    self:ResolveRole()
end

-- ============================================================
-- ---- Event: PARTY_LOOT_METHOD_CHANGED ----
-- ============================================================

function MasterLoot:OnLootMethodChanged()
    local wasActive = self:IsActive()
    local wasML     = self:IsML()

    if wasML and DetectLootMethod() ~= "master" then
        self:SendMessage("CLEAR")
    end
    if DetectLootMethod() ~= "master" then
        self.session = nil
    end

    self:ResolveRole()

    local nowActive = self:IsActive()
    if wasActive ~= nowActive and NofoxyUI and NofoxyUI.Refresh then
        NofoxyUI:Refresh()
    end
end

-- ============================================================
-- ---- Event: LOOT_OPENED ----
-- ============================================================

function MasterLoot:OnLootOpened()
    self:ResolveRole()
    if not self:IsActive() then return end
    if not self:IsML() then return end  -- Raiders only receive via addon messages

    local numItems = GetNumLootItems()
    if numItems == 0 then return end

    local corpseGUID = UnitGUID("target") or "0"
    local guidPrefix = corpseGUID .. ":"

    -- Snapshot the current roster once for SR validity checks. Keyed by
    -- normalized name so casing/realm-suffix differences between the
    -- softres.it export and what WoW's roster APIs return don't cause a
    -- reservation to silently fail to match.
    local rosterSet = {}   -- normalizedName -> canonical in-game name
    for _, entry in ipairs(self:GetRaidRoster()) do
        rosterSet[NormalizeName(entry.name)] = entry.name
    end

    local newItems = {}
    for i = 1, numItems do
        local texture, name, quantity, quality = GetLootSlotInfo(i)
        local link = GetLootSlotLink(i)
        if name and link then
            local itemID  = tonumber(string.match(link, "item:(%d+)"))
            local itemKey = guidPrefix .. (itemID or "0")
            local existing = self.session.items[itemKey]

            if existing then
                -- We've seen this item before on this same corpse (the loot
                -- window was closed and reopened). If a winner was already
                -- decided (roll finished while the window was closed), finish
                -- delivering it now, straight from the loot window — no trade
                -- needed. This is just completing something already decided,
                -- not a fresh auto-trigger — Soft-Reserved items that haven't
                -- been Award/Roll-clicked yet are deliberately left alone here.
                if existing.winner and not existing:IsDone() then
                    local err = self:AwardToWinner(itemKey, existing.winner)
                    if not err then
                        Nofoxy:PrintQuiet("Corpse reopened — finished pending award: " .. existing.winner ..
                            " gets " .. (existing.link ~= "" and existing.link or existing.name))
                    end
                elseif not existing:IsDone() and not existing.heldByML and not existing:IsRolling()
                    and (Nofoxy.db == nil or Nofoxy.db.secureRollingItems ~= false) then
                    -- Safety-net retry: this item should have been secured to
                    -- our bags on the first pass but wasn't (e.g. bags were
                    -- full at the time) — try again now that the window's open.
                    self:SecureItemToSelf(existing)
                end

            else
                -- ---- 1. Soft-reserve check (highest priority — never auto-loot a reserved item) ----
                local reservers = itemID and NofoxySR:GetReservers(itemID)
                local validHolders = {}
                if reservers then
                    for _, h in ipairs(reservers) do
                        -- Use the roster's canonical spelling/casing, not the
                        -- CSV's, so later roll-result matching (which comes
                        -- from real WoW name strings) lines up exactly.
                        local canonical = rosterSet[NormalizeName(h.name)]
                        if canonical then table.insert(validHolders, canonical) end
                    end
                end

                if #validHolders > 0 then
                    local item = Item.new(itemKey, link, texture, quality, name, i)
                    item.quantity   = quantity or 1
                    item.srHolders  = validHolders
                    self.session.items[itemKey] = item
                    newItems[itemKey] = item
                    -- Deliberately NOT auto-announcing/auto-rolling/auto-awarding
                    -- here — the item just shows up tagged as reserved, and sits
                    -- there until the ML clicks Award (1 reserver) or Roll (2+)
                    -- on the Master Loot tab. See HandleSoftReserve/AnnounceSR,
                    -- which is now only ever triggered by that manual click.

                -- ---- 2. Auto-loot check (trash / below-threshold, not reserved) ----
                elseif NofoxyAL:ShouldAutoLoot(quality, link) then
                    NofoxyAL:GiveToSelf(i, link)

                -- ---- 3. Normal manual item ----
                else
                    local item = Item.new(itemKey, link, texture, quality, name, i)
                    item.quantity = quantity or 1
                    self.session.items[itemKey] = item
                    newItems[itemKey] = item
                end
            end
        end
    end

    for _, item in pairs(newItems) do
        self:SendMessage(self:SerializeItem(item))
        if item.srHolders then
            local msg = "SR" .. SEP .. item.itemKey
            for _, n in ipairs(item.srHolders) do msg = msg .. SEP .. n end
            self:SendMessage(msg)
        end
    end

    -- Secure anything that's still unresolved (rolling, or a failed
    -- instant Soft-Reserve award) into the ML's own bags right now, while
    -- this loot window is still guaranteed open. Without this, an item
    -- that takes the full roll duration to resolve can end up impossible
    -- to award at all once the corpse/loot window is gone. Off by choice
    -- (Options → Roll Settings) if you'd rather keep items in the loot
    -- window and babysit it until rolls finish — fine for boss loot where
    -- you're usually standing still anyway, riskier for fast trash farming.
    local unresolvedCount = 0
    for _, item in pairs(newItems) do
        if not item:IsDone() then unresolvedCount = unresolvedCount + 1 end
    end
    if Nofoxy.db == nil or Nofoxy.db.secureRollingItems ~= false then
        for _, item in pairs(newItems) do
            if not item:IsDone() then
                self:SecureItemToSelf(item)
            end
        end
    elseif unresolvedCount > 0 and Nofoxy.db and Nofoxy.db.debug then
        Nofoxy:Print("Auto-Secure is OFF — " .. unresolvedCount ..
            " item(s) will stay in the loot window while rolling. Keep this window open until the roll ends, " ..
            "or turn Auto-Secure back on in Options → Roll Settings.")
    end

    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function MasterLoot:OnLootClosed()
    -- Items persist after loot window closes; rolls continue.
end

-- ============================================================
-- ---- Soft-reserve handling (ML side, called from OnLootOpened) ----
-- ============================================================

function MasterLoot:HandleSoftReserve(item, slot)
    local holders = item.srHolders

    if #holders == 1 then
        SendAnnounce(string.format(">> %s is Soft-Reserved by %s — awarding.",
            item.link ~= "" and item.link or item.name, holders[1]))
        local err = self:AwardToWinner(item.itemKey, holders[1])
        if err then
            local msgs = {
                ERR_NOT_CANDIDATE  = holders[1] .. " is not a valid loot candidate.",
                ERR_ITEM_NOT_FOUND = "Item not found in loot window or bags.",
                ERR_NOT_IN_GROUP   = holders[1] .. " is not in your group.",
                ERR_OUT_OF_RANGE   = "Move closer to " .. holders[1] .. ".",
            }
            Nofoxy:Print("|cffff6040[SR]|r Auto-award failed: " .. (msgs[err] or err) .. " — award manually.")
        end
    else
        local names = table.concat(holders, ", ")
        SendAnnounce(string.format(">> %s is reserved by %d players (%s) — rolling now! (%ds)",
            item.link ~= "" and item.link or item.name, #holders, names, self.rollDuration))
        self:StartSRRoll(item.itemKey, holders)
    end
end

-- This is the ML's Award/Roll button handler for Soft-Reserved items — the
-- ONLY thing that ever triggers an SR announcement, roll, or award. Nothing
-- about Soft Reserves happens automatically anymore; the item just sits
-- tagged and idle until this is called. One reserver announces + awards
-- immediately; two or more announces + starts a restricted roll. Also
-- doubles as a manual retry if a previous attempt failed (wrong candidate,
-- out of trade range, etc.) — safe to call again on an idle item.
function MasterLoot:AnnounceSR(itemKey)
    if not self:IsML() then return end
    local item = self.session and self.session:GetItem(itemKey)
    if not item or not item.srHolders or #item.srHolders == 0 then return end
    if item:IsRolling() or item:IsDone() then return end
    self:HandleSoftReserve(item, item.slot)
end

-- ============================================================
-- ---- Throttled message queue ----
-- ============================================================

function MasterLoot:SendMessage(msg)
    if not self:IsML() then return end
    table.insert(self.pendingMsgs, msg)
    self:FlushQueue()
end

function MasterLoot:FlushQueue()
    if #self.pendingMsgs == 0 then return end
    if GetTime() - self.lastMsgTime < self.msgThrottle then
        if not self.sendTimer then
            self.sendTimer = CreateFrame("Frame")
            self.sendTimer:SetScript("OnUpdate", function()
                MasterLoot:FlushQueue()
            end)
        end
        self.sendTimer:Show()
        return
    end

    local msg     = table.remove(self.pendingMsgs, 1)
    local channel = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"

    SendAddonMessage("NOFOXY", msg, channel)
    self.lastMsgTime = GetTime()

    if #self.pendingMsgs == 0 and self.sendTimer then
        self.sendTimer:Hide()
    end
end

-- ============================================================
-- ---- Protocol serialization ----
-- ============================================================

function MasterLoot:SerializeItem(item)
    return "ITEM" .. SEP .. item.itemKey .. SEP .. item.link
end

local function ParseItemQuality(link)
    if not link or link == "" then return nil end
    local color = string.match(link, "^|cff(%x%x%x%x%x%x)")
    if not color then return nil end
    color = color:lower()
    local map = {
        ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
        ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
    }
    return map[color]
end

local function ParseItemName(link)
    return string.match(link or "", "%[(.+)%]")
end

function MasterLoot:DeserializeItem(message)
    local parts = SplitBySep(message)
    if #parts < 2 or parts[1] ~= "ITEM" then return nil end
    local itemKey  = parts[2]
    local itemLink = parts[3] or ""
    local quality  = ParseItemQuality(itemLink) or 2
    local name     = ParseItemName(itemLink) or "Unknown"
    return Item.new(itemKey, itemLink, "", quality, name, 0)
end

-- ============================================================
-- ---- Addon message receiver (Raider side) ----
-- ============================================================

function MasterLoot:OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= "NOFOXY" then return end
    if self:IsML() then return end  -- ML ignores own broadcasts

    if not self.session then
        self:ResolveRole()
        if not self.session then return end
    end

    local parts = SplitBySep(message)
    local kind  = parts[1]

    if kind == "ITEM" then
        if not self.session.mlName then
            self.session.mlName = sender
        end

        local item = self:DeserializeItem(message)
        if not item then return end
        if self.session.items[item.itemKey] then return end

        local itemID = item.link and tonumber(string.match(item.link, "item:(%d+)"))
        local texture
        if itemID then
            texture = select(10, GetItemInfo(itemID))
        end
        item.texture = texture or ""

        if item.texture == "" and itemID then
            self.pendingItemInfo[itemID] = self.pendingItemInfo[itemID] or {}
            self.pendingItemInfo[itemID][item.itemKey] = true
            self:StartPendingRetry()
        end

        self.session.items[item.itemKey] = item

    elseif kind == "SR" then
        local itemKey = parts[2]
        local item = self.session:GetItem(itemKey)
        if item then
            item.srHolders = {}
            for i = 3, #parts do table.insert(item.srHolders, parts[i]) end
        end

    elseif kind == "ROLL_START" then
        local itemKey = parts[2]
        local rollKind = parts[3]
        local item = self.session:GetItem(itemKey)
        if item then
            item.rolling   = true
            item.rollStart = GetTime()
            item.rolls     = {}
            item.rerolls   = {}
            item.wasRolled = true
            item.eligiblePlayers = nil
            if rollKind == "sr" or rollKind == "tie" then
                item.eligiblePlayers = {}
                for i = 4, #parts do item.eligiblePlayers[parts[i]] = true end
            end
            self.session.currentRoll = itemKey
        end

    elseif kind == "ROLL_END" then
        local itemKey = parts[2]
        local winner  = parts[3]
        local item = self.session:GetItem(itemKey)
        if item then
            item.rolling   = false
            item.rollStart = nil
            item.winner    = (winner and winner ~= "none") and winner or nil
        end
        self.session.currentRoll = nil

    elseif kind == "ITEM_DONE" then
        local itemKey = parts[2]
        local item = self.session:GetItem(itemKey)
        if item then item.isDone = true end

    elseif kind == "FILTER" then
        local val = tonumber(parts[2])
        if val ~= nil then self.session.qualityFilter = val end

    elseif message == "CLEAR" then
        self.session = nil
    end

    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

-- ============================================================
-- ---- GET_ITEM_INFO_RECEIVED handler (Raider side) ----
-- ============================================================

function MasterLoot:OnItemInfoReceived(itemID)
    local pending = self.pendingItemInfo[itemID]
    if not pending then return end

    local texture = select(10, GetItemInfo(itemID))
    if not texture then return end

    for itemKey in pairs(pending) do
        local item = self.session and self.session:GetItem(itemKey)
        if item and item.texture == "" then
            item.texture = texture
        end
    end
    self.pendingItemInfo[itemID] = nil

    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function MasterLoot:StartPendingRetry()
    if self.pendingRetryTimer then return end
    self.pendingRetryTimer = CreateFrame("Frame")
    self.pendingRetryTimer.elapsed = 0
    self.pendingRetryTimer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 1 then return end
        self.elapsed = 0
        MasterLoot:RetryPendingItemInfo()
    end)
    self.pendingRetryTimer:Show()
end

function MasterLoot:RetryPendingItemInfo()
    if not next(self.pendingItemInfo) then
        if self.pendingRetryTimer then
            self.pendingRetryTimer:Hide()
            self.pendingRetryTimer = nil
        end
        return
    end

    local resolved = {}
    for itemID, pending in pairs(self.pendingItemInfo) do
        local texture = select(10, GetItemInfo(itemID))
        if texture then
            for itemKey in pairs(pending) do
                local item = self.session and self.session:GetItem(itemKey)
                if item and item.texture == "" then
                    item.texture = texture
                end
            end
            resolved[itemID] = true
        end
    end
    for itemID in pairs(resolved) do
        self.pendingItemInfo[itemID] = nil
    end

    if next(resolved) and NofoxyUI and NofoxyUI.Refresh then
        NofoxyUI:Refresh()
    end
    if not next(self.pendingItemInfo) and self.pendingRetryTimer then
        self.pendingRetryTimer:Hide()
        self.pendingRetryTimer = nil
    end
end

-- ============================================================
-- ---- Quality filter ----
-- ============================================================

function MasterLoot:GetFilterThreshold()
    if self.session and self.session.qualityFilter ~= nil then
        return self.session.qualityFilter
    end
    return Nofoxy.db and Nofoxy.db.qualityFilter or 2
end

function MasterLoot:BroadcastFilter()
    if not self:IsML() then return end
    self:SendMessage("FILTER" .. SEP .. tostring(self:GetFilterThreshold()))
end

-- ============================================================
-- ---- Roll management (ML side) — manual, open rolls ----
-- ============================================================

function MasterLoot:StartRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or item:IsDone() or item:IsRolling() then return end

    if self.rollTimer then self.rollTimer:Hide() end
    if self.pendingAward then self.pendingAward[itemKey] = nil end

    item.rolling   = true
    item.rollStart = GetTime()
    item.rolls     = {}
    item.rerolls   = {}
    item.winner    = nil
    item.eligiblePlayers = nil
    item.wasRolled = true
    item.autoAward = false
    self.session.currentRoll = itemKey

    SendAnnounce(">> Rolling for: " .. (item.link ~= "" and item.link or item.name) ..
                 " — /roll now! (" .. self.rollDuration .. "s)")

    self:SendMessage("ROLL_START" .. SEP .. itemKey .. SEP .. "open")
    self.rollTimer = self:CreateTimer(itemKey)

    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

-- Automatic roll restricted to soft-reserve holders. Winner is auto-awarded.
function MasterLoot:StartSRRoll(itemKey, holderNames)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item then return end

    if self.rollTimer then self.rollTimer:Hide() end

    item.rolling   = true
    item.rollStart = GetTime()
    item.rolls     = {}
    item.rerolls   = {}
    item.winner    = nil
    item.wasRolled = true
    item.autoAward = true
    item.eligiblePlayers = {}
    for _, n in ipairs(holderNames) do item.eligiblePlayers[n] = true end
    self.session.currentRoll = itemKey

    local msg = "ROLL_START" .. SEP .. itemKey .. SEP .. "sr"
    for _, n in ipairs(holderNames) do msg = msg .. SEP .. n end
    self:SendMessage(msg)

    self.rollTimer = self:CreateTimer(itemKey)
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function MasterLoot:EndRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or not item:IsRolling() then return end

    item.rolling   = false
    item.rollStart = nil
    self.session.currentRoll = nil
    self.rollTimer           = nil

    local tied = item:GetTiedWinners()
    if tied then
        item.winner = nil
        local tieStr = table.concat(tied.names, " & ")
        if item.autoAward then
            SendAnnounce(">> Tie at " .. tied.value .. "! " .. tieStr .. " — rolling again...")
        else
            SendAnnounce(">> Tie at " .. tied.value .. "! " .. tieStr .. " — ML can re-roll")
        end
        self:SendMessage("ROLL_END" .. SEP .. itemKey .. SEP .. "none")

        if item.autoAward then
            self:StartReRoll(itemKey)
            return
        end
    else
        local winner, winValue = item:GetWinner()
        item.winner = winner

        if winner then
            SendAnnounce(">> " .. winner .. " wins " .. (item.link ~= "" and item.link or item.name) ..
                         " with " .. winValue .. "!")
        else
            Nofoxy:PrintQuiet("No rolls for " .. (item.link ~= "" and item.link or item.name))
        end

        self:SendMessage("ROLL_END" .. SEP .. itemKey .. SEP .. (winner or "none"))

        if winner and item.autoAward then
            local err = self:AwardToWinner(itemKey, winner)
            if err then
                Nofoxy:Print("|cffff6040[Award]|r Auto-award failed for " .. winner ..
                    " (" .. err .. ") — award manually.")
            end
        end
    end
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function MasterLoot:CancelRoll()
    if not self:IsML() then return end
    local itemKey = self.session and self.session.currentRoll
    if not itemKey then return end
    local item = self.session:GetItem(itemKey)
    if item then
        item.rolling   = false
        item.rollStart = nil
    end
    self.session.currentRoll = nil
    if self.rollTimer then
        self.rollTimer:Hide()
        self.rollTimer = nil
    end
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

-- Tie-break re-roll. Preserves item.autoAward so SR ties keep resolving
-- automatically; manual-item ties stay manual (ML clicked Re-roll).
function MasterLoot:StartReRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or not item:IsTied() then return end

    if self.rollTimer then self.rollTimer:Hide() end

    item:ResetForReroll()
    item.rolling   = true
    item.rollStart = GetTime()
    item.rolls     = {}
    item.rerolls   = {}
    self.session.currentRoll = itemKey

    local names = {}
    for name in pairs(item.eligiblePlayers) do table.insert(names, name) end
    local tieStr = table.concat(names, " & ")

    SendAnnounce(">> Tie re-roll! Only " .. tieStr .. " — /roll now! (" .. self.rollDuration .. "s)")

    local msg = "ROLL_START" .. SEP .. itemKey .. SEP .. "tie"
    for _, name in ipairs(names) do msg = msg .. SEP .. name end
    self:SendMessage(msg)

    self.rollTimer = self:CreateTimer(itemKey)
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function MasterLoot:ToggleDone(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item then return end
    item.isDone = not item.isDone
    self:SendMessage("ITEM_DONE" .. SEP .. itemKey)
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

-- ============================================================
-- ---- Roll recording (fed by Parser on CHAT_MSG_SYSTEM) ----
-- ============================================================

function MasterLoot:RecordRoll(playerName, value)
    if not self.session then return end
    local item = self.session:GetCurrentRollingItem()
    if not item then return end

    local result = item:RecordRoll(playerName, value)
    if result == "ok" and NofoxyUI and NofoxyUI.Refresh then
        NofoxyUI:Refresh()
    end
end

-- ============================================================
-- ---- Timer (ML side) ----
-- ============================================================

function MasterLoot:CreateTimer(itemKey)
    local timer = CreateFrame("Frame")
    timer.itemKey = itemKey
    timer.elapsed = 0
    timer:Show()
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 1 then return end
        self.elapsed = 0
        local session = MasterLoot.session
        if not session then self:Hide(); return end
        local item = session:GetItem(self.itemKey)
        if item and item:IsRolling() then
            local remaining = MasterLoot.rollDuration - (GetTime() - item.rollStart)
            if remaining <= 0 then
                MasterLoot:EndRoll(self.itemKey)
            end
        else
            self:Hide()
        end
    end)
    return timer
end

function MasterLoot:ClearDone()
    if not self.session then return end
    self.session:ClearDone()
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

function MasterLoot:GetSession() return self.session end

function MasterLoot:GetActiveItemCount()
    if not self.session then return 0 end
    return self.session:GetActiveItemCount()
end

-- ============================================================
-- ---- Award to winner ----
-- ============================================================

function MasterLoot:GetRaidRoster()
    local list = {}
    local myName = UnitName("player")
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, cls = GetRaidRosterInfo(i)
            if name then table.insert(list, { name = name, class = cls or "WARRIOR" }) end
        end
    else
        table.insert(list, { name = myName, class = select(2, UnitClass("player")) or "WARRIOR" })
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local n = UnitName(unit)
            if n then
                local _, cls = UnitClass(unit)
                table.insert(list, { name = n, class = cls or "WARRIOR" })
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function MasterLoot:FindRaidUnit(playerName)
    local target = NormalizeName(playerName)
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if NormalizeName(UnitName(unit)) == target then return unit end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            if NormalizeName(UnitName(unit)) == target then return unit end
        end
    end
    return nil
end

function MasterLoot:FindCandidateIndex(playerName)
    local target = NormalizeName(playerName)
    for i = 1, 40 do
        local name = GetMasterLootCandidate(i)
        if NormalizeName(name) == target then return i end
    end
    return nil
end

-- Pulls an item that's about to sit unresolved for a while (rolling, or a
-- failed instant Soft-Reserve award) straight into the Master Looter's own
-- bags, WHILE the loot window is still guaranteed open. This is the fix for
-- "the corpse/loot window is gone by the time the roll ends" — once secured
-- here, AwardToWinner can always fall back to trade later, no matter how
-- long the roll takes or how much the ML moves around/fights other mobs in
-- the meantime. Looks the item up fresh by link (not a stored slot index),
-- so it's safe even if other slots on the same corpse shifted already.
function MasterLoot:SecureItemToSelf(item)
    if item.heldByML or item:IsDone() then return false end
    -- Deliberately NOT checking the LootFrame UI object here — some clients
    -- (custom loot UIs, some private-server cores) don't expose it the same
    -- way, or at all. GetNumLootItems() reflects the actual loot session
    -- state directly and works regardless of what's drawing the window.
    if GetNumLootItems() == 0 then return false end

    local lootSlot
    for i = 1, GetNumLootItems() do
        if GetLootSlotLink(i) == item.link then
            lootSlot = i
            break
        end
    end
    if not lootSlot then
        Nofoxy:Print("|cffff6040[Secure]|r Couldn't find " .. (item.link ~= "" and item.link or item.name) ..
            " still in the loot window to secure it — it may have already been taken another way.")
        return false
    end

    local myIndex = self:FindCandidateIndex(UnitName("player"))
    if not myIndex then
        Nofoxy:Print("|cffff6040[Secure]|r Couldn't find you (" .. UnitName("player") ..
            ") as a valid loot candidate for " .. (item.link ~= "" and item.link or item.name) ..
            " — it's staying in the loot window instead. Award it directly while the window's still open, or toggle off Auto-Secure in Options.")
        return false
    end

    GiveMasterLoot(lootSlot, myIndex)
    item.heldByML = true
    if Nofoxy.db and Nofoxy.db.debug then
        Nofoxy:Print("|cff33ccff[Secure]|r " .. (item.link ~= "" and item.link or item.name) .. " → your bags (roll pending).")
    end
    return true
end

function MasterLoot:FindItemInBags(itemLink)
    if not itemLink or itemLink == "" then return nil end
    -- Match by item ID rather than the exact link string — link text from
    -- bags (GetContainerItemLink) can format slightly differently than the
    -- version captured from the loot window, even for the same item.
    local wantID = tonumber(string.match(itemLink, "item:(%d+)"))
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                if link == itemLink then return bag, slot end
                if wantID then
                    local gotID = tonumber(string.match(link, "item:(%d+)"))
                    if gotID and gotID == wantID then return bag, slot end
                end
            end
        end
    end
    return nil
end

function MasterLoot:AwardToWinner(itemKey, playerName)
    if not self:IsML() then return "ERR_NOT_ML" end
    local item = self.session and self.session:GetItem(itemKey)
    if not item then return "ERR_NO_ITEM" end

    local wantID = tonumber(string.match(item.link or "", "item:(%d+)"))
    -- Deliberately NOT using LootFrame:IsShown() — some clients don't
    -- expose that object the same way (or at all), which silently broke
    -- this check completely. GetNumLootItems() reflects the actual loot
    -- session state and works regardless of what UI is drawing it.
    local numLootItems = GetNumLootItems()
    local sessionActive = numLootItems > 0
    local dbg = Nofoxy.db and Nofoxy.db.debug

    if dbg then
        Nofoxy:Print(string.format(
            "|cff888888[Award debug]|r target=%s active loot session=%s numLootItems=%d",
            item.link ~= "" and item.link or item.name, tostring(sessionActive), numLootItems))
    end

    -- ---- Scenario 1: loot session is active ----
    if sessionActive then
        local lootSlot
        for i = 1, GetNumLootItems() do
            local slotLink = GetLootSlotLink(i)
            local match = false
            if slotLink then
                if slotLink == item.link then
                    match = true
                elseif wantID then
                    local gotID = tonumber(string.match(slotLink, "item:(%d+)"))
                    match = gotID and gotID == wantID
                end
            end
            if dbg then
                Nofoxy:Print(string.format("|cff888888[Award debug]|r slot %d: %s%s",
                    i, slotLink or "(empty)", match and "  <-- MATCH" or ""))
            end
            if match then
                lootSlot = i
                break
            end
        end
        if lootSlot then
            local candidateIdx = self:FindCandidateIndex(playerName)
            if not candidateIdx then return "ERR_NOT_CANDIDATE" end
            GiveMasterLoot(lootSlot, candidateIdx)
            item.isDone = true
            item.winner = playerName
            self:SendMessage("ITEM_DONE" .. SEP .. item.itemKey)
            self:ConsumeSoftReserve(item, playerName)
            if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
            return nil
        end
        -- Not in the loot window (already looted) — fall through to bag search
    end

    -- ---- Scenario 2: item already in ML's own bags ----
    local bag, slot = self:FindItemInBags(item.link)
    if dbg then
        Nofoxy:Print(string.format("|cff888888[Award debug]|r not in loot window — bag search: %s",
            bag and ("found in bag " .. bag .. " slot " .. slot) or "not found"))
    end
    if not bag then return "ERR_ITEM_NOT_FOUND" end

    -- Winner IS the Master Looter (very common — the ML rolls on their own
    -- items too) and the item is already sitting in their bags (secured
    -- earlier, or picked up some other way). There's nothing left to do —
    -- it's already exactly where it needs to be. Trading with yourself
    -- isn't something WoW supports, so this must be handled separately
    -- instead of falling into the trade path below, which could never work.
    if NormalizeName(playerName) == NormalizeName(UnitName("player")) then
        item.isDone = true
        item.winner = playerName
        self:SendMessage("ITEM_DONE" .. SEP .. item.itemKey)
        self:ConsumeSoftReserve(item, playerName)
        if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
        return nil
    end

    local unit = self:FindRaidUnit(playerName)
    if not unit then return "ERR_NOT_IN_GROUP" end
    if not CheckInteractDistance(unit, 2) then
        return "ERR_OUT_OF_RANGE"
    end
    self:StartTradeSequence(playerName, unit, bag, slot)
    self:ConsumeSoftReserve(item, playerName)
    return nil
end

-- Clears this player's Soft Reserve entry for the awarded item, if it had
-- one, so a duplicate drop later in the raid isn't flagged as reserved for
-- them again. Anyone ELSE who also reserved the same item keeps their
-- reservation for the next copy that drops.
function MasterLoot:ConsumeSoftReserve(item, playerName)
    if not item.srHolders or #item.srHolders == 0 then return end
    local itemID = tonumber(string.match(item.link or "", "item:(%d+)"))
    if not itemID then return end
    NofoxySR:RemoveHolder(itemID, playerName)
    if Nofoxy.db and Nofoxy.db.debug then
        Nofoxy:Print(string.format("[SR] Cleared %s's reservation on %s.", playerName, item.name))
    end
end

function MasterLoot:StartTradeSequence(playerName, unit, bag, slot)
    self.tradeState = { winner = playerName, bag = bag, slot = slot }
    InitiateTrade(unit)
end

function MasterLoot:OnTradeShow()
    if not self.tradeState then return end
    local ts = self.tradeState
    UseContainerItem(ts.bag, ts.slot)
end

function MasterLoot:OnTradeClosed()
    if not self.tradeState then return end
    self.tradeState = nil
    if NofoxyUI and NofoxyUI.Refresh then NofoxyUI:Refresh() end
end

-- ============================================================
-- ---- Add a bag item to the Master Loot tab ----
-- ============================================================
-- For items that never came through a live loot window at all — crafted,
-- pulled from the bank, or something Auto-Loot already swept into your
-- bags that you've now decided is worth a proper roll after all. Since
-- the item is already sitting in your bags, it's marked heldByML from the
-- start, so awarding it always goes straight to the trade path — there's
-- no loot window for it to ever come from.
function MasterLoot:AddBagItemToRoll(itemLink)
    if not itemLink or itemLink == "" or not string.find(itemLink, "item:") then
        Nofoxy:Print("|cffff6040[Nofoxy]|r Usage: /nfx roll <shift-click the item> — " ..
            "type the command, then shift-click the item from your bags into the same line before pressing Enter.")
        return
    end

    -- Force a MasterLooter session if we don't already have one — this is
    -- meant to work even with no corpse/loot window open at all.
    if not self.session or not self.session:IsML() then
        self.session = Session.new("MasterLooter")
    end

    local bag, slot = self:FindItemInBags(itemLink)
    if not bag then
        Nofoxy:Print("|cffff6040[Nofoxy]|r Couldn't find " .. itemLink .. " in your bags.")
        return
    end

    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemLink)
    if not name then
        -- Not cached yet — fall back to what the bag slot itself can tell us.
        name    = string.match(itemLink, "%[(.+)%]") or "Unknown Item"
        link    = itemLink
        quality = 1
        texture = select(10, GetContainerItemInfo(bag, slot))
    end

    local itemKey = "Bag-" .. UnitName("player") .. ":" .. (itemID or "0") .. ":" .. tostring(GetTime())
    local item = Item.new(itemKey, link, texture or "", quality or 1, name, 0)
    item.heldByML = true  -- already in bags — AwardToWinner will use the trade path
    self.session.items[itemKey] = item

    Nofoxy:Print("Added " .. link .. " to the Master Loot tab — click Start Roll when ready.")
    if NofoxyUI and NofoxyUI.SwitchTab then NofoxyUI:SwitchTab("master") end
    if NofoxyUI and NofoxyUI.Refresh   then NofoxyUI:Refresh() end
end

-- ============================================================
-- ---- The Ashkandi Prank ----
-- ============================================================
-- Starts a completely real Master Loot roll for Ashkandi, Greatsword of
-- the Brotherhood (item 19364, epic, Nefarian/BWL) — sent through the
-- exact same StartRoll path as a genuine drop, so the announcement goes
-- out to real raid/party chat and looks 100% legitimate to anyone who
-- doesn't know better. Forces a MasterLooter session if you don't already
-- have one (like /nfx test), so this works even solo for a screenshot.
-- Any actual Award attempt fails gracefully (ERR_ITEM_NOT_FOUND) since
-- there's no real item behind the fake link — don't actually give anyone
-- anything, this is just for the announcement/roll spectacle.
function MasterLoot:InjectAshkandiTroll()
    if not self.session or not self.session:IsML() then
        self.session = Session.new("MasterLooter")
    end

    local GUID = "Creature-0-TROLL-NEFARIAN-00001"
    local itemKey = GUID .. ":19364"

    local item = Item.new(itemKey,
        "|cffa335ee|Hitem:19364:0:0:0:0:0:0:0:0|h[Ashkandi, Greatsword of the Brotherhood]|h|r",
        "Interface\\Icons\\INV_Sword_50", 4, "Ashkandi, Greatsword of the Brotherhood", 1)
    self.session.items[itemKey] = item

    Nofoxy:Print("[TROLL] Rolling for Ashkandi — enjoy the chaos.")
    self:StartRoll(itemKey)

    if NofoxyUI and NofoxyUI.SwitchTab then NofoxyUI:SwitchTab("master") end
    if NofoxyUI and NofoxyUI.Refresh   then NofoxyUI:Refresh() end
end

-- ============================================================
-- ---- Test data injection ----
-- ============================================================

function MasterLoot:InjectTestRolls()
    self.session = Session.new("MasterLooter")
    local now  = GetTime()
    local GUID = "Creature-0-TEST-TEST-00001"

    local i1 = Item.new(GUID .. ":16959",
        "|cffa335ee|Hitem:16959:0:0:0:0:0:0:0:0|h[Bracelets of Wrath]|h|r",
        "Interface\\Icons\\INV_Bracer_04", 4, "Bracelets of Wrath", 1)
    i1.rolling = true
    i1.rollStart = now
    i1.wasRolled = true
    i1.autoAward = true
    i1.srHolders = { "Devincy" }
    i1.eligiblePlayers = { Devincy = true }
    i1.rolls = { Devincy = { value = 87, time = now } }

    local i2 = Item.new(GUID .. ":19347",
        "|cffa335ee|Hitem:19347:0:0:0:0:0:0:0:0|h[Claw of Chromaggus]|h|r",
        "Interface\\Icons\\INV_Misc_MonsterClaw_04", 4, "Claw of Chromaggus", 2)
    i2.wasRolled = true
    i2.autoAward = true
    i2.srHolders = { "Fenzhul", "Nikuriu" }
    i2.rolling = true
    i2.rollStart = now
    i2.eligiblePlayers = { Fenzhul = true, Nikuriu = true }
    i2.rolls = { Fenzhul = { value = 62, time = now } }

    local i3 = Item.new(GUID .. ":19438",
        "|cff0070dd|Hitem:19438:0:0:0:0:0:0:0:0|h[Ringo's Blizzard Boots]|h|r",
        "Interface\\Icons\\INV_Boots_08", 3, "Ringo's Blizzard Boots", 3)

    self.session.items = {
        [GUID .. ":16959"] = i1,
        [GUID .. ":19347"] = i2,
        [GUID .. ":19438"] = i3,
    }
    self.session.currentRoll = GUID .. ":19347"

    Nofoxy:Print("Test data injected — SR auto-award, SR contested roll, and one manual item.")
    if NofoxyUI and NofoxyUI.SwitchTab then NofoxyUI:SwitchTab("master") end
    if NofoxyUI and NofoxyUI.Refresh   then NofoxyUI:Refresh() end
end

-- ============================================================
-- ---- Soft-Reserve end-to-end test ----
-- ============================================================
-- Seeds a small Soft Reserve list into NofoxySR (so the Soft Reserves
-- tab shows real content) and then calls HandleSoftReserve directly for
-- three fake items — exactly what happens when you click the Award/Roll
-- button on a real reserved item, just triggered by this command instead
-- of a click, so you can preview the flow without a real corpse or group.
--
-- Item 1: single holder  → instant announce + award attempt.
-- Item 2: two holders    → stays LIVE and rolling, with one fake roll
--                          already in, so you can see the eligible names,
--                          the timer, and the partial roll list while it's
--                          still in progress.
-- Item 3: two holders    → also stays LIVE and rolling, empty, so you can
--                          click "Roll!" yourself and watch it resolve.
--
-- The one "award" attempt will fail gracefully with ERR_ITEM_NOT_FOUND
-- since there's no real loot window or bag item behind the fake link —
-- that's expected; everything up to the actual GiveMasterLoot call is real.
function MasterLoot:InjectSRTest()
    local sampleCSV = table.concat({
        "Item Name,Item ID,From,Raider Name,Raider Class,Raider Spec,Raider Note,Extra Reserves,Date",
        "Bracelets of Wrath,16959,Razorgore the Untamed,Devincy,Warrior,Protection,,0,2026-09-23 23:03:25",
        "Claw of Chromaggus,19347,Chromaggus,Fenzhul,Mage,Fire,,0,2026-09-25 11:54:16",
        "Claw of Chromaggus,19347,Chromaggus,Nikuriu,Mage,Fire,Nikuriu,0,2026-09-25 18:27:30",
        "Neltharion's Tear,19379,Nefarian,Heysiri,Shaman,Restoration,,0,2026-09-25 17:02:32",
        "Neltharion's Tear,19379,Nefarian,Seniia,Shaman,Restoration,,0,2026-09-25 17:02:32",
    }, "\n")
    local n, itemCount = NofoxySR:ImportCSV(sampleCSV)
    Nofoxy:Print(string.format("[SR TEST] Seeded %d test reservation(s) across %d item(s) — check the Soft Reserves tab.", n, itemCount))

    if not self.session or not self.session:IsML() then
        self.session = Session.new("MasterLooter")
    end
    local GUID = "Creature-0-TEST-SR-00001"

    -- ---- Item 1: single holder → instant award ----
    local i1 = Item.new(GUID .. ":16959",
        "|cffa335ee|Hitem:16959:0:0:0:0:0:0:0:0|h[Bracelets of Wrath]|h|r",
        "Interface\\Icons\\INV_Bracer_04", 4, "Bracelets of Wrath", 1)
    i1.srHolders = { "Devincy" }
    self.session.items[i1.itemKey] = i1

    -- ---- Item 2: two holders → left LIVE and rolling ----
    local i2 = Item.new(GUID .. ":19347",
        "|cffa335ee|Hitem:19347:0:0:0:0:0:0:0:0|h[Claw of Chromaggus]|h|r",
        "Interface\\Icons\\INV_Misc_MonsterClaw_04", 4, "Claw of Chromaggus", 2)
    i2.srHolders = { "Fenzhul", "Nikuriu" }
    self.session.items[i2.itemKey] = i2

    -- ---- Item 3: two holders → also left LIVE, empty, for you to try ----
    local i3 = Item.new(GUID .. ":19379",
        "|cffa335ee|Hitem:19379:0:0:0:0:0:0:0:0|h[Neltharion's Tear]|h|r",
        "Interface\\Icons\\INV_Jewelry_Necklace_20", 4, "Neltharion's Tear", 3)
    i3.srHolders = { "Heysiri", "Seniia" }
    self.session.items[i3.itemKey] = i3

    Nofoxy:Print("[SR TEST] Simulating Award/Roll clicks for 3 reserved items...")

    self:HandleSoftReserve(i1, 1)   -- resolves instantly (single holder)
    self:HandleSoftReserve(i2, 2)   -- starts a live restricted roll
    self:HandleSoftReserve(i3, 3)   -- starts a second live restricted roll

    -- Simulate Fenzhul having already /rolled, so the roll list + eligible
    -- names ("Rolling (auto-award): Fenzhul & Nikuriu") are visible right
    -- away on item 2, without ending the roll — Nikuriu hasn't rolled yet,
    -- exactly like a real in-progress roll.
    i2.rolls = { Fenzhul = { value = 62, time = GetTime() } }

    if NofoxyUI and NofoxyUI.SwitchTab then NofoxyUI:SwitchTab("master") end
    if NofoxyUI and NofoxyUI.Refresh   then NofoxyUI:Refresh() end
end
