-- Nofoxy Parser
-- Parses CHAT_MSG_SYSTEM messages to capture /roll values during Master Loot.
-- No state of its own — delegates recorded rolls to MasterLoot.

local L = Nofoxy_L

local Parser = {}
NofoxyParser = Parser

function Parser:ProcessSystemMessage(message)
    if not message then return end

    for _, pattern in ipairs(L.MASTER_ROLL_PATTERNS) do
        local nameOrValue, valueStr, rangeMin, rangeMax = string.match(message, pattern)

        if nameOrValue and rangeMin then
            local value = tonumber(valueStr)
            local rMin  = tonumber(rangeMin)
            local rMax  = tonumber(rangeMax)

            if value and rMin == 1 and rMax == 100 and value >= 1 and value <= 100 then
                local playerName
                if nameOrValue:find("^Your roll") then
                    playerName = UnitName("player")
                else
                    playerName = nameOrValue
                end
                NofoxyML:RecordRoll(playerName, value)
                return
            end
        end
    end
end
