-- ============================================================================
-- Healer Mana Bars — aura & spell detection
-- ----------------------------------------------------------------------------
-- Regen/drink buff detection, the combat-log Mana Tide tracker, and the
-- Innervate-by-class default for the right-click spell. Everything resolves
-- spell IDs to the client's locale at login (ns.InitAuras) — never match an
-- aura by a hard-coded English name.
-- ============================================================================

local _, ns = ...

local GetSpellInfo = GetSpellInfo

-- Spell IDs of the AURAS that actually land on the player (the buff you'd see in
-- their buff bar), resolved to the client's locale at login via GetSpellInfo so
-- detection stays locale- and rank-proof (ranks share a buff name).
--
-- Only effects that put a real aura on the player are detectable this way.
-- Verified in-game: Mana Spring Totem applies an *area aura* to each party member
-- (detectable), but Mana Tide Totem does NOT buff players — it energizes them
-- from a totem-side aura, so there's nothing to scan. Shadowfiend likewise
-- returns mana with no player aura. Both are therefore intentionally omitted.
local REGEN_SPELL_IDS = {
    29166,   -- Innervate (Druid) — single-target buff
    5677,    -- Mana Spring — area aura Mana Spring Totem applies to the party
}
local DRINK_SPELL_IDS = {
    430,     -- Drink (rank 1) — all ranks share the name "Drink"
    22734,   -- Drink (higher rank, for clients lacking the rank-1 entry)
}

-- Locale-resolved name sets, filled by ns.InitAuras() at login.
local REGEN_AURAS, DRINK_AURAS = {}, {}
local function BuildAuraNameSets()
    wipe(REGEN_AURAS); wipe(DRINK_AURAS)
    if not GetSpellInfo then return end   -- no resolver → indicators just stay off

    for _, id in ipairs(REGEN_SPELL_IDS) do
        local n = GetSpellInfo(id); if n then REGEN_AURAS[n] = true end
    end
    for _, id in ipairs(DRINK_SPELL_IDS) do
        local n = GetSpellInfo(id); if n then DRINK_AURAS[n] = true end
    end
end

-- Mana Tide Totem puts no aura on players (verified in-game) — it energizes the
-- party from a totem-side aura. So we detect it from the combat log instead:
-- watch for the periodic mana energize and flag the recipient for a short window.
-- Match is by localized name (the totem's name and/or the "Mana Tide" effect),
-- which covers every rank since ranks share a name.
-- 39609 is the energize the totem actually emits on the 2.5.5 client (its name is
-- "Mana Tide Totem", same across ranks); 16190/16191 are kept for other builds
-- but don't resolve here. We match the combat-log energize by the totem's
-- localized name, which covers every rank.
local MANATIDE_IDS    = { 39609, 16190, 16191 }
local MANATIDE_WINDOW = 4                   -- seconds; refreshed by each ~3s tick
local MANATIDE_NAMES  = {}                  -- locale-resolved, filled at login
local MANATIDE_ICON                         -- filled at login
local function BuildManaTide()
    wipe(MANATIDE_NAMES)
    if GetSpellInfo then
        for _, id in ipairs(MANATIDE_IDS) do
            local n = GetSpellInfo(id); if n then MANATIDE_NAMES[n] = true end
        end
    end
    -- Hardcoded: GetSpellTexture(39609) returns the *energize effect's* art (a
    -- Vampiric-Touch-looking icon), not the recognizable totem icon.
    MANATIDE_ICON = "Interface\\Icons\\Spell_Frost_SummonWaterElemental"
end

-- The right-click spell is user-configurable (DB.rightClickSpell). To seed a
-- sensible default we resolve Innervate's localized name at login and flag
-- whether the player is a druid who knows it; the login handler uses that for
-- the one-time class default. GetSpellInfo keeps the name locale-proof.
local INNERVATE_SPELL_ID = 29166
local g_innervateName            -- localized "Innervate", or nil
local g_canInnervate = false     -- player is a druid who knows Innervate
local function ComputeInnervate()
    local _, class = UnitClass("player")
    g_innervateName = GetSpellInfo and GetSpellInfo(INNERVATE_SPELL_ID) or nil
    g_canInnervate  = (class == "DRUID") and g_innervateName ~= nil
        and (not IsSpellKnown or IsSpellKnown(INNERVATE_SPELL_ID))
end

-- Resolve every locale-dependent name once. Call at PLAYER_LOGIN, before the
-- first Rebuild.
function ns.InitAuras()
    BuildAuraNameSets()
    BuildManaTide()
    ComputeInnervate()
end

-- One-time class default for DB.rightClickSpell: Innervate for druids who know
-- it, "" (off) for everyone else.
function ns.DefaultRightClickSpell()
    return g_canInnervate and g_innervateName or ""
end

-- Find the regen/drink aura icons on a unit, if any. Returns icon paths so the
-- indicator shows the actual spell art the player would recognise.
function ns.ScanRegenDrink(unit)
    local regenIcon, drinkIcon
    for i = 1, 40 do
        local name, icon = UnitBuff(unit, i)
        if not name then break end
        if DRINK_AURAS[name] then
            drinkIcon = icon
        elseif REGEN_AURAS[name] then
            regenIcon = regenIcon or icon
        end
    end
    return regenIcon, drinkIcon
end

-- ─── Mana Tide (combat-log) ──────────────────────────────────────────────────
-- A dedicated frame so combat-log spam never touches the rebuild path. It is
-- only registered while we're actually showing real healers (the engine calls
-- ns.SetTideTracking from Rebuild), so solo / hidden / test mode pay nothing.
local g_manaTide  = {}      -- destGUID -> GetTime() expiry, from the combat log
local g_clogOn    = false   -- is the combat-log tracker registered?
local g_tideDebug = false   -- /hmb tidedebug: print energize events to find IDs

local g_clog = CreateFrame("Frame")
g_clog:SetScript("OnEvent", function()
    local _, sub, _, _, srcName, _, _, destGUID, destName, _, _, spellId, spellName
        = CombatLogGetCurrentEventInfo()
    if sub ~= "SPELL_PERIODIC_ENERGIZE" and sub ~= "SPELL_ENERGIZE" then return end
    if g_tideDebug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff66ccffHMB tide|r energize: spell=%s id=%s src=%s dest=%s",
            tostring(spellName), tostring(spellId), tostring(srcName), tostring(destName)))
    end
    -- The energize can be attributed to the totem (source) or the effect (spell);
    -- match either localized name so we catch it regardless.
    if destGUID and (MANATIDE_NAMES[spellName] or MANATIDE_NAMES[srcName]) then
        g_manaTide[destGUID] = GetTime() + MANATIDE_WINDOW
    end
end)

function ns.SetTideTracking(on)
    if on == g_clogOn then return end
    g_clogOn = on
    if on then
        g_clog:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        g_clog:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        wipe(g_manaTide)
    end
end

-- The Mana Tide icon for this unit while its energize window is live, else nil.
function ns.UnitTideIcon(unit)
    local guid = UnitGUID(unit)
    if guid and (g_manaTide[guid] or 0) > GetTime() then return MANATIDE_ICON end
end

function ns.ToggleTideDebug()
    g_tideDebug = not g_tideDebug
    return g_tideDebug
end
