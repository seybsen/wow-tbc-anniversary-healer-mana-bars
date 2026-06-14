-- ============================================================================
-- Healer Mana Bars — core: defaults, saved variables, media, colours
-- ----------------------------------------------------------------------------
-- First-loaded runtime module. Owns the saved-variable defaults (DEFAULTS —
-- the single source of truth), seeds/aliases the DB, and provides the shared
-- media resolvers, colour helpers and chat printer that every other module
-- reaches through the private addon table (ns).
-- ============================================================================

local _, ns = ...

-- ─── Saved-variable defaults ─────────────────────────────────────────────────
-- The single source of truth for saved-variable defaults. It lives here (not
-- the options panel) so the bars still get a fully-seeded DB even if the panel
-- file ever fails to load. Seeded by ns.EnsureDefaults (below); also exposed
-- as ns.DEFAULTS. Add a new setting here and nowhere else.
local DEFAULTS = {
    pos          = nil,        -- {point, x, y}; nil = top-left corner
    locked       = false,      -- start unlocked so a fresh install is easy to place
    testMode     = false,
    showOverall  = true,
    overallOnly  = false,      -- show only the overall bar, no individual healers
    hideDead     = false,      -- hide dead healers; when off they're greyed out
    growth       = "down",     -- "down" | "up"
    nameSide     = "left",      -- name text edge: "left" | "right"
    valueSide    = "right",     -- % readout: "left" | "right" | "hidden"
    iconSide     = "right",     -- status icons overflow this edge: "left" | "right"
    fillDir      = "lr",        -- bar fill: "lr" (empties from right) | "rl" (from left)
    barW         = 160,
    barH         = 16,
    spacing      = 2,
    texture      = "Blizzard",
    font         = "Friz Quadrata",
    fontSize     = 11,
    scale        = 1.0,
    opacity      = 1.0,        -- whole-cluster opacity
    bgOpacity    = 0.55,       -- bar background (empty track) opacity

    -- colouring
    healerColorMode    = "class",            -- "class" | "static" | "gradient"
    healerStaticColor  = { 0.20, 0.80, 0.20 },
    overallColorMode   = "static",           -- "static" | "gradient"
    overallStaticColor = { 0.20, 0.45, 0.95 },

    -- low-mana alerts
    blink           = true,
    lowThreshold    = 15,                     -- percent
    warn            = true,                   -- local raid-warning text + sound
    announce        = false,                  -- broadcast to a chat channel
    announceChannel = "AUTO",                 -- AUTO|SAY|PARTY|RAID|YELL|RAID_WARNING

    -- click interaction (secure overlay; see UpdateSecure in Bars.lua)
    clickToTarget   = true,   -- left-click a healer bar to target them
    -- rightClickSpell: spell name cast on a healer with right-click ("" = off).
    -- Left nil here (like `pos`) and seeded at login by class — Innervate for
    -- druids, "" for everyone else — since DEFAULTS can't know the class.
    rightClickSpell = nil,

    -- ElvUI skin match
    useElvUI        = false,

    -- where the bars are shown (always hidden in arenas/BGs — no roles there;
    -- see ShouldShowByContext)
    showInRaid  = true,
    showInParty = true,
    showAlways  = false,   -- show everywhere applicable, even solo
}
ns.DEFAULTS = DEFAULTS

-- Seed any missing keys without clobbering the user's saved choices. Exposed so
-- the options panel can guarantee the DB exists before it reads a widget value.
function ns.EnsureDefaults()
    HealerManaBarsDB = HealerManaBarsDB or {}
    local db = HealerManaBarsDB

    -- Migrate the pre-1.0 key name before filling defaults.
    if db.lowThreshold == nil and db.blinkThreshold ~= nil then
        db.lowThreshold = db.blinkThreshold
    end
    db.blinkThreshold = nil

    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            -- Copy table defaults (colours) so editing the live value can't
            -- mutate the shared DEFAULTS template.
            if type(v) == "table" then
                local t = {}
                for i, x in ipairs(v) do t[i] = x end
                db[k] = t
            else
                db[k] = v
            end
        end
    end
end

-- Called once at login (before anything renders). ns.db is the live DB alias
-- every module reads *at call time* — never captured at file scope — so module
-- load order can never hand out a stale nil.
function ns.ApplyDefaults()
    ns.EnsureDefaults()
    ns.db = HealerManaBarsDB
end

-- ─── Media ───────────────────────────────────────────────────────────────────
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

-- Last-resort font for when a resolved path fails to SetFont (see ApplyFont in
-- Bars.lua) — ships with every client, so text is never invisible.
ns.FALLBACK_FONT = BUILTIN_FONTS["Friz Quadrata"]

function ns.TexturePath(name)
    if LSM then return LSM:Fetch("statusbar", name) or LSM:Fetch("statusbar", "Blizzard") end
    return BUILTIN_TEXTURES[name] or BUILTIN_TEXTURES["Blizzard"]
end

function ns.TextureList()
    if LSM then return LSM:List("statusbar") end
    local t = {}
    for k in pairs(BUILTIN_TEXTURES) do t[#t + 1] = k end
    table.sort(t)
    return t
end

function ns.FontPath(name)
    if LSM then return LSM:Fetch("font", name) or LSM:Fetch("font", "Friz Quadrata") end
    return BUILTIN_FONTS[name] or BUILTIN_FONTS["Friz Quadrata"]
end

function ns.FontList()
    if LSM then return LSM:List("font") end
    local t = {}
    for k in pairs(BUILTIN_FONTS) do t[#t + 1] = k end
    table.sort(t)
    return t
end

-- ─── Colour helpers ──────────────────────────────────────────────────────────
local CLASS_COLORS = RAID_CLASS_COLORS or {}

function ns.ClassColor(class)
    local c = CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

-- "|cffRRGGBB" escape so names can be class-coloured inside a single SetText.
function ns.ClassHex(class)
    local c = CLASS_COLORS[class]
    if c and c.colorStr then return "|c" .. c.colorStr end
    if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "|cffcccccc"
end

-- Health-bar style gradient: green at full, through yellow, to red at empty.
function ns.GradientColor(pct)
    if pct >= 0.5 then
        return (1.0 - pct) * 2, 1.0, 0.0
    else
        return 1.0, pct * 2, 0.0
    end
end

-- ─── Chat output ─────────────────────────────────────────────────────────────
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffHealerManaBars|r: " .. msg)
end
