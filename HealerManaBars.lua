-- ============================================================================
-- Healer Mana Bars                                  WoW Classic Anniversary (2.5.x)
-- ----------------------------------------------------------------------------
-- One mana bar per raid healer plus an aggregate "overall" bar, with:
--   · class-coloured names and configurable bar colour (class / static / gradient)
--   · mana-regen (Innervate, Mana Spring, Mana Tide) and drinking indicator icons
--   · low-mana alert: blink, local raid-warning, and optional chat announce
--   · test mode, lock/unlock dragging, and configurable size / texture / font
--
-- This file is the display engine: it owns the movable anchor, decides what is
-- shown (visibility → Rebuild → RefreshValues), and drives the OnUpdate loop.
-- The other concerns live in their own modules, all sharing the private addon
-- table `ns` — defaults/media/colours (Core.lua), aura & Mana Tide detection
-- (Auras.lua), roster + test mode (Roster.lua), bar widgets (Bars.lua), alerts
-- (Alerts.lua), the slash command (Slash.lua) and the options panel
-- (HealerManaBarsConfig.lua).
--
-- Slash: /hmb   (see /hmb help)
-- ============================================================================

local addonName, ns = ...
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "dev"

-- Power index 0 is mana regardless of the unit's *current* power type, so a
-- druid shifted into cat/bear still reports real mana here.
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- ─── State ───────────────────────────────────────────────────────────────────
local DB                       -- alias for HealerManaBarsDB (= ns.db), set at login
local g_anchor                 -- movable container; parents every bar (= ns.anchor)

local g_updateAccum = 0        -- time since the last throttled value refresh
local g_overallBar             -- the overall bar (cached so OnUpdate can blink it)
local g_overallBlink = false   -- is the overall bar currently in the low state?
local g_blinkPhase   = 0       -- accumulator driving the blink sine wave
local g_lowActive    = false   -- latch so the low-mana alert fires once per dip
local g_lastSig      = ""      -- last healer fingerprint, to detect death/roster shifts

local g_iconScratch = {}       -- reused per-bar icon list to avoid churn
local EMPTY_ICONS   = {}       -- shared empty list for the (icon-less) overall bar

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

local function RefreshValues(entries, healers)
    local bars = ns.bars

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
        local bar = bars[i]
        if not bar then break end

        if e.kind == "overall" then
            local pct = (sumMax > 0) and (sumCur / sumMax) or 0
            bar:SetValue(pct)
            g_overallBar = bar

            local threshold = DB.lowThreshold or ns.DEFAULTS.lowThreshold
            local low = (healerCount > 0) and (pct * 100 < threshold)

            -- Alert once on the downward crossing, and only re-arm after mana
            -- climbs a margin back above the line, so a value sitting right at
            -- the threshold can't spam the warning/announce.
            if low and not g_lowActive then
                g_lowActive = true
                ns.FireLocalAlert()
                ns.FireAnnounce()
            elseif not low and pct * 100 >= threshold + 5 then
                g_lowActive = false
            end

            if low and DB.blink then
                g_overallBlink = true                 -- OnUpdate animates the alpha
                bar:SetStatusBarColor(0.90, 0.10, 0.10)
            else
                bar:SetAlpha(1)
                if DB.overallColorMode == "gradient" then
                    bar:SetStatusBarColor(ns.GradientColor(pct))
                else
                    bar:SetStatusBarColor(unpack(DB.overallStaticColor))
                end
            end
            bar.label:SetText(string.format("|cffffffffHealers (%d)|r", healerCount))
            bar.value:SetText(string.format("%d%%", pct * 100 + 0.5))
            ns.SetBarIcons(bar, EMPTY_ICONS)
        elseif e._dead then
            -- Greyed-out corpse. Only reached when "hide dead" is off, since the
            -- hide path drops dead healers from the list entirely.
            bar:SetValue(0)
            bar:SetAlpha(0.6)
            bar:SetStatusBarColor(0.35, 0.35, 0.35)
            bar.label:SetText("|cff808080" .. (e.name or "?") .. "|r")
            bar.value:SetText("|cff808080dead|r")
            ns.SetBarIcons(bar, EMPTY_ICONS)
        else
            bar:SetAlpha(1)   -- this pooled bar may have shown a corpse last pass
            local cur, max = e._cur or 0, e._max or 0
            local pct = (max > 0) and (cur / max) or 0
            bar:SetValue(pct)

            if DB.healerColorMode == "gradient" then
                bar:SetStatusBarColor(ns.GradientColor(pct))
            elseif DB.healerColorMode == "static" then
                bar:SetStatusBarColor(unpack(DB.healerStaticColor))
            else
                bar:SetStatusBarColor(ns.ClassColor(e.class))
            end
            -- Name stays class-coloured even when the bar fill is static/gradient.
            bar.label:SetText(ns.ClassHex(e.class) .. (e.name or "?") .. "|r")
            bar.value:SetText(string.format("%d%%", pct * 100 + 0.5))

            local regenIcon, drinkIcon
            if e.fake then
                regenIcon, drinkIcon = e.fake.regenIcon, e.fake.drinkIcon
            else
                regenIcon, drinkIcon = ns.ScanRegenDrink(e.unit)
            end
            -- Mana Tide has no player aura, so it comes from the combat-log tracker.
            local tideIcon = e.unit and ns.UnitTideIcon(e.unit) or nil
            wipe(g_iconScratch)
            if regenIcon then g_iconScratch[#g_iconScratch + 1] = regenIcon end
            if tideIcon  then g_iconScratch[#g_iconScratch + 1] = tideIcon  end
            if drinkIcon then g_iconScratch[#g_iconScratch + 1] = drinkIcon end
            ns.SetBarIcons(bar, g_iconScratch)
        end
    end
end

-- Per-context visibility. Arenas and battlegrounds assign no roles, so the addon
-- can never detect healers there — it's always hidden in PvP instances (checked
-- first, so even "always show" doesn't force a useless empty frame).
local function ShouldShowByContext()
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" then return false end
    if DB.showAlways then return true end
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
        ns.SetTideTracking(false)
        return
    end
    g_anchor:Show()
    g_anchor:SetAlpha(DB.opacity or 1)   -- whole-cluster opacity

    -- Mana Tide tracking only makes sense for real grouped healers.
    ns.SetTideTracking(not DB.testMode and IsInGroup())

    local entries, healers = ns.BuildEntries()
    for _, bar in ipairs(ns.bars) do bar:Hide() end
    for i, e in ipairs(entries) do
        local bar = ns.AcquireBar(i)
        ns.EnsureSecure(bar, i)
        ns.StyleBar(bar)
        bar:Show()
        ns.UpdateSecure(bar, e)
    end
    ns.LayoutBars(#entries)
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
    if DB.testMode then ns.TickTestMode(g_updateAccum) end
    g_updateAccum = 0

    -- Re-sort/rebuild when a healer dies, resurrects, joins or leaves so corpses
    -- move to the bottom (and hide, with that option on). Cheap: just a string
    -- compare unless something actually changed.
    if not DB.testMode and IsInGroup() then
        local sig = ns.HealerSignature()
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
    ns.anchor = g_anchor   -- bars parent to it (Bars.lua); /hmb status reads it
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

-- Hooks the options panel and slash command call to apply live changes.
ns.Rebuild       = Rebuild
ns.ApplyLock     = ApplyLock
ns.ApplyPosition = ApplyPosition

-- ─── Events ──────────────────────────────────────────────────────────────────
-- PLAYER_LOGIN builds everything once; the rest just trigger a rebuild so the
-- roster, roles, and online status stay current.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_CONNECTION")        -- a member logged off / back on
ev:RegisterEvent("PLAYER_REGEN_ENABLED")   -- combat ended → flush deferred secure attrs
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.ApplyDefaults()
        DB = ns.db
        ns.InitAuras()
        -- One-time class default for the right-click spell: druids → Innervate,
        -- everyone else → "" (off). nil means "never seeded", so clearing the
        -- field to "" later sticks and is not re-seeded.
        if DB.rightClickSpell == nil then
            DB.rightClickSpell = ns.DefaultRightClickSpell()
        end
        ns.InitTestMode()
        InitAnchor()
        Rebuild()
        ns.Print("v" .. VERSION .. " loaded. /hmb for options.")
    else
        Rebuild()
    end
end)
