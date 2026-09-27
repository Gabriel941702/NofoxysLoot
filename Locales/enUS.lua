-- Nofoxy Locale: enUS
-- Patterns for parsing CHAT_MSG_SYSTEM /roll messages under Master Loot.

local L = {}

-- Master Loot /roll patterns (CHAT_MSG_SYSTEM)
-- Captures: 1=name-or-"Your roll...", 2=value, 3=rangeMin, 4=rangeMax
L.MASTER_ROLL_PATTERNS = {
    -- "PlayerName rolls 85 (1-100)"
    "^(.-) rolls (%d+) %((%d+)%-(%d+)%)$",
    -- "Your roll for [Item] is 85 (1-100)"  /  "Your roll of 1-100 is 85. (1-100)"
    "^Your roll .- is (%d+) %((%d+)%-(%d+)%)$",
}

Nofoxy_L = L
