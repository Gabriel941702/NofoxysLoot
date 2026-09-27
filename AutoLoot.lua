-- Nofoxy AutoLoot Module
-- Owns: the "everything at/below a quality threshold goes straight into the
-- Master Looter's own bags" behavior (MagicLooter-style), PLUS an optional
-- bind-type filter. Pure domain — no events, no UI. MasterLoot calls into
-- this per-slot while a corpse is open and only for items that are NOT
-- soft-reserved.
--
-- Two independent, combinable criteria decide whether an item auto-loots:
--   1. Quality ceiling  — anything AT OR BELOW the chosen quality.
--   2. Non-BoP items    — anything that is NOT Bind on Pickup (i.e. no
--      binding at all, or Bind on Equip), regardless of quality. This
--      exists because quality alone is a bad signal for "is this actually
--      trash" — recipes, patterns, and bags are very often plain white
--      (Common) quality items, which a pure quality filter can't tell
--      apart from genuine vendor junk. Since non-BoP items are freely
--      tradeable/sellable/mailable, auto-looting them is safe regardless
--      of quality; true BoP drops (real gear upgrades) NEVER auto-loot
--      under this criterion no matter how low their quality is, so they
--      always land in the Master Loot tab for a proper roll.

local AutoLoot = {}
NofoxyAL  = AutoLoot

-- Returns true if this item should be auto-looted to the Master Looter,
-- given current settings. itemLink is required for the bind-type check;
-- without it, only the quality-ceiling criterion is evaluated.
function AutoLoot:ShouldAutoLoot(quality, itemLink)
    if not Nofoxy.db or not Nofoxy.db.autoLootEnabled then return false end
    quality = quality or 0

    if quality <= (Nofoxy.db.autoLootThreshold or 0) then
        if Nofoxy.db.debug then
            Nofoxy:Print(string.format("[AutoLoot] quality=%d <= threshold=%d -> auto-loot",
                quality, Nofoxy.db.autoLootThreshold or 0))
        end
        return true
    end

    if Nofoxy.db.autoLootBoE and itemLink then
        local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
        local bindType
        if itemID then
            bindType = select(14, GetItemInfo(itemID))
        end
        if bindType and bindType ~= 1 then
            if Nofoxy.db.debug then
                Nofoxy:Print(string.format("[AutoLoot] quality=%d bindType=%s (not BoP) -> auto-loot",
                    quality, tostring(bindType)))
            end
            return true
        elseif Nofoxy.db.debug then
            Nofoxy:Print(string.format("[AutoLoot] quality=%d bindType=%s -> NOT auto-looted, showing in Master tab",
                quality, tostring(bindType)))
        end
    elseif Nofoxy.db.debug then
        Nofoxy:Print(string.format("[AutoLoot] quality=%d above threshold, BoE-check off -> NOT auto-looted",
            quality))
    end

    return false
end

-- Attempts to hand the given loot slot straight to the Master Looter (self).
-- Returns true on success, false otherwise. Only ever called by the ML.
function AutoLoot:GiveToSelf(slot, itemLink)
    local myIndex
    for i = 1, 40 do
        if GetMasterLootCandidate(i) == UnitName("player") then
            myIndex = i
            break
        end
    end
    if not myIndex then
        -- Not a valid candidate on our own loot (shouldn't normally happen for the ML)
        return false
    end

    GiveMasterLoot(slot, myIndex)

    if Nofoxy.db and Nofoxy.db.debug then
        Nofoxy:Print(string.format("[AutoLoot] slot=%d → self (%s)", slot, itemLink or "?"))
    end
    return true
end
