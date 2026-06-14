-- ============================================================================
-- Healer Mana Bars — roster: who to show
-- ----------------------------------------------------------------------------
-- Turns the group roster (or the test-mode fake roster) into the ordered list
-- of entries the engine draws. Healer detection lives here — assigned raid
-- role only, no class-guessing.
-- ============================================================================

local _, ns = ...

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
-- moves (someone dies, resurrects, joins or leaves) the engine rebuilds so
-- corpses re-sort to the bottom — and drop out entirely when "hide dead" is on.
function ns.HealerSignature()
    local parts = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) and IsHealer(unit) then
            parts[#parts + 1] = unit .. (UnitIsDeadOrGhost(unit) and "1" or "0")
        end
    end
    return table.concat(parts, ",")
end

-- ─── Test mode ───────────────────────────────────────────────────────────────
-- A fixed cast so screenshots/tuning are reproducible. (WoW's sandbox has no
-- math.randomseed, so randomised data wouldn't be stable across reloads anyway.)
local g_fakeHealers            -- deterministic test-mode roster

local function MakeFakeHealers()
    -- The { player = true } slot is resolved live in ns.BuildEntries to the real
    -- player (your name, mana and buffs); Shoosto is flagged dead to demo the
    -- grey-out / hide-dead option.
    local roster = {
        { name = "Zlarx",    class = "DRUID",   max = 3900,
          regenIcon = "Interface\\Icons\\Spell_Nature_Lightning" },          -- Innervate
        { name = "Cyllino",  class = "SHAMAN",  max = 4100,
          regenIcon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" }, -- Mana Spring
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

-- Build the fake roster once, at login.
function ns.InitTestMode()
    g_fakeHealers = MakeFakeHealers()
end

function ns.TickTestMode(elapsed)
    for _, h in ipairs(g_fakeHealers) do
        if not h.player then   -- the player slot reads real mana, not simulated
            h.cur = h.cur + h.dir * h.speed * elapsed
            if h.cur <= h.max * 0.10 then h.cur, h.dir = h.max * 0.10, 1 end
            if h.cur >= h.max         then h.cur, h.dir = h.max, -1 end
        end
    end
end

-- ─── Roster → ordered display list ───────────────────────────────────────────
-- Returns the ordered render list. Each entry is { kind = "overall" } or
-- { kind = "unit", unit/fake, name, class }. The overall bar is placed so it
-- always sits at the top, regardless of grow direction.
function ns.BuildEntries()
    local db = ns.db
    -- Collect the healers to show; each carries a build-time dead flag used to
    -- sink corpses to the bottom (and to drop them when "hide dead" is on).
    local healers = {}
    if db.testMode then
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
            if not (db.hideDead and dead) then healers[#healers + 1] = entry end
        end
    else
        for _, unit in ipairs(GroupUnits()) do
            -- An offline member's bar would freeze on stale data and never
            -- update, so drop them rather than show a misleading value.
            if UnitExists(unit) and UnitIsConnected(unit) and IsHealer(unit) then
                local dead = UnitIsDeadOrGhost(unit)
                if not (db.hideDead and dead) then
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
    local soloSelf = not db.testMode and not IsInGroup()
    local visual = {}
    if db.showOverall or db.overallOnly or soloSelf then visual[#visual + 1] = { kind = "overall" } end
    if not db.overallOnly and not soloSelf then
        for _, h in ipairs(healers) do if not h.dead then visual[#visual + 1] = h end end
        for _, h in ipairs(healers) do if h.dead     then visual[#visual + 1] = h end end
    end

    -- Bar index grows away from the anchor along the grow direction, so "up"
    -- builds from the bottom — reverse the visual order to keep the overall bar
    -- on top and corpses on the bottom in both directions.
    if db.growth == "up" then
        local rev = {}
        for i = #visual, 1, -1 do rev[#rev + 1] = visual[i] end
        return rev, healers
    end
    return visual, healers
end
