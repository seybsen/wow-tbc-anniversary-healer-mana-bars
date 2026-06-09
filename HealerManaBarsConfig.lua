-- ============================================================================
-- Healer Mana Bars — options panel
-- ----------------------------------------------------------------------------
-- Builds the options panel (Interface → AddOns) and edits HealerManaBarsDB
-- live, calling the ns.* hooks the runtime exposes to apply changes. The
-- saved-variable defaults and ns.EnsureDefaults live in the runtime
-- (HealerManaBars.lua) so the DB is seeded even if this panel ever fails to
-- load; everything here runs at panel-open time, after the runtime is loaded.
-- ============================================================================

local ADDON_NAME, ns = ...

-- ─── Convenience ────────────────────────────────────────────────────────────
local E = ElvUI and ElvUI[1]
local function Rebuild()   if ns.Rebuild   then ns.Rebuild()   end end
local function ApplyLock() if ns.ApplyLock then ns.ApplyLock() end end

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

-- Single-line text input. Commits on Enter or focus-loss, trims whitespace, and
-- Escape reverts to the stored value. Stores the string under dbKey.
local function MakeEditBox(parent, yRef, label, dbKey, onChange)
    MakeLabel(parent, yRef, label)
    local eb = CreateFrame("EditBox", "HMBEdit_" .. dbKey, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yRef.v)
    eb:SetSize(220, 20)
    eb:SetAutoFocus(false)
    eb:SetText(HealerManaBarsDB[dbKey] or "")
    local function commit()
        local v = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        HealerManaBarsDB[dbKey] = v
        eb:SetText(v)
        eb:ClearFocus()
        if onChange then onChange(v) end
        Rebuild()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function()
        eb:SetText(HealerManaBarsDB[dbKey] or ""); eb:ClearFocus()
    end)
    yRef.v = yRef.v - 30
    return eb
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
-- fmt(value) optionally formats the readout (e.g. as a percentage); defaults to
-- the raw number for integer sliders like width/height.
local function MakeSlider(parent, yRef, label, dbKey, minV, maxV, step, onChange, fmt)
    local function disp(v) return fmt and fmt(v) or tostring(v) end
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
    val:SetText(disp(HealerManaBarsDB[dbKey] or minV))

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step   -- snap to the step
        HealerManaBarsDB[dbKey] = v
        val:SetText(disp(v))
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
-- Each tab builds its widgets into its own scroll page, so a page only scrolls
-- if it actually overflows. The shared y-cursor pattern is unchanged — it just
-- runs once per tab instead of over one giant list. PANEL_W is the content width.
local PANEL_W = 480

local function BuildGeneralTab(child)
    local y = { v = 0 }
    MakeHeader(child, y, "General", PANEL_W)
    MakeCheckbox(child, y, "Test mode (simulate fake healers)", "testMode")
    MakeCheckbox(child, y, "Show overall (aggregate) bar", "showOverall")
    MakeCheckbox(child, y, "Only the overall bar (hide individual healers)", "overallOnly")
    MakeCheckbox(child, y, "Hide dead healers (otherwise grey them out)", "hideDead")
    MakeDesc(child, y, "Healers are detected via assigned raid role (right-click a unit " ..
        "frame → Role → Healer). Players without the Healer role are not shown. " ..
        "When solo (no raid roles), a single bar shows your own mana.")
    MakeCheckbox(child, y, "Locked (uncheck to drag the bars)", "locked",
        function() ApplyLock() end)

    MakeHeader(child, y, "Interaction", PANEL_W)
    MakeCheckbox(child, y, "Click a healer's bar to target them", "clickToTarget")
    MakeEditBox(child, y, "Right-click spell (cast on that healer; blank = off)", "rightClickSpell")
    MakeDesc(child, y, "Type a spell name to cast on a healer with right-click — e.g. " ..
        "Innervate (druids), Power Infusion (priests). Leave blank to disable. Bars are " ..
        "clickable only while locked; the overall bar and test-mode simulated healers " ..
        "aren't real units, so clicking them does nothing.")

    MakeHeader(child, y, "Visibility", PANEL_W)
    MakeCheckbox(child, y, "Always show (even when solo)", "showAlways")
    MakeCheckbox(child, y, "Show in raid", "showInRaid")
    MakeCheckbox(child, y, "Show in party", "showInParty")
    MakeDesc(child, y, "Always hidden in arenas and battlegrounds (no healer roles " ..
        "are assigned there). \"Always show\" overrides the rest; while unlocked the " ..
        "bars stay visible so you can position them.")
    child:SetHeight(math.abs(y.v) + 30)
end

local function BuildLayoutTab(child)
    local y = { v = 0 }
    MakeHeader(child, y, "Layout", PANEL_W)
    MakeLabel(child, y, "Growth direction")
    MakeRadioGroup(child, y, {
        { key = "down", label = "Grow downward" },
        { key = "up",   label = "Grow upward" },
    }, HealerManaBarsDB.growth, function(key)
        HealerManaBarsDB.growth = key; Rebuild()
    end)
    MakeLabel(child, y, "Name side")
    MakeRadioGroup(child, y, {
        { key = "left",  label = "Left" },
        { key = "right", label = "Right" },
    }, HealerManaBarsDB.nameSide, function(key)
        HealerManaBarsDB.nameSide = key; Rebuild()
    end)
    MakeLabel(child, y, "Value (%) side")
    MakeRadioGroup(child, y, {
        { key = "right",  label = "Right" },
        { key = "left",   label = "Left" },
        { key = "hidden", label = "Hidden" },
    }, HealerManaBarsDB.valueSide, function(key)
        HealerManaBarsDB.valueSide = key; Rebuild()
    end)
    MakeLabel(child, y, "Status icons side")
    MakeRadioGroup(child, y, {
        { key = "right", label = "Right" },
        { key = "left",  label = "Left" },
    }, HealerManaBarsDB.iconSide, function(key)
        HealerManaBarsDB.iconSide = key; Rebuild()
    end)
    MakeLabel(child, y, "Fill direction")
    MakeRadioGroup(child, y, {
        { key = "lr", label = "Left → right (empties from the right)" },
        { key = "rl", label = "Right → left (empties from the left)" },
    }, HealerManaBarsDB.fillDir, function(key)
        HealerManaBarsDB.fillDir = key; Rebuild()
    end)
    MakeDesc(child, y, "Place elements to suit where the cluster sits. Docking it on the " ..
        "right of your screen? Put status icons on the Left, the name on the Right, and " ..
        "fill Right → left so nothing overflows off-screen and the bar drains toward the edge.")
    MakeSlider(child, y, "Bar width",  "barW",    60, 400, 1)
    MakeSlider(child, y, "Bar height", "barH",     8,  40, 1)
    MakeSlider(child, y, "Spacing",    "spacing",  0,  20, 1)
    MakeMediaDropdown(child, y, "Bar texture", "HealerManaBarsTextureDD", "texture", ns.TextureList)
    MakeMediaDropdown(child, y, "Font", "HealerManaBarsFontDD", "font", ns.FontList)
    MakeSlider(child, y, "Font size", "fontSize", 6, 24, 1)
    local pct = function(v) return string.format("%d%%", v * 100 + 0.5) end
    MakeSlider(child, y, "Overall opacity",    "opacity",   0.2, 1.0, 0.05, nil, pct)
    MakeSlider(child, y, "Background opacity", "bgOpacity", 0.0, 1.0, 0.05, nil, pct)
    if E then
        MakeCheckbox(child, y, "Use ElvUI texture + font (overrides texture & font above)", "useElvUI")
    else
        MakeDesc(child, y, "ElvUI not detected — ElvUI texture/font option hidden.", 0)
    end
    child:SetHeight(math.abs(y.v) + 30)
end

local function BuildColoursTab(child)
    local y = { v = 0 }
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
    child:SetHeight(math.abs(y.v) + 30)
end

local function BuildAlertsTab(child)
    local y = { v = 0 }
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

local function BuildPanel(p)
    if p._built then return end   -- build once; OnShow can fire repeatedly
    p._built = true
    -- The panel can be opened before our PLAYER_LOGIN handler runs, so make sure
    -- the DB is seeded before any widget reads it.
    ns.EnsureDefaults()

    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "dev"

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)
    title:SetText("|cff66ccffHealer Mana Bars|r")
    local verFs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFs:SetPoint("LEFT", title, "RIGHT", 6, 0)
    verFs:SetText("|cff555577v" .. version .. "|r")

    local tabs = {
        { name = "General", build = BuildGeneralTab },
        { name = "Layout",  build = BuildLayoutTab },
        { name = "Colours", build = BuildColoursTab },
        { name = "Alerts",  build = BuildAlertsTab },
    }

    -- Highlight the active tab's button and show only its page.
    local function show(idx)
        for i, t in ipairs(tabs) do
            t.scroll:SetShown(i == idx)
            if i == idx then t.btn:LockHighlight() else t.btn:UnlockHighlight() end
        end
    end

    local prev
    for i, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        btn:SetSize(94, 22)
        btn:SetText(t.name)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -44)
        end
        btn:SetScript("OnClick", function() show(i) end)
        t.btn, prev = btn, btn

        -- One scroll page per tab; only the active one is shown (see show()).
        local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -76)
        scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -30, 10)
        local cont = CreateFrame("Frame", nil, scroll)
        cont:SetSize(PANEL_W, 1)
        scroll:SetScrollChild(cont)
        t.scroll = scroll
        t.build(cont)
    end

    show(1)
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
    ns.EnsureDefaults()
    RegisterPanel()
end)

function ns.OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Twice on purpose: the classic API often opens the parent on first call.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
