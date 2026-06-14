-- ============================================================================
-- Healer Mana Bars — slash command (/hmb)
-- ----------------------------------------------------------------------------
-- Thin command layer over the ns.* hooks. Keep the help text below in sync
-- with README.md's command table (see AGENTS.md — doc sync).
-- ============================================================================

local _, ns = ...

SLASH_HEALERMANABARS1 = "/hmb"
SLASH_HEALERMANABARS2 = "/healermanabars"
SlashCmdList["HEALERMANABARS"] = function(msg)
    local DB = ns.db
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "lock" then
        DB.locked = true;  ns.ApplyLock(); ns.Print("locked.")
    elseif msg == "unlock" then
        DB.locked = false; ns.ApplyLock(); ns.Print("unlocked — drag the blue handle.")
    elseif msg == "test" then
        DB.testMode = not DB.testMode; ns.Rebuild()
        ns.Print("test mode " .. (DB.testMode and "ON (fake healers)." or "OFF."))
    elseif msg == "up" or msg == "down" then
        DB.growth = msg; ns.Rebuild(); ns.Print("growth: " .. msg)
    elseif msg == "reset" then
        DB.pos = nil; ns.ApplyPosition(); ns.Print("position reset to top-left.")
    elseif msg == "tidedebug" then
        local on = ns.ToggleTideDebug()
        ns.Print("Mana Tide energize debug " .. (on and "ON — drop a Mana Tide Totem near a tracked healer and read the printed spell/src." or "OFF."))
    elseif msg == "config" or msg == "options" or msg == "" then
        if ns.OpenConfig then ns.OpenConfig() end
    elseif msg == "status" then
        -- Lightweight diagnostics for bug reports (see /hmb help).
        local anchor = ns.anchor
        local entries = anchor and anchor._entries
        local shown = 0
        for _, b in ipairs(ns.bars) do if b:IsShown() then shown = shown + 1 end end
        ns.Print("panel file loaded = " .. tostring(ns.OpenConfig ~= nil))
        ns.Print(string.format("testMode=%s  entries=%d  shownBars=%d  pool=%d",
            tostring(DB.testMode), entries and #entries or 0, shown, #ns.bars))
        if anchor then
            local l, b = anchor:GetLeft(), anchor:GetBottom()
            ns.Print(string.format("anchor shown=%s  x=%s y=%s",
                tostring(anchor:IsShown()),
                l and tostring(math.floor(l)) or "nil",
                b and tostring(math.floor(b)) or "nil"))
        else
            ns.Print("|cffff4444anchor is NIL — init never ran (check for a login error).|r")
        end
    else
        ns.Print("commands:")
        ns.Print("  /hmb              — open the options panel")
        ns.Print("  /hmb lock|unlock  — toggle dragging")
        ns.Print("  /hmb test         — toggle test mode")
        ns.Print("  /hmb up|down      — growth direction")
        ns.Print("  /hmb reset        — reset position to top-left")
        ns.Print("  /hmb status       — print diagnostics")
        ns.Print("tip: while locked, left-click a bar to target; right-click casts your configured spell (see options).")
    end
end
