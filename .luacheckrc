-- luacheck configuration for Healer Mana Bars (WoW Classic Anniversary addon).
-- Run with:  luacheck .
--
-- WoW runs Lua 5.1 and exposes a large API as globals that luacheck can't know
-- about, so we declare the ones this addon actually uses. Keeping the list to
-- *used* globals (rather than a blanket ignore) means a typo'd API call like
-- UnitPowerMx still gets flagged as an undefined global.

std = "lua51"
max_line_length = false   -- the source intentionally uses long descriptive lines

-- Don't lint generated/duplicate trees.
exclude_files = {
    ".release/",
    "HealerManaBars/",   -- untracked packaging staging copy (byte-identical)
}

-- Globals this addon defines (read AND written by our own files).
globals = {
    "HealerManaBarsDB",
    "SLASH_HEALERMANABARS1",
    "SLASH_HEALERMANABARS2",
    -- Functions exported for the other file / slash command to call.
    "HealerManaBars_Rebuild",
    "HealerManaBars_ApplyLock",
    "HealerManaBars_ApplyPosition",
    "HealerManaBars_TexturePath",
    "HealerManaBars_TextureList",
    "HealerManaBars_FontPath",
    "HealerManaBars_FontList",
    "HealerManaBars_EnsureDefaults",
    "HealerManaBars_OpenConfig",
}

-- WoW API + UI globals the addon reads (not reassigned). Add new entries here
-- when you call a new API, so genuine typos keep surfacing.
read_globals = {
    -- core / frames
    "CreateFrame", "UIParent", "_G", "wipe", "hooksecurefunc",
    "C_AddOns", "GetAddOnMetadata", "Enum", "LibStub",
    -- class colours / ElvUI
    "RAID_CLASS_COLORS", "ElvUI",
    -- unit + group queries
    "UnitClass", "UnitName", "UnitExists", "UnitIsConnected", "UnitIsDeadOrGhost",
    "UnitGroupRolesAssigned", "UnitPower", "UnitPowerMax", "UnitBuff",
    "IsInRaid", "IsInGroup", "GetNumGroupMembers", "IsInInstance",
    -- chat / alerts
    "SendChatMessage", "DEFAULT_CHAT_FRAME", "ChatTypeInfo",
    "RaidNotice_AddMessage", "RaidWarningFrame", "PlaySound", "SOUNDKIT",
    "SlashCmdList",
    -- options panel widgets
    "UIDropDownMenu_SetWidth", "UIDropDownMenu_Initialize",
    "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton", "UIDropDownMenu_SetText",
    "ColorPickerFrame", "Settings",
    "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
}
