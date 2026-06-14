-- ============================================================================
-- Healer Mana Bars — bar widgets
-- ----------------------------------------------------------------------------
-- The pooled StatusBar frames and everything per-bar: creation (ns.AcquireBar),
-- the secure click overlay, styling, per-element layout, status icons, and the
-- cluster stacking (ns.LayoutBars). Bars parent to ns.anchor (the engine's
-- movable container) and are re-styled each rebuild so config changes apply
-- live without recreating frames.
-- ============================================================================

local _, ns = ...

-- ElvUI engine handle, if the user runs ElvUI (drives the optional skin match).
local E = ElvUI and ElvUI[1]

-- Reusable StatusBar pool, indexed 1..n. Shared on ns so the engine can hide /
-- refresh the pool and `/hmb status` can report its size.
ns.bars = {}

-- ─── Styling source (honours the optional ElvUI skin match) ──────────────────
-- When the user opts into ElvUI styling we mirror ElvUI's own media so the bars
-- blend into the rest of their UI; otherwise we use the addon's own choices.
local function CurrentTexture()
    local db = ns.db
    if db.useElvUI and E and E.media and E.media.normTex then
        return E.media.normTex
    end
    return ns.TexturePath(db.texture)
end

local function ApplyFont(fs)
    local db = ns.db
    local path, size
    if db.useElvUI and E and E.media and E.media.normFont then
        path = E.media.normFont
        size = (E.db and E.db.general and E.db.general.fontSize) or db.fontSize or 11
    else
        path = ns.FontPath(db.font)
        size = db.fontSize or 11
    end
    -- SetFont returns false on a bad path; fall back so text is never invisible.
    if fs:SetFont(path, size, "OUTLINE") == false then
        fs:SetFont(ns.FALLBACK_FONT, size, "OUTLINE")
    end
end

-- ─── Bar pool ────────────────────────────────────────────────────────────────
function ns.AcquireBar(i)
    local bar = ns.bars[i]
    if bar then return bar end

    bar = CreateFrame("StatusBar", "HealerManaBar" .. i, ns.anchor)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)

    -- Text anchors (name/value sides) are applied per rebuild in ns.StyleBar so
    -- the layout options take effect live; just create the strings here.
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    -- Status icons sit *outside* the bar (the configured edge; see SetBarIcons),
    -- so the bar keeps its width and the % text is never overlapped.
    -- Up to three: mana-regen, Mana Tide, drinking.
    bar.icons = {}
    for n = 1, 3 do
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

    ns.bars[i] = bar
    return bar
end

-- ─── Click-to-target / right-click Innervate (secure) ────────────────────────
-- Targeting a unit and casting a spell on it are *protected* actions: they must
-- go through a SecureActionButtonTemplate whose attributes are set out of combat
-- (SetAttribute is blocked while InCombatLockdown). So each bar carries a secure
-- overlay button; left-click targets the healer, right-click casts the user's
-- configured spell. Attribute writes — and the create/anchor of a new overlay —
-- are skipped in combat and re-applied on PLAYER_REGEN_ENABLED (which Rebuilds).
function ns.EnsureSecure(bar, i)
    -- CreateFrame/SetPoint on a protected frame is also blocked in combat, so if
    -- the pool grows mid-fight we leave the overlay until combat ends.
    if bar.secure or InCombatLockdown() then return end
    local sec = CreateFrame("Button", "HealerManaBarButton" .. i, bar, "SecureActionButtonTemplate")
    sec:SetAllPoints(bar)
    sec:RegisterForClicks("AnyUp")   -- both buttons; left=target, right=spell
    bar.secure = sec
end

-- Point the overlay at this entry's unit. Cleared for the overall/test bars (no
-- real unit) so a click there is a harmless no-op. Mouse is enabled only while
-- locked, so an unlocked cluster stays draggable instead of eating the click.
function ns.UpdateSecure(bar, entry)
    local sec = bar.secure
    if not sec or InCombatLockdown() then return end
    local db = ns.db
    -- Clicking disabled (db.clickToTarget) drops the unit so every click no-ops;
    -- the overall/test bars carry no real unit to target either.
    local unit = db.clickToTarget and entry.unit or nil
    -- Right-click casts the user's configured spell on that unit; blank = off.
    local spell = db.rightClickSpell
    if spell == "" then spell = nil end
    if unit then
        sec:SetAttribute("unit", unit)
        sec:SetAttribute("type1", "target")
        if spell then
            sec:SetAttribute("type2", "spell")
            sec:SetAttribute("spell2", spell)
        else
            sec:SetAttribute("type2", nil)
            sec:SetAttribute("spell2", nil)
        end
    else
        sec:SetAttribute("unit", nil)
        sec:SetAttribute("type1", nil)
        sec:SetAttribute("type2", nil)
        sec:SetAttribute("spell2", nil)
    end
    -- Mouse on only while locked AND clicking enabled, so unlocked/off = draggable.
    sec:EnableMouse(db.locked and db.clickToTarget)
end

-- ─── Per-element layout & styling ────────────────────────────────────────────
-- Anchor the name/value text to their configured edges (icons are handled in
-- SetBarIcons). Re-done each rebuild so the layout options apply live; lets you
-- mirror everything for a cluster docked on the right of the screen.
local function LayoutBarElements(bar)
    local db = ns.db
    bar.label:ClearAllPoints()
    if db.nameSide == "right" then
        bar.label:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.label:SetJustifyH("RIGHT")
    else
        bar.label:SetPoint("LEFT", bar, "LEFT", 4, 0)
        bar.label:SetJustifyH("LEFT")
    end

    bar.value:ClearAllPoints()
    if db.valueSide == "hidden" then
        bar.value:Hide()
    else
        bar.value:Show()
        if db.valueSide == "left" then
            bar.value:SetPoint("LEFT", bar, "LEFT", 4, 0)
            bar.value:SetJustifyH("LEFT")
        else
            bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
            bar.value:SetJustifyH("RIGHT")
        end
    end
end

-- Apply size/texture/font. Cheap to redo on every rebuild, so config changes
-- take effect immediately without recreating frames.
function ns.StyleBar(bar)
    local db = ns.db
    bar:SetSize(db.barW, db.barH)
    bar:SetStatusBarTexture(CurrentTexture())
    -- Reverse fill anchors the filled portion to the right edge (empties from the
    -- left) — pairs with a right-of-screen mirror. Guarded: older clients lack it.
    if bar.SetReverseFill then bar:SetReverseFill(db.fillDir == "rl") end
    -- Reuse the bar texture (darkened) as the background so the empty portion
    -- matches the fill instead of being a flat block.
    bar.bg:SetTexture(CurrentTexture())
    bar.bg:SetVertexColor(0, 0, 0, db.bgOpacity or 0.55)
    ApplyFont(bar.label)
    ApplyFont(bar.value)
    LayoutBarElements(bar)
    local isz = math.max(8, db.barH - 4)
    for _, ic in ipairs(bar.icons) do ic:SetSize(isz, isz) end
end

-- Lay out the active icons just past the configured bar edge, growing outward
-- (rightward off the right edge by default, or leftward off the left edge).
function ns.SetBarIcons(bar, iconList)
    local left = (ns.db.iconSide == "left")
    local prev
    for idx = 1, #bar.icons do
        local ic, path = bar.icons[idx], iconList[idx]
        if path then
            ic:SetTexture(path)
            ic:ClearAllPoints()
            -- chain off the previous icon, or the bar's edge for the first
            if left then
                ic:SetPoint("RIGHT", prev or bar, "LEFT", -(prev and 2 or 3), 0)
            else
                ic:SetPoint("LEFT", prev or bar, "RIGHT", prev and 2 or 3, 0)
            end
            ic:Show()
            prev = ic
        else
            ic:Hide()
        end
    end
end

-- ─── Cluster layout ──────────────────────────────────────────────────────────
-- Stack the bars from the anchor. "down" grows below it, "up" grows above; the
-- anchored edge stays put so the cluster doesn't drift as healers come and go.
function ns.LayoutBars(count)
    local db = ns.db
    local anchor = ns.anchor
    local step = db.barH + db.spacing
    for i = 1, count do
        local bar = ns.bars[i]
        bar:ClearAllPoints()
        if db.growth == "down" then
            bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * step)
        else
            bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, (i - 1) * step)
        end
    end
    anchor:SetSize(db.barW, db.barH)   -- one-bar footprint = drag target
end
