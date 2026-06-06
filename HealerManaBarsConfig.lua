-- ============================================================================
-- Healer Mana Bars — options panel & saved-variable defaults
-- ----------------------------------------------------------------------------
-- The .toc loads this file *before* the runtime, so the defaults below (and
-- HealerManaBars_EnsureDefaults) exist by the time the core initialises. The
-- panel registers into Interface → AddOns and edits HealerManaBarsDB live,
-- calling the HealerManaBars_* hooks the core exposes to apply changes.
-- ============================================================================

local ADDON_NAME = "HealerManaBars"

-- ─── Default configuration ──────────────────────────────────────────────────
local DEFAULTS = {
    pos          = nil,        -- {point, x, y}; nil = top-left corner
    locked       = false,      -- start unlocked so a fresh install is easy to place
    testMode     = false,
    showOverall  = true,
    hideDead     = false,      -- hide dead healers; when off they're greyed out
    growth       = "down",     -- "down" | "up"
    barW         = 160,
    barH         = 16,
    spacing      = 2,
    texture      = "Blizzard",
    font         = "Friz Quadrata",
    fontSize     = 11,
    scale        = 1.0,

    -- colouring
    healerColorMode    = "class",            -- "class" | "static" | "gradient"
    healerStaticColor  = { 0.20, 0.80, 0.20 },
    overallColorMode   = "static",           -- "static" | "gradient"
    overallStaticColor = { 0.20, 0.45, 0.95 },

    -- low-mana alerts
    blink           = true,
    lowThreshold    = 30,                     -- percent
    warn            = true,                   -- local raid-warning text + sound
    announce        = false,                  -- broadcast to a chat channel
    announceChannel = "AUTO",                 -- AUTO|SAY|PARTY|RAID|YELL|RAID_WARNING

    -- ElvUI skin match
    useElvUI        = false,
}

-- Seed any missing keys without clobbering the user's saved choices.
function HealerManaBars_EnsureDefaults()
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

-- ─── Convenience ────────────────────────────────────────────────────────────
local E = ElvUI and ElvUI[1]
local function Rebuild()   if HealerManaBars_Rebuild   then HealerManaBars_Rebuild()   end end
local function ApplyLock() if HealerManaBars_ApplyLock then HealerManaBars_ApplyLock() end end

-- ═════════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL
-- ═════════════════════════════════════════════════════════════════════════════
local panel = CreateFrame("Frame", "HealerManaBarsOptionsPanel")
panel.name = "Healer Mana Bars"

-- Every widget helper advances a shared y-cursor ({ v = ... }) so the layout
-- flows top-to-bottom without each call needing to know the running offset.

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    yRef.v = yRef.v - (fs:GetStringHeight() or 16) - 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.30, 0.50, 0.70, 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    line:SetWidth(width or 480)
    yRef.v = yRef.v - 8
end

-- Sub-label preceding a radio group / slider (e.g. "Growth direction").
local function MakeLabel(parent, yRef, text)
    yRef.v = yRef.v - 4
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    yRef.v = yRef.v - 20
    return fs
end

local function MakeDesc(parent, yRef, text, indent)
    indent = indent or 32
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, yRef.v)
    fs:SetWidth(440)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cff999999" .. text .. "|r")
    yRef.v = yRef.v - (fs:GetStringHeight() + 6)
    return fs
end

local function MakeCheckbox(parent, yRef, label, dbKey, onChange)
    yRef.v = yRef.v - 4
    local cb = CreateFrame("CheckButton", "HMBCB_" .. dbKey, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb.Text:SetText(label)
    cb:SetChecked(HealerManaBarsDB[dbKey] and true or false)
    cb:SetScript("OnClick", function(self)
        HealerManaBarsDB[dbKey] = self:GetChecked() and true or false
        if onChange then onChange(self:GetChecked()) end
        Rebuild()
    end)
    yRef.v = yRef.v - 26
    return cb
end

local function MakeRadioGroup(parent, yRef, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        local rb = CreateFrame("CheckButton", "HMBRB_" .. tostring(opt.key), parent, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        local textObj = rb.text or rb.Text or _G[rb:GetName() .. "Text"]
        if textObj then
            textObj:SetText(opt.label)
            textObj:SetFontObject("GameFontHighlight")
        end
        rb._key = opt.key
        radios[#radios + 1] = rb
        rb:SetScript("OnClick", function(self)
            -- Radios aren't a real group here, so clear the siblings ourselves.
            for _, other in ipairs(radios) do other:SetChecked(other._key == self._key) end
            onSelect(self._key)
        end)
        yRef.v = yRef.v - 22
    end
    for _, rb in ipairs(radios) do rb:SetChecked(rb._key == currentKey) end
    return radios
end

local g_sliderN = 0
local function MakeSlider(parent, yRef, label, dbKey, minV, maxV, step, onChange)
    MakeLabel(parent, yRef, label)

    g_sliderN = g_sliderN + 1
    local name = "HMBSlider" .. g_sliderN
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yRef.v)
    s:SetWidth(220)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    -- The Low/High labels aren't exposed as parentKeys on every client build, so
    -- fall back to a name-based lookup.
    local low  = s.Low  or _G[name .. "Low"]
    local high = s.High or _G[name .. "High"]
    if low  then low:SetText(minV)  end
    if high then high:SetText(maxV) end
    s:SetValue(HealerManaBarsDB[dbKey] or minV)

    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    val:SetPoint("LEFT", s, "RIGHT", 10, 0)
    val:SetText(tostring(HealerManaBarsDB[dbKey] or minV))

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step   -- snap to the step
        HealerManaBarsDB[dbKey] = v
        val:SetText(tostring(v))
        if onChange then onChange(v) end
        Rebuild()
    end)
    yRef.v = yRef.v - 34
    return s
end

-- Colour swatch that writes its RGB back into colorTbl in place.
local function MakeColorRow(parent, yRef, label, colorTbl)
    yRef.v = yRef.v - 4
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yRef.v)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    local tex = b:CreateTexture(nil, "OVERLAY"); tex:SetAllPoints(b)
    local function refresh() tex:SetColorTexture(colorTbl[1], colorTbl[2], colorTbl[3]) end
    refresh()
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetPoint("LEFT", b, "RIGHT", 8, 0); txt:SetText(label)

    b:SetScript("OnClick", function()
        local r, g, bl = colorTbl[1], colorTbl[2], colorTbl[3]
        local function set(nr, ng, nb)
            if not nr then return end
            colorTbl[1], colorTbl[2], colorTbl[3] = nr, ng, nb
            refresh(); Rebuild()
        end
        local function swatchFunc() set(ColorPickerFrame:GetColorRGB()) end
        local function cancelFunc(prev)
            if prev then set(prev.r or prev[1], prev.g or prev[2], prev.b or prev[3]) end
        end

        -- The modern (Dragonflight-derived) ColorPickerFrame ignores the old
        -- .func/.previousValues fields and needs SetupColorPickerAndShow; older
        -- clients only have the legacy path. Support both.
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = bl, hasOpacity = false,
                swatchFunc = swatchFunc, cancelFunc = cancelFunc,
            })
        else
            ColorPickerFrame.func           = swatchFunc
            ColorPickerFrame.cancelFunc     = cancelFunc
            ColorPickerFrame.hasOpacity     = false
            ColorPickerFrame.previousValues = { r = r, g = g, b = bl }
            ColorPickerFrame:SetColorRGB(r, g, bl)
            ColorPickerFrame:Hide(); ColorPickerFrame:Show()
        end
    end)
    yRef.v = yRef.v - 24
    return b
end

-- Dropdown over a media list. dbKey stores the chosen name; listFn supplies the
-- options (LibSharedMedia's registry when present, else the built-ins).
local function MakeMediaDropdown(parent, yRef, label, frameName, dbKey, listFn)
    MakeLabel(parent, yRef, label)

    local dd = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", -8, yRef.v)
    UIDropDownMenu_SetWidth(dd, 160)
    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, name in ipairs((listFn and listFn()) or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == HealerManaBarsDB[dbKey])
            info.func = function()
                HealerManaBarsDB[dbKey] = name
                UIDropDownMenu_SetText(dd, name)
                Rebuild()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(dd, HealerManaBarsDB[dbKey])
    yRef.v = yRef.v - 34
    return dd
end

-- ─── Panel contents ──────────────────────────────────────────────────────────
local function BuildPanel(p)
    if p._built then return end   -- build once; OnShow can fire repeatedly
    p._built = true
    -- The panel can be opened before our PLAYER_LOGIN handler runs, so make sure
    -- the DB is seeded before any widget reads it.
    HealerManaBars_EnsureDefaults()

    local PANEL_W = 480
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "dev"

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)
    title:SetText("|cff66ccffHealer Mana Bars|r")
    local verFs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFs:SetPoint("LEFT", title, "RIGHT", 6, 0)
    verFs:SetText("|cff555577v" .. version .. "|r")

    -- Scrolling content: the child is taller than the panel and sized to fit at
    -- the end, so the option list can grow without manual height bookkeeping.
    local scroll = CreateFrame("ScrollFrame", "HealerManaBarsScroll", p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -44)
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -30, 10)
    local child = CreateFrame("Frame", "HealerManaBarsScrollChild")
    child:SetSize(PANEL_W, 1000)
    scroll:SetScrollChild(child)

    local y = { v = 0 }

    -- General -----------------------------------------------------------------
    MakeHeader(child, y, "General", PANEL_W)
    MakeCheckbox(child, y, "Test mode (simulate fake healers)", "testMode")
    MakeCheckbox(child, y, "Show overall (aggregate) bar", "showOverall")
    MakeCheckbox(child, y, "Hide dead healers (otherwise grey them out)", "hideDead")
    MakeDesc(child, y, "Healers are detected via assigned raid role (right-click a unit " ..
        "frame → Role → Healer). Players without the Healer role are not shown.")
    MakeCheckbox(child, y, "Locked (uncheck to drag the bars)", "locked",
        function() ApplyLock() end)

    -- Layout ------------------------------------------------------------------
    MakeHeader(child, y, "Layout", PANEL_W)
    MakeLabel(child, y, "Growth direction")
    MakeRadioGroup(child, y, {
        { key = "down", label = "Grow downward" },
        { key = "up",   label = "Grow upward" },
    }, HealerManaBarsDB.growth, function(key)
        HealerManaBarsDB.growth = key; Rebuild()
    end)
    MakeSlider(child, y, "Bar width",  "barW",    60, 400, 1)
    MakeSlider(child, y, "Bar height", "barH",     8,  40, 1)
    MakeSlider(child, y, "Spacing",    "spacing",  0,  20, 1)
    MakeMediaDropdown(child, y, "Bar texture", "HealerManaBarsTextureDD", "texture", HealerManaBars_TextureList)
    MakeMediaDropdown(child, y, "Font", "HealerManaBarsFontDD", "font", HealerManaBars_FontList)
    MakeSlider(child, y, "Font size", "fontSize", 6, 24, 1)
    if E then
        MakeCheckbox(child, y, "Use ElvUI texture + font (overrides texture & font above)", "useElvUI")
    else
        MakeDesc(child, y, "ElvUI not detected — ElvUI texture/font option hidden.", 0)
    end

    -- Colours -----------------------------------------------------------------
    MakeHeader(child, y, "Colours", PANEL_W)
    MakeLabel(child, y, "Healer bars")
    MakeRadioGroup(child, y, {
        { key = "class",    label = "Class colours" },
        { key = "static",   label = "Static colour (set below)" },
        { key = "gradient", label = "By mana (green 100% → red 0%)" },
    }, HealerManaBarsDB.healerColorMode, function(key)
        HealerManaBarsDB.healerColorMode = key; Rebuild()
    end)
    MakeColorRow(child, y, "Healer static colour", HealerManaBarsDB.healerStaticColor)

    MakeLabel(child, y, "Overall bar")
    MakeRadioGroup(child, y, {
        { key = "static",   label = "Static colour (set below)" },
        { key = "gradient", label = "By mana (green 100% → red 0%)" },
    }, HealerManaBarsDB.overallColorMode, function(key)
        HealerManaBarsDB.overallColorMode = key; Rebuild()
    end)
    MakeColorRow(child, y, "Overall static colour", HealerManaBarsDB.overallStaticColor)
    MakeDesc(child, y, "Player names are always shown in class colours.", 0)

    -- Low-mana alerts ---------------------------------------------------------
    MakeHeader(child, y, "Low-mana alerts", PANEL_W)
    MakeSlider(child, y, "Threshold (%)", "lowThreshold", 5, 90, 1)
    MakeCheckbox(child, y, "Blink the overall bar red when below threshold", "blink")
    MakeCheckbox(child, y, "Local warning (raid-warning text + sound, only you)", "warn")
    MakeCheckbox(child, y, "Announce to chat when below threshold", "announce")
    MakeDesc(child, y, "Sends \"Healer mana below " .. (HealerManaBarsDB.lowThreshold or 30) ..
        "%\" once when overall healer mana drops below the threshold (re-arms after it " ..
        "recovers). In test mode it only prints locally, never to a public channel.")
    MakeLabel(child, y, "Announce channel")
    MakeRadioGroup(child, y, {
        { key = "AUTO",         label = "Auto (Raid / Party / Say by group)" },
        { key = "SAY",          label = "Say" },
        { key = "PARTY",        label = "Party" },
        { key = "RAID",         label = "Raid" },
        { key = "RAID_WARNING", label = "Raid Warning (needs assist/lead)" },
        { key = "YELL",         label = "Yell" },
    }, HealerManaBarsDB.announceChannel, function(key)
        HealerManaBarsDB.announceChannel = key
    end)

    child:SetHeight(math.abs(y.v) + 30)
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

-- ─── Registration ────────────────────────────────────────────────────────────
local function RegisterPanel()
    -- Settings.* is the modern API (Anniversary/retail engine); fall back to the
    -- classic InterfaceOptions API on older clients.
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function()
    HealerManaBars_EnsureDefaults()
    RegisterPanel()
end)

function HealerManaBars_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Twice on purpose: the classic API often opens the parent on first call.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
