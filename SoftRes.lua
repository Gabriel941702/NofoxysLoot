-- Nofoxy SoftRes Module
-- Owns: parsing of pasted softres.it CSV / WeakAura export text, the
-- resulting reservation table, and lookups used by MasterLoot when
-- deciding whether a looted item is soft-reserved.
--
-- Data model:
--   SoftRes.reserves = {
--       [itemID] = {
--           itemName = "Bracelets of Wrath",   -- best-known display name
--           holders  = {
--               { name = "Devincy", class = "WARRIOR", note = "", spec = "Protection" },
--               ...
--           },
--       },
--   }
--
-- No UI code, no events. References Nofoxy global at call time only.

local SoftRes = {}
NofoxySR = SoftRes

SoftRes.reserves    = {}   -- [itemID] = { itemName=, holders={...} }
SoftRes.itemCount    = 0
SoftRes.reserveCount = 0
SoftRes.lastImportAt = nil
SoftRes.lastImportKind = nil  -- "softres" | "weakaura"

-- ============================================================
-- ---- CSV line parsing (RFC4180-ish: handles quoted fields with commas) ----
-- ============================================================

local function ParseCSVLine(line)
    local fields = {}
    local i = 1
    local n = #line

    while i <= n do
        if line:sub(i, i) == '"' then
            local j = i + 1
            local buf = {}
            while j <= n do
                local c = line:sub(j, j)
                if c == '"' then
                    if line:sub(j + 1, j + 1) == '"' then
                        buf[#buf + 1] = '"'
                        j = j + 2
                    else
                        j = j + 1
                        break
                    end
                else
                    buf[#buf + 1] = c
                    j = j + 1
                end
            end
            fields[#fields + 1] = table.concat(buf)
            i = j
            if line:sub(i, i) == "," then i = i + 1 end
        else
            local commaPos = line:find(",", i, true)
            if commaPos then
                fields[#fields + 1] = line:sub(i, commaPos - 1)
                i = commaPos + 1
            else
                fields[#fields + 1] = line:sub(i)
                i = n + 1
            end
        end
    end

    -- Trailing comma means an empty last field
    if n > 0 and line:sub(n, n) == "," then
        fields[#fields + 1] = ""
    end

    return fields
end

-- Splits raw pasted text into non-empty, trimmed lines.
local function SplitLines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    return lines
end

local function Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

-- ============================================================
-- ---- Internal: add one holder entry for an item ----
-- ============================================================

local function AddHolder(itemID, itemName, name, class, spec, note)
    if not itemID or itemID == 0 or not name or name == "" then return false end

    class = (class or ""):upper()
    if class == "" then class = nil end

    local bucket = SoftRes.reserves[itemID]
    if not bucket then
        bucket = { itemName = itemName or ("Item " .. itemID), holders = {} }
        SoftRes.reserves[itemID] = bucket
    elseif itemName and itemName ~= "" then
        bucket.itemName = itemName
    end

    -- De-dupe: same name reserving the same item twice (e.g. re-pasted list)
    for _, h in ipairs(bucket.holders) do
        if h.name == name then
            h.class = class or h.class
            h.spec  = spec ~= "" and spec or h.spec
            h.note  = note ~= "" and note or h.note
            return false
        end
    end

    table.insert(bucket.holders, {
        name  = name,
        class = class,
        spec  = spec ~= "" and spec or nil,
        note  = note ~= "" and note or nil,
    })
    return true
end

-- ============================================================
-- ---- Import: softres.it CSV export ----
-- ============================================================
-- Header: Item Name,Item ID,From,Raider Name,Raider Class,Raider Spec,Raider Note,Extra Reserves,Date

function SoftRes:ImportCSV(text)
    if not text or Trim(text) == "" then return 0, 0, "Nothing to import." end

    self.reserves = {}
    local lines = SplitLines(text)
    local imported, skipped = 0, 0

    for _, line in ipairs(lines) do
        local f = ParseCSVLine(line)
        -- Skip header row
        if f[1] and f[1]:lower():find("item name") and f[2] and f[2]:lower():find("item id") then
            -- header, skip
        elseif #f >= 4 then
            local itemName = Trim(f[1])
            local itemID   = tonumber(Trim(f[2] or ""))
            local raider   = Trim(f[4] or "")
            local class    = Trim(f[5] or "")
            local spec     = Trim(f[6] or "")
            local note     = Trim(f[7] or "")

            if itemID and raider ~= "" then
                if AddHolder(itemID, itemName, raider, class, spec, note) then
                    imported = imported + 1
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    self:Recount()
    self.lastImportAt   = date and date("%H:%M:%S") or nil
    self.lastImportKind = "softres"

    if imported == 0 then
        return 0, 0, "No valid rows found — check the CSV format."
    end
    return imported, self.itemCount,
        string.format("Imported %d reservation(s) across %d item(s).", imported, self.itemCount)
end

-- ============================================================
-- ---- Import: WeakAura-style export ----
-- ============================================================
-- Format: ItemId,Name,Class,Note   (header optional)

function SoftRes:ImportWeakAura(text)
    if not text or Trim(text) == "" then return 0, 0, "Nothing to import." end

    self.reserves = {}
    local lines = SplitLines(text)
    local imported = 0

    for _, line in ipairs(lines) do
        local f = ParseCSVLine(line)
        local first = Trim(f[1] or "")
        if first:lower() == "itemid" then
            -- header, skip
        elseif #f >= 3 then
            local itemID = tonumber(first)
            local raider = Trim(f[2] or "")
            local class  = Trim(f[3] or "")
            local note   = Trim(f[4] or "")

            if itemID and raider ~= "" then
                if AddHolder(itemID, nil, raider, class, "", note) then
                    imported = imported + 1
                end
            end
        end
    end

    self:Recount()
    self.lastImportAt   = date and date("%H:%M:%S") or nil
    self.lastImportKind = "weakaura"

    if imported == 0 then
        return 0, 0, "No valid rows found — check the WeakAura export format."
    end
    return imported, self.itemCount,
        string.format("Imported %d reservation(s) across %d item(s).", imported, self.itemCount)
end

-- Auto-detects which format a pasted blob is and imports it.
-- Detection: the softres.it export always has a comma-separated line with
-- 9 fields (or a matching header); WeakAura export lines have 3-4 fields
-- with the item ID first instead of second.
function SoftRes:ImportAuto(text)
    if not text or Trim(text) == "" then return 0, 0, "Nothing to import." end
    local lines = SplitLines(text)
    if #lines == 0 then return 0, 0, "Nothing to import." end

    for _, line in ipairs(lines) do
        local f = ParseCSVLine(line)
        if #f >= 8 and tonumber(Trim(f[2] or "")) then
            return self:ImportCSV(text)
        elseif #f >= 1 and tonumber(Trim(f[1] or "")) then
            return self:ImportWeakAura(text)
        end
    end
    -- Fall back: header-only heuristics
    local firstLine = lines[1]:lower()
    if firstLine:find("item name") then
        return self:ImportCSV(text)
    elseif firstLine:find("itemid") then
        return self:ImportWeakAura(text)
    end
    return 0, 0, "Could not detect the format — try the specific Import buttons."
end

-- ============================================================
-- ---- Queries ----
-- ============================================================

function SoftRes:GetReservers(itemID)
    local bucket = self.reserves[itemID]
    if not bucket or #bucket.holders == 0 then return nil end
    return bucket.holders, bucket.itemName
end

function SoftRes:HasAny()
    return next(self.reserves) ~= nil
end

function SoftRes:Recount()
    local items, total = 0, 0
    for _, bucket in pairs(self.reserves) do
        items = items + 1
        total = total + #bucket.holders
    end
    self.itemCount    = items
    self.reserveCount = total
end

-- Sorted list of { itemID, itemName, holders } for the UI list view.
function SoftRes:GetSortedList()
    local list = {}
    for itemID, bucket in pairs(self.reserves) do
        table.insert(list, { itemID = itemID, itemName = bucket.itemName, holders = bucket.holders })
    end
    table.sort(list, function(a, b) return a.itemName < b.itemName end)
    return list
end

function SoftRes:Clear()
    self.reserves = {}
    self:Recount()
    self.lastImportAt   = nil
    self.lastImportKind = nil
end

-- Removes one holder's reservation for an item once it's been awarded to
-- them, so a duplicate drop of the same item later in the raid doesn't
-- get flagged as still reserved for them (common with repeat-drop bosses,
-- e.g. AQ40 trash/twins). If they were the last remaining holder for that
-- item, the item stops being tracked as reserved entirely; if someone else
-- also reserved it, that reservation stays live for the next drop.
function SoftRes:RemoveHolder(itemID, name)
    local bucket = self.reserves[itemID]
    if not bucket then return end
    for i, h in ipairs(bucket.holders) do
        if h.name == name then
            table.remove(bucket.holders, i)
            break
        end
    end
    if #bucket.holders == 0 then
        self.reserves[itemID] = nil
    end
    self:Recount()
end

-- ============================================================
-- ---- Persistence (called by Core on login / logout) ----
-- ============================================================

function SoftRes:SaveToDB(db)
    db.softReserves = self.reserves
end

function SoftRes:LoadFromDB(db)
    self.reserves = db.softReserves or {}
    self:Recount()
end
