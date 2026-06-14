-- ============================================================================
-- Healer Mana Bars — low-mana alerts
-- ----------------------------------------------------------------------------
-- The local raid-warning + sound and the optional chat announce. Fired by the
-- engine's once-per-dip threshold latch in RefreshValues. The channel rules
-- below (SAY/YELL) are engine restrictions — do not "fix" them away.
-- ============================================================================

local _, ns = ...

-- Local-only alert: a raid-warning banner + sound that just the user sees.
function ns.FireLocalAlert()
    if not ns.db.warn then return end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, "Healer mana low!", ChatTypeInfo["RAID_WARNING"])
    end
    if PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
end

-- SAY and YELL can only be sent from a hardware event (key/click); our
-- threshold alert runs from the update timer, so Blizzard blocks them with
-- ADDON_ACTION_BLOCKED. PARTY/RAID/RAID_WARNING are allowed from automated code.
local PROTECTED_CHANNELS = { SAY = true, YELL = true }

-- Returns the channel to announce on, or nil when there is nobody to tell.
local function ResolveChannel()
    local c = ns.db.announceChannel or "AUTO"
    if c == "AUTO" then
        if IsInRaid() then return "RAID"
        elseif IsInGroup() then return "PARTY"
        else return nil end   -- solo: no group channel, so don't announce
    end
    return c
end

-- Broadcast the low-mana message. In test mode we deliberately print locally
-- instead of sending, so tuning the addon solo never spams a public channel.
function ns.FireAnnounce()
    local db = ns.db
    if not db.announce then return end
    local channel = ResolveChannel()
    local msg = "Healer mana below " .. (db.lowThreshold or ns.DEFAULTS.lowThreshold) .. "%"
    if db.testMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffHealerManaBars|r [test → " .. (channel or "—") .. "]: " .. msg)
        return
    end
    -- No channel (solo) or a hardware-event-only channel (Say/Yell) can't be
    -- auto-sent from the timer — skip rather than trip ADDON_ACTION_BLOCKED.
    -- The local raid-warning alert still fires for the player if enabled.
    if not channel or PROTECTED_CHANNELS[channel] then return end
    SendChatMessage(msg, channel)
end
