local addonName, addonTable = ...
local DungeonAlertAddon = CreateFrame("Frame")

-- Configuration
local config = {
    general = {
        ineligible_alerts = true,
        roles = {true, true, true} -- Tank, Healer, Damage
    },
    types = {
        dg_types = {
            ["2516"] = true, -- Normal
            ["2723"] = true, -- Heroic
            holiday = true,  -- Holiday Dungeons
            lvl_types = {
                ["258"] = true, -- Classic Normal
                ["259"] = true, -- Burning Crusade Normal
                ["260"] = true, -- Burning Crusade Heroic
                ["261"] = true, -- Lich King Normal
                ["262"] = true, -- Lich King Heroic
                ["300"] = true, -- Cata Normal
                ["301"] = true, -- Cata Heroic
                ["434"] = true, -- Hour of Twilight Heroic
                ["462"] = true, -- Mists of Pandaria Heroic
                ["463"] = true, -- Mists of Pandaria Normal
                ["788"] = true, -- Warlords of Draenor Normal
                ["789"] = true, -- Warlords of Draenor Heroic
                ["1045"] = true, -- Legion Normal
                ["1046"] = true, -- Legion Heroic
                ["1670"] = true, -- BFA Normal
                ["1671"] = true, -- BFA Heroic
                ["2086"] = true, -- Shadowlands Normal
                ["2087"] = true, -- Shadowlands Heroic
                ["2350"] = true, -- Dragonflight Normal
                ["2351"] = true, -- Dragonflight Heroic
            }
        },
        raid_types = {
            raid_container_nap = {
                ["2649"] = true, -- The Skittering Battlements
                ["2650"] = true, -- Secrets of Nerub-ar Palace
                ["2651"] = true, -- A Queen's Fall
            }
        }
    }
}

-- State variables
local lock = false
local last_status = nil
local data = {}
local lastDisplayTime = 0 -- Timestamp of the last display

-- Function to check player's eligibility for roles and dungeons
local function checkStatus()
    local r = false
    local canTank, canHealer, canDamage
    if config.general.ineligible_alerts then
        canTank, canHealer, canDamage = config.general.roles[1], config.general.roles[2], config.general.roles[3]
    else
        canTank, canHealer, canDamage = C_LFGList.GetAvailableRoles()
    end
    local ilvl = GetAverageItemLevel()

    local function checkTypes(instanceTypes, optionsKey, ilReq, isRaidCheck)
        if instanceTypes[optionsKey] then
            return true
        end
        if not isRaidCheck then
            return false
        end
        for raid_container_key, raid_container_value in pairs(instanceTypes) do
            for k, v in pairs(raid_container_value) do
                if k:find(optionsKey) and v then
                    return true
                end
            end
        end
        return false
    end

    local function checkInstanceType(dID, isHoliday, dName, ilReq)
        local options_key = tostring(dID)
        local dungeon_check = checkTypes(config.types.dg_types, options_key, ilReq, false)
        local raid_check = checkTypes(config.types.raid_types, options_key, ilReq, true)
        local holiday_check = config.types.dg_types.holiday and isHoliday
        return dungeon_check or raid_check or holiday_check
    end

    local function updateShortageInfo(dID, dName, isHoliday, ilReq)
        for j = 1, LFG_ROLE_NUM_SHORTAGE_TYPES do
            local eligible, tank, healer, damage, itemCount, money, xp = GetLFGRoleShortageRewards(dID, j)
            local tankLocked, healerLocked, damageLocked = GetLFDRoleRestrictions(dID)
            local isDesiredType = checkInstanceType(dID, isHoliday, dName, ilReq)
            local isEligible = ilvl > ilReq or config.general.ineligible_alerts
            tank = tank and canTank and not tankLocked and config.general.roles[1]
            healer = healer and canHealer and not healerLocked and config.general.roles[2]
            damage = damage and canDamage and not damageLocked and config.general.roles[3]
            if eligible and itemCount > 0 and (tank or healer or damage) and isDesiredType and isEligible then
                local rewardName, rewardIcon = GetLFGDungeonShortageRewardInfo(dID, j, 1)
                if not rewardIcon then
                    rewardIcon = ""
                    rewardName = ""
                end
                data[dID] = {dID = dID, name = GetLFGDungeonInfo(dID), rewardName = rewardName, rewardIcon = rewardIcon, tank = tank, healer = healer, damage = damage}
                r = true
            end
        end
    end

    for i = 1, GetNumRandomDungeons() do
        local dID, dName, _, _, _, _, _, _, _, _, _, _, _, _, _, isHoliday, _, _, _, _, ilReq = GetLFGRandomDungeonInfo(i)
        updateShortageInfo(dID, dName, isHoliday, ilReq)
    end

    for i = 1, GetNumRFDungeons() do
        local dID, dName, _, _, _, _, _, _, _, _, _, _, _, _, _, isHoliday, _, _, _, _, ilReq = GetRFDungeonInfo(i)
        updateShortageInfo(dID, dName, isHoliday, ilReq)
    end

    return r
end

-- Function to generate display text with role icons
function DungeonAlertAddon:GenerateDisplayText()
    local tankIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:0:19:22:41|t"
    local healerIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:1:20|t"
    local damageIcon = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:22:41|t"
    local text = "Call to Arms Status:\n"
    for _, v in pairs(data) do
        local icon_text = ""
        if config.general.roles[1] and v.tank then
            icon_text = icon_text .. tankIcon
        end
        if config.general.roles[2] and v.healer then
            icon_text = icon_text .. healerIcon
        end
        if config.general.roles[3] and v.damage then
            icon_text = icon_text .. damageIcon
        end
        if string.len(icon_text) > 0 then
            text = text .. string.format("%s %s %s\n", "|T" .. v.rewardIcon .. ":0|t", icon_text, v.name)
        end
    end
    return text
end

-- Event handler
local function onEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, function() RequestLFDPlayerLockInfo() end)
        RequestLFDPlayerLockInfo()
    elseif event == "LFG_UPDATE_RANDOM_INFO" then
        if not lock then
            lock = true
            last_status = checkStatus()
            C_Timer.After(30, function() lock = false; RequestLFDPlayerLockInfo(); end)

            -- Display the status only if a reward event has occurred and no more than once per minute
            if last_status and (GetTime() - lastDisplayTime) > 60 then
                print(DungeonAlertAddon:GenerateDisplayText())
                lastDisplayTime = GetTime() -- Update the last display time
            end
        end
    end
end

-- Register events
DungeonAlertAddon:RegisterEvent("PLAYER_LOGIN")
DungeonAlertAddon:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
DungeonAlertAddon:SetScript("OnEvent", onEvent)

-- Slash command for debugging
SLASH_CALLTOARMS1 = "/calltoarms"
SlashCmdList["CALLTOARMS"] = function(msg)
    print(DungeonAlertAddon:GenerateDisplayText())
end