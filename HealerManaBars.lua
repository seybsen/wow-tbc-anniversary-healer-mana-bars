-- ============================================================================
-- Healer Mana Bars                                  WoW Classic Anniversary (2.5.x)
-- ----------------------------------------------------------------------------
-- One mana bar per raid healer plus an aggregate "overall" bar, with:
--   · class-coloured names and configurable bar colour (class / static / gradient)
--   · mana-regen (Innervate, Mana Tide) and drinking indicator icons
--   · low-mana alert: blink, local raid-warning, and optional chat announce
--   · test mode, lock/unlock dragging, and configurable size / texture / font
--
-- This file is the runtime. Saved-variable defaults and the options panel live
-- in HealerManaBarsConfig.lua, which the .toc loads first.
--
-- Slash: /hmb   (see /hmb help)
-- ============================================================================

local addonName = "HealerManaBars"
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "dev"

-- ─── Constants ───────────────────────────────────────────────────────────────

-- Power index 0 is mana regardless of the unit's *current* power type, so a
-- druid shifted into cat/bear still reports real mana here.
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- Auras (matched by name) that mark a temporary mana-regen effect. Mana Spring
-- Totem is intentionally absent: in TBC it pulses mana without applying any
-- player aura, so there is nothing to detect. Mana Tide and Innervate do.
local REGEN_AURAS = {
    ["Innervate"]         = true,
    ["Mana Tide"]         = true,
    ["Mana Tide Totem"]   = true,
    ["Mana Spring"]       = true,   -- listed in case a build ever surfaces it
    ["Mana Spring Totem"] = true,
    ["Shadowfiend"]       = true,
}
local DRINK_AURAS = {
    ["Drink"]       = true,
    ["Refreshment"] = true,
}

-- Media that always ships with the client. When LibSharedMedia-3.0 is present
-- we defer to its (much larger) registry instead, so the dropdowns match what
-- the rest of the user's UI offers.
local BUILTIN_TEXTURES = {
    ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Raid"]     = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    ["Flat"]     = "Interface\\Buttons\\WHITE8X8",
    ["Skillbar"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}
local BUILTIN_FONTS = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Skurri"]        = "Fonts\\SKURRI.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
}

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local CLASS_COLORS = RAID_CLASS_COLORS or {}

-- ElvUI engine handle, if the user runs ElvUI (drives the optional skin match).
local E = ElvUI and ElvUI[1]

-- Last-resort defaults. The config file normally seeds every key, but it is a
-- separate file: if it ever fails to load, this keeps the core from running
-- with a nil DB (which would size bars to nil and blank the whole display).
local CORE_FALLBACK = {
    locked = false, testMode = false, showOverall = true, overallOnly = false,
    hideDead = false, growth = "down",
    barW = 160, barH = 16, spacing = 2, texture = "Blizzard", scale = 1.0,
    font = "Friz Quadrata", fontSize = 11,
    opacity = 1.0, bgOpacity = 0.55,
    healerColorMode = "class",   healerStaticColor  = { 0.20, 0.80, 0.20 },
    overallColorMode = "static", overallStaticColor = { 0.20, 0.45, 0.95 },
    blink = true, lowThreshold = 30, warn = true,
    announce = false, announceChannel = "AUTO", useElvUI = false,
    showInRaid = true, showInParty = true, showInBattleground = true,
    showInArena = true, showAlways = false,
}

-- ─── State ───────────────────────────────────────────────────────────────────
local DB                       -- alias for HealerManaBarsDB, set in ApplyDefaults
local g_anchor                 -- movable container; parents every bar
local g_bars        = {}       -- reusable StatusBar pool, indexed 1..n
local g_fakeHealers            -- deterministic test-mode roster

local g_updateAccum = 0        -- time since the last throttled value refresh
local g_overallBar             -- the overall bar (cached so OnUpdate can blink it)
local g_overallBlink = false   -- is the overall bar currently in the low state?
local g_blinkPhase   = 0       -- accumulator driving the blink sine wave
local g_lowActive    = false   -- latch so the low-mana alert fires once per dip
local g_lastSig      = ""       -- last healer fingerprint, to detect death/roster shifts

local g_iconScratch = {}       -- reused per-bar icon list to avoid churn
local EMPTY_ICONS   = {}       -- shared empty list for the (icon-less) overall bar

-- ─── Media resolvers (also called from the config dropdowns) ─────────────────
function HealerManaBars_TexturePath(name)
    if LSM then return LSM:Fetch("statusbar", name) or LSM:Fetch("statusbar", "Blizzard") end
    return BUILTIN_TEXTURES[name] or BUILTIN_TEXTURES["Blizzard"]
end
local TexturePath = HealerManaBars_TexturePath

function HealerManaBars_TextureList()
    if LSM then return LSM:List("statusbar") end
    local t = {}
    for k in pairs(BUILTIN_TEXTURES) do t[#t + 1] = k end
    table.sort(t)
    return t
end

function HealerManaBars_FontPath(name)
    if LSM then return LSM:Fetch("font", name) or LSM:Fetch("font", "Friz Quadrata") end
    return BUILTIN_FONTS[name] or BUILTIN_FONTS["Friz Quadrata"]
end
local FontPath = HealerManaBars_FontPath

function HealerManaBars_FontList()
    if LSM then return LSM:List("font") end
    local t = {}
    for k in pairs(BUILTIN_FONTS) do t[#t + 1] = k end
    table.sort(t)
    return t
end

-- ─── Colour helpers ──────────────────────────────────────────────────────────
local function ClassColor(class)
    local c = CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

-- "|cffRRGGBB" escape so names can be class-coloured inside a single SetText.
local function ClassHex(class)
    local c = CLASS_COLORS[class]
    if c and c.colorStr then return "|c" .. c.colorStr end
    if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "|cffcccccc"
end

-- Health-bar style gradient: green at full, through yellow, to red at empty.
local function GradientColor(pct)
    if pct >= 0.5 then
        return (1.0 - pct) * 2, 1.0, 0.0
    else
        return 1.0, pct * 2, 0.0
    end
end

-- ─── Styling source (honours the optional ElvUI skin match) ──────────────────
-- When the user opts into ElvUI styling we mirror ElvUI's own media so the bars
-- blend into the rest of their UI; otherwise we use the addon's own choices.
local function CurrentTexture()
    if DB.useElvUI and E and E.media and E.media.normTex then
        return E.media.normTex
    end
    return TexturePath(DB.texture)
end

local function ApplyFont(fs)
    local path, size
    if DB.useElvUI and E and E.media and E.media.normFont then
        path = E.media.normFont
        size = (E.db and E.db.general and E.db.general.fontSize) or DB.fontSize or 11
    else
        path = FontPath(DB.font)
        size = DB.fontSize or 11
    end
    -- SetFont returns false on a bad path; fall back so text is never invisible.
    if fs:SetFont(path, size, "OUTLINE") == false then
        fs:SetFont(BUILTIN_FONTS["Friz Quadrata"], size, "OUTLINE")
    end
end

-- ─── Roster → ordered display list ───────────────────────────────────────────
local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
    else
        units[#units + 1] = "player"
    end
    return units
end

-- Detection is purely the assigned raid role. Guessing from class is unreliable
-- (a shadow priest is not a healer) and would need talent data we don't have.
local function IsHealer(unit)
    -- Solo: no assigned raid roles exist, so show your own mana regardless.
    if not IsInGroup() then return unit == "player" end
    return UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) == "HEALER"
end

-- Compact fingerprint of the shown healers and their alive/dead state. When it
-- moves (someone dies, resurrects, joins or leaves) we rebuild so corpses
-- re-sort to the bottom — and drop out entirely when "hide dead" is on.
local function HealerSignature()
    local parts = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) and IsHealer(unit) then
            parts[#parts + 1] = unit .. (UnitIsDeadOrGhost(unit) and "1" or "0")
        end
    end
    return table.concat(parts, ",")
end

-- Returns the ordered render list. Each entry is { kind = "overall" } or
-- { kind = "unit", unit/fake, name, class }. The overall bar is placed so it
-- always sits at the top, regardless of grow direction.
local function BuildEntries()
    -- Collect the healers to show; each carries a build-time dead flag used to
    -- sink corpses to the bottom (and to drop them when "hide dead" is on).
    local healers = {}
    if DB.testMode then
        for _, h in ipairs(g_fakeHealers) do
            local entry, dead
            if h.player then
                -- The real player: live name, mana and auras (so an actual
                -- Innervate/drink on you shows up while testing).
                local _, class = UnitClass("player")
                entry = { kind = "unit", unit = "player", name = UnitName("player"), class = class }
                dead = UnitIsDeadOrGhost("player")
            else
                entry = { kind = "unit", fake = h, name = h.name, class = h.class }
                dead = h.dead and true or false
            end
            entry.dead = dead
            if not (DB.hideDead and dead) then healers[#healers + 1] = entry end
        end
    else
        for _, unit in ipairs(GroupUnits()) do
            -- An offline member's bar would freeze on stale data and never
            -- update, so drop them rather than show a misleading value.
            if UnitExists(unit) and UnitIsConnected(unit) and IsHealer(unit) then
                local dead = UnitIsDeadOrGhost(unit)
                if not (DB.hideDead and dead) then
                    local _, class = UnitClass(unit)
                    healers[#healers + 1] = { kind = "unit", unit = unit, name = UnitName(unit), class = class, dead = dead }
                end
            end
        end
    end

    -- Canonical top→bottom order: overall first, then the living, then corpses.
    -- "Overall only" draws just the aggregate bar, but the healer list is still
    -- returned separately so the overall keeps reflecting the whole group.
    -- Solo (not grouped, outside test mode): the only healer is you, so the
    -- overall and individual bars would be identical. Show just the overall,
    -- forcing it on even if "show overall" is off.
    local soloSelf = not DB.testMode and not IsInGroup()
    local visual = {}
    if DB.showOverall or DB.overallOnly or soloSelf then visual[#visual + 1] = { kind = "overall" } end
    if not DB.overallOnly and not soloSelf then
        for _, h in ipairs(healers) do if not h.dead then visual[#visual + 1] = h end end
        for _, h in ipairs(healers) do if h.dead     then visual[#visual + 1] = h end end
    end

    -- Bar index grows away from the anchor along the grow direction, so "up"
    -- builds from the bottom — reverse the visual order to keep the overall bar
    -- on top and corpses on the bottom in both directions.
    if DB.growth == "up" then
        local rev = {}
        for i = #visual, 1, -1 do rev[#rev + 1] = visual[i] end
        return rev, healers
    end
    return visual, healers
end

-- ─── Bar pool ────────────────────────────────────────────────────────────────
local function AcquireBar(i)
    local bar = g_bars[i]
    if bar then return bar end

    bar = CreateFrame("StatusBar", "HealerManaBar" .. i, g_anchor)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.label:SetJustifyH("LEFT")

    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.value:SetJustifyH("RIGHT")

    -- Status icons sit *outside* the bar's right edge (see SetBarIcons), so the
    -- bar keeps its configured width and the % text is never overlapped.
    bar.icons = {}
    for n = 1, 2 do
        local ic = bar:CreateTexture(nil, "OVERLAY")
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the default icon border
        ic:Hide()
        bar.icons[n] = ic
    end

    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", bar, -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", bar, 1, -1)
    bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    g_bars[i] = bar
    return bar
end

-- Apply size/texture/font. Cheap to redo on every rebuild, so config changes
-- take effect immediately without recreating frames.
local function StyleBar(bar)
    bar:SetSize(DB.barW, DB.barH)
    bar:SetStatusBarTexture(CurrentTexture())
    -- Reuse the bar texture (darkened) as the background so the empty portion
    -- matches the fill instead of being a flat block.
    bar.bg:SetTexture(CurrentTexture())
    bar.bg:SetVertexColor(0, 0, 0, DB.bgOpacity or 0.55)
    ApplyFont(bar.label)
    ApplyFont(bar.value)
    local isz = math.max(8, DB.barH - 4)
    for _, ic in ipairs(bar.icons) do ic:SetSize(isz, isz) end
end

-- Lay out the active icons just past the bar's right edge, growing rightward.
local function SetBarIcons(bar, iconList)
    local prev
    for idx = 1, #bar.icons do
        local ic, path = bar.icons[idx], iconList[idx]
        if path then
            ic:SetTexture(path)
            ic:ClearAllPoints()
            -- chain off the previous icon, or the bar's right edge for the first
            ic:SetPoint("LEFT", prev or bar, "RIGHT", prev and 2 or 3, 0)
            ic:Show()
            prev = ic
        else
            ic:Hide()
        end
    end
end

-- Find the regen/drink aura icons on a unit, if any. Returns icon paths so the
-- indicator shows the actual spell art the player would recognise.
local function ScanRegenDrink(unit)
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

-- ─── Layout ──────────────────────────────────────────────────────────────────
-- Stack the bars from the anchor. "down" grows below it, "up" grows above; the
-- anchored edge stays put so the cluster doesn't drift as healers come and go.
local function LayoutBars(count)
    local step = DB.barH + DB.spacing
    for i = 1, count do
        local bar = g_bars[i]
        bar:ClearAllPoints()
        if DB.growth == "down" then
            bar:SetPoint("TOPLEFT", g_anchor, "TOPLEFT", 0, -(i - 1) * step)
        else
            bar:SetPoint("BOTTOMLEFT", g_anchor, "BOTTOMLEFT", 0, (i - 1) * step)
        end
    end
    g_anchor:SetSize(DB.barW, DB.barH)   -- one-bar footprint = drag target
end

-- ─── Value refresh (runs on the throttled timer) ─────────────────────────────
local function UnitMana(entry)
    if entry.fake then return entry.fake.cur, entry.fake.max end
    return UnitPower(entry.unit, MANA), UnitPowerMax(entry.unit, MANA)
end

-- Live dead/ghost state. Recomputed each refresh so grey-out reacts within a
-- tick; fakes carry a static flag for the test-mode demo.
local function IsEntryDead(entry)
    if entry.fake then return entry.fake.dead and true or false end
    if entry.unit then return UnitIsDeadOrGhost(entry.unit) end
    return false
end

-- Local-only alert: a raid-warning banner + sound that just the user sees.
local function FireLocalAlert()
    if not DB.warn then return end
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
    local c = DB.announceChannel or "AUTO"
    if c == "AUTO" then
        if IsInRaid() then return "RAID"
        elseif IsInGroup() then return "PARTY"
        else return nil end   -- solo: no group channel, so don't announce
    end
    return c
end

-- Broadcast the low-mana message. In test mode we deliberately print locally
-- instead of sending, so tuning the addon solo never spams a public channel.
local function FireAnnounce()
    if not DB.announce then return end
    local channel = ResolveChannel()
    local msg = "Healer mana below " .. (DB.lowThreshold or 30) .. "%"
    if DB.testMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffHealerManaBars|r [test → " .. (channel or "—") .. "]: " .. msg)
        return
    end
    -- No channel (solo) or a hardware-event-only channel (Say/Yell) can't be
    -- auto-sent from the timer — skip rather than trip ADDON_ACTION_BLOCKED.
    -- The local raid-warning alert still fires for the player if enabled.
    if not channel or PROTECTED_CHANNELS[channel] then return end
    SendChatMessage(msg, channel)
end

local function RefreshValues(entries, healers)
    -- Aggregate over every healer for the overall bar — including ones not drawn
    -- (so "overall only" still reflects the whole group). A corpse isn't "low on
    -- mana", just unavailable, so the dead are left out of the average.
    local sumCur, sumMax, healerCount = 0, 0, 0
    for _, e in ipairs(healers) do
        local cur, max = UnitMana(e)
        e._cur, e._max = cur, max
        e._dead = IsEntryDead(e)
        if not e._dead and max > 0 then
            sumCur, sumMax, healerCount = sumCur + cur, sumMax + max, healerCount + 1
        end
    end

    g_overallBar, g_overallBlink = nil, false

    for i, e in ipairs(entries) do
        local bar = g_bars[i]
        if not bar then break end

        if e.kind == "overall" then
            local pct = (sumMax > 0) and (sumCur / sumMax) or 0
            bar:SetValue(pct)
            g_overallBar = bar

            local threshold = DB.lowThreshold or 30
            local low = (healerCount > 0) and (pct * 100 < threshold)

            -- Alert once on the downward crossing, and only re-arm after mana
            -- climbs a margin back above the line, so a value sitting right at
            -- the threshold can't spam the warning/announce.
            if low and not g_lowActive then
                g_lowActive = true
                FireLocalAlert()
                FireAnnounce()
            elseif not low and pct * 100 >= threshold + 5 then
                g_lowActive = false
            end

            if low and DB.blink then
                g_overallBlink = true                 -- OnUpdate animates the alpha
                bar:SetStatusBarColor(0.90, 0.10, 0.10)
            else
                bar:SetAlpha(1)
                if DB.overallColorMode == "gradient" then
                    bar:SetStatusBarColor(GradientColor(pct))
                else
                    bar:SetStatusBarColor(unpack(DB.overallStaticColor))
                end
            end
            bar.label:SetText(string.format("|cffffffffHealers (%d)|r", healerCount))
            bar.value:SetText(string.format("%d%%", pct * 100 + 0.5))
            SetBarIcons(bar, EMPTY_ICONS)
        elseif e._dead then
            -- Greyed-out corpse. Only reached when "hide dead" is off, since the
            -- hide path drops dead healers from the list entirely.
            bar:SetValue(0)
            bar:SetAlpha(0.6)
            bar:SetStatusBarColor(0.35, 0.35, 0.35)
            bar.label:SetText("|cff808080" .. (e.name or "?") .. "|r")
            bar.value:SetText("|cff808080dead|r")
            SetBarIcons(bar, EMPTY_ICONS)
        else
            bar:SetAlpha(1)   -- this pooled bar may have shown a corpse last pass
            local cur, max = e._cur or 0, e._max or 0
            local pct = (max > 0) and (cur / max) or 0
            bar:SetValue(pct)

            if DB.healerColorMode == "gradient" then
                bar:SetStatusBarColor(GradientColor(pct))
            elseif DB.healerColorMode == "static" then
                bar:SetStatusBarColor(unpack(DB.healerStaticColor))
            else
                bar:SetStatusBarColor(ClassColor(e.class))
            end
            -- Name stays class-coloured even when the bar fill is static/gradient.
            bar.label:SetText(ClassHex(e.class) .. (e.name or "?") .. "|r")
            bar.value:SetText(string.format("%d%%", pct * 100 + 0.5))

            local regenIcon, drinkIcon
            if e.fake then
                regenIcon, drinkIcon = e.fake.regenIcon, e.fake.drinkIcon
            else
                regenIcon, drinkIcon = ScanRegenDrink(e.unit)
            end
            wipe(g_iconScratch)
            if regenIcon then g_iconScratch[#g_iconScratch + 1] = regenIcon end
            if drinkIcon then g_iconScratch[#g_iconScratch + 1] = drinkIcon end
            SetBarIcons(bar, g_iconScratch)
        end
    end
end

-- Per-context visibility. Arenas/BGs are tested before group type because the
-- instance also puts you in a party/raid, so the PvP options must win there.
local function ShouldShowByContext()
    if DB.showAlways then return true end
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then return DB.showInArena end
    if instanceType == "pvp"   then return DB.showInBattleground end
    if IsInRaid()  then return DB.showInRaid end
    if IsInGroup() then return DB.showInParty end
    return false   -- solo, and "always" is off
end

-- ─── Rebuild (roster or config change) ───────────────────────────────────────
local function Rebuild()
    if not g_anchor then return end

    -- Test mode and an unlocked frame always show (so it can be tuned and
    -- positioned); otherwise the per-context options decide. Hiding the anchor
    -- also hides every child bar and suspends its OnUpdate.
    if not (DB.testMode or not DB.locked or ShouldShowByContext()) then
        g_anchor:Hide()
        return
    end
    g_anchor:Show()
    g_anchor:SetAlpha(DB.opacity or 1)   -- whole-cluster opacity

    local entries, healers = BuildEntries()
    for _, bar in ipairs(g_bars) do bar:Hide() end
    for i in ipairs(entries) do
        local bar = AcquireBar(i)
        StyleBar(bar)
        bar:Show()
    end
    LayoutBars(#entries)
    RefreshValues(entries, healers)
    -- handed to OnUpdate for periodic refresh; healers can outnumber entries when
    -- "overall only" hides the individual bars
    g_anchor._entries = entries
    g_anchor._healers = healers
end

-- ─── Movement: lock / position ───────────────────────────────────────────────
local function ApplyLock()
    if not g_anchor then return end
    local unlocked = not DB.locked
    g_anchor:EnableMouse(unlocked)
    g_anchor.drag:SetShown(unlocked)
    g_anchor.dragTxt:SetShown(unlocked)
    Rebuild()   -- lock state affects solo visibility, so re-evaluate
end

local function SavePosition()
    local point, _, _, x, y = g_anchor:GetPoint()
    DB.pos = { point = point, x = x, y = y }
end

local function ApplyPosition()
    g_anchor:ClearAllPoints()
    if DB.pos then
        g_anchor:SetPoint(DB.pos.point, UIParent, DB.pos.point, DB.pos.x, DB.pos.y)
    else
        g_anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -16)   -- fresh-install default
    end
    g_anchor:SetScale(DB.scale)
end

-- ─── Test mode ───────────────────────────────────────────────────────────────
-- A fixed cast so screenshots/tuning are reproducible. (WoW's sandbox has no
-- math.randomseed, so randomised data wouldn't be stable across reloads anyway.)
local function MakeFakeHealers()
    -- The { player = true } slot is resolved live in BuildEntries to the real
    -- player (your name, mana and buffs); Shoosto is flagged dead to demo the
    -- grey-out / hide-dead option.
    local roster = {
        { name = "Zlarx",    class = "DRUID",   max = 3900,
          regenIcon = "Interface\\Icons\\Spell_Nature_Lightning" },          -- Innervate
        { name = "Cyllino",  class = "SHAMAN",  max = 4100,
          regenIcon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" }, -- Mana Tide
        { name = "Ellizza",  class = "SHAMAN",  max = 4000 },
        { player = true },
        { name = "Chanfana", class = "PALADIN", max = 4500 },
        { name = "Shoosto",  class = "PALADIN", max = 4400, dead = true },
    }
    for i, t in ipairs(roster) do
        if not t.player then
            -- Stagger starting levels (and speeds) so the bars don't move in
            -- lockstep; the wrap keeps every value in a readable 30–85% band.
            t.cur   = t.max * (0.30 + 0.55 * (((i - 1) * 0.23) % 1))
            t.dir   = -1
            t.speed = 50 + i * 20
        end
    end
    return roster
end

local function TickTestMode(elapsed)
    for _, h in ipairs(g_fakeHealers) do
        if not h.player then   -- the player slot reads real mana, not simulated
            h.cur = h.cur + h.dir * h.speed * elapsed
            if h.cur <= h.max * 0.10 then h.cur, h.dir = h.max * 0.10, 1 end
            if h.cur >= h.max         then h.cur, h.dir = h.max, -1 end
        end
    end
end

-- ─── OnUpdate driver ─────────────────────────────────────────────────────────
local function OnUpdate(_, elapsed)
    -- Blink runs every frame for a smooth pulse; the heavier value refresh below
    -- is throttled to ~10 Hz, which is plenty for mana and keeps the cost low.
    if g_overallBar then
        if g_overallBlink then
            g_blinkPhase = g_blinkPhase + elapsed
            g_overallBar:SetAlpha(0.30 + 0.70 * (0.5 + 0.5 * math.sin(g_blinkPhase * 6)))
        else
            g_overallBar:SetAlpha(1)
        end
    end

    g_updateAccum = g_updateAccum + elapsed
    if g_updateAccum < 0.1 then return end
    if DB.testMode then TickTestMode(g_updateAccum) end
    g_updateAccum = 0

    -- Re-sort/rebuild when a healer dies, resurrects, joins or leaves so corpses
    -- move to the bottom (and hide, with that option on). Cheap: just a string
    -- compare unless something actually changed.
    if not DB.testMode and IsInGroup() then
        local sig = HealerSignature()
        if sig ~= g_lastSig then
            g_lastSig = sig
            Rebuild()
            return
        end
    end

    -- Polling (vs. UNIT_POWER/UNIT_AURA events) is trivially cheap for a handful
    -- of bars and transparently handles units passing in and out of range.
    if g_anchor._entries then RefreshValues(g_anchor._entries, g_anchor._healers) end
end

-- ─── Init ────────────────────────────────────────────────────────────────────
local function InitAnchor()
    g_anchor = CreateFrame("Frame", "HealerManaBarsAnchor", UIParent)
    g_anchor:SetSize(DB.barW, DB.barH)
    g_anchor:SetMovable(true)
    g_anchor:SetClampedToScreen(true)
    g_anchor:RegisterForDrag("LeftButton")
    g_anchor:SetScript("OnDragStart", function() g_anchor:StartMoving() end)
    g_anchor:SetScript("OnDragStop", function()
        g_anchor:StopMovingOrSizing()
        SavePosition()
    end)

    -- Drag handle: a tinted overlay shown only while unlocked, so a locked frame
    -- is click-through and invisible chrome-wise.
    local drag = g_anchor:CreateTexture(nil, "OVERLAY")
    drag:SetAllPoints(g_anchor)
    drag:SetColorTexture(0.2, 0.6, 1.0, 0.35)
    g_anchor.drag = drag
    local dragTxt = g_anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragTxt:SetPoint("CENTER", drag, "CENTER")
    dragTxt:SetText("HMB — drag")
    g_anchor.dragTxt = dragTxt

    g_anchor:SetScript("OnUpdate", OnUpdate)
    ApplyPosition()
    ApplyLock()
end

local function ApplyDefaults()
    if HealerManaBars_EnsureDefaults then HealerManaBars_EnsureDefaults() end
    HealerManaBarsDB = HealerManaBarsDB or {}
    DB = HealerManaBarsDB
    -- Backstop the config file's defaults so no key the core touches is ever nil.
    for k, v in pairs(CORE_FALLBACK) do
        if DB[k] == nil then
            if type(v) == "table" then
                local t = {}
                for i, x in ipairs(v) do t[i] = x end
                DB[k] = t
            else
                DB[k] = v
            end
        end
    end
end

-- Hooks the options panel (separate file) calls to apply live changes.
HealerManaBars_Rebuild       = Rebuild
HealerManaBars_ApplyLock     = ApplyLock
HealerManaBars_ApplyPosition = ApplyPosition

-- ─── Slash command ───────────────────────────────────────────────────────────
local function PrintMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffHealerManaBars|r: " .. msg)
end

SLASH_HEALERMANABARS1 = "/hmb"
SLASH_HEALERMANABARS2 = "/healermanabars"
SlashCmdList["HEALERMANABARS"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "lock" then
        DB.locked = true;  ApplyLock(); PrintMsg("locked.")
    elseif msg == "unlock" then
        DB.locked = false; ApplyLock(); PrintMsg("unlocked — drag the blue handle.")
    elseif msg == "test" then
        DB.testMode = not DB.testMode; Rebuild()
        PrintMsg("test mode " .. (DB.testMode and "ON (fake healers)." or "OFF."))
    elseif msg == "up" or msg == "down" then
        DB.growth = msg; Rebuild(); PrintMsg("growth: " .. msg)
    elseif msg == "reset" then
        DB.pos = nil; ApplyPosition(); PrintMsg("position reset to top-left.")
    elseif msg == "config" or msg == "options" or msg == "" then
        if HealerManaBars_OpenConfig then HealerManaBars_OpenConfig() end
    elseif msg == "status" then
        -- Lightweight diagnostics for bug reports (see /hmb help).
        local entries = g_anchor and g_anchor._entries
        local shown = 0
        for _, b in ipairs(g_bars) do if b:IsShown() then shown = shown + 1 end end
        PrintMsg("config file loaded = " .. tostring(HealerManaBars_EnsureDefaults ~= nil))
        PrintMsg(string.format("testMode=%s  entries=%d  shownBars=%d  pool=%d",
            tostring(DB.testMode), entries and #entries or 0, shown, #g_bars))
        if g_anchor then
            local l, b = g_anchor:GetLeft(), g_anchor:GetBottom()
            PrintMsg(string.format("anchor shown=%s  x=%s y=%s",
                tostring(g_anchor:IsShown()),
                l and tostring(math.floor(l)) or "nil",
                b and tostring(math.floor(b)) or "nil"))
        else
            PrintMsg("|cffff4444g_anchor is NIL — init never ran (check for a login error).|r")
        end
    else
        PrintMsg("commands:")
        PrintMsg("  /hmb              — open the options panel")
        PrintMsg("  /hmb lock|unlock  — toggle dragging")
        PrintMsg("  /hmb test         — toggle test mode")
        PrintMsg("  /hmb up|down      — growth direction")
        PrintMsg("  /hmb reset        — reset position to top-left")
        PrintMsg("  /hmb status       — print diagnostics")
    end
end

-- ─── Events ──────────────────────────────────────────────────────────────────
-- PLAYER_LOGIN builds everything once; the rest just trigger a rebuild so the
-- roster, roles, and online status stay current.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_CONNECTION")        -- a member logged off / back on
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ApplyDefaults()
        g_fakeHealers = MakeFakeHealers()
        InitAnchor()
        Rebuild()
        PrintMsg("v" .. VERSION .. " loaded. /hmb for options.")
    else
        Rebuild()
    end
end)
