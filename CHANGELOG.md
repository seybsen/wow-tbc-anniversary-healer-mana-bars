# Changelog

## 1.0.16

### Changed
- **Internal restructuring only — no behaviour changes.** The runtime is split
  from one large file into focused modules (`modules/Core·Auras·Roster·Bars·
  Alerts·Slash.lua` plus the display engine). Settings, commands, and visuals
  are unchanged; saved variables carry over as-is.

## 1.0.15

### Changed
- **The low-mana alert threshold now defaults to 15%** (was 30%). This drives the
  blink, the local raid-warning, and the chat announce. Existing setups keep
  their saved value — only fresh installs (or a reset DB) get the new default.

## 1.0.14

### Added
- **The right-click spell field now previews the spell's icon** as you type. The
  icon (and the spell's name) appears when the entry resolves to a spell you can
  cast; otherwise it shows "not found" — so you get instant confirmation the name
  is right.

## 1.0.13

### Added
- **Per-element layout options** (Layout section): independently place the
  **name** (left/right), the **% value** (left/right/hidden), the **status
  icons** (left/right), and the **fill direction** (left→right or right→left).
  Defaults are unchanged, so existing setups look the same.
- Lets you **mirror the bars for a right-of-screen cluster** — icons on the Left,
  name on the Right, fill right→left, so nothing overflows off-screen and the bar
  drains toward the edge.

### Changed
- **The options panel is now tabbed** (General · Layout · Colours · Alerts)
  instead of one long scrolling list, so settings are easier to find.

## 1.0.12

### Added
- **Click a healer's bar to target them.** Each individual bar is now an
  interactive unit button — left-click targets that healer.
- **Right-click to cast a configurable spell** on that healer. Set any spell name
  in the new *Interaction* options (e.g. Innervate, Power Infusion); it defaults
  to **Innervate for druids** and blank for everyone else, and a blank field
  disables right-click. Cast by name, so localized clients work.
- Bars are only clickable while **locked**; unlock as before to drag the cluster.
  The overall and test-mode bars aren't tied to a real unit, so clicking them
  does nothing. Because target/cast are protected, the click mapping can't change
  mid-combat — it re-syncs to the current roster the moment you leave combat.
- Click-to-target itself can also be disabled in the *Interaction* options.

## 1.0.11

### Added
- **Mana Tide Totem indicator (via combat log).** Mana Tide puts no aura on
  players, so it's detected from the totem's energize ticks and shown for the
  totem's duration. Range-limited — the combat log only reports healers near you.

## 1.0.10

### Fixed
- **Mana Spring Totem now shows the regen indicator.** Detection was keyed to the
  totem's cast spell rather than the "Mana Spring" aura that lands on party
  members (spell 5677). Verified in-game.

### Changed
- Dropped Mana Tide Totem and Shadowfiend from the regen indicator: in TBC they
  restore mana without putting any aura on the player, so there's nothing to
  detect by scanning buffs.

## 1.0.9

### Changed
- The addon is now **always hidden in arenas and battlegrounds** — no healer
  roles are assigned there, so it could only ever show an empty bar.

## 1.0.8

### Fixed
- **Regen/drink indicators now work on non-English clients.** Innervate, Mana
  Tide Totem and the drinking buff were matched by their English names, so the
  icons never showed on de/fr/es/etc. clients. They're now matched by spell ID
  and resolved to your client's language, and the match is rank-independent.

### Changed
- Internal cleanup, no behaviour change: the two files now share state through a
  private addon table instead of the global namespace, and the saved-variable
  defaults live in a single place (removing a duplicated fallback copy).

## 1.0.7

### Fixed
- Release packages were **empty through 1.0.6**: inline `# ...` comments on
  `.pkgmeta` ignore entries broke the packager's file copy (it does not strip
  inline comments and `eval`s the patterns). Moved all notes to full-line
  comments — this is the first build that actually ships the addon files.

## 1.0.6

### Fixed
- Corrected the Wago.io upload credentials in the release pipeline. No in-game
  changes.

## 1.0.5

### Changed
- Added **WoWInterface** and **Wago.io** as release targets alongside CurseForge
  and GitHub. No in-game changes.

## 1.0.4

### Changed
- Clarified the in-game options text: the healer-detection help now notes that a
  single bar tracks your own mana when solo.

## 1.0.3

### Changed
- Solo (ungrouped) now shows a single bar tracking your own mana instead of
  nothing — raid roles don't exist solo, so the overall bar stands in for you.

### Fixed
- Low-mana auto-announce no longer triggers `ADDON_ACTION_BLOCKED`: **Say** and
  **Yell** can't be sent from automated code, so those channels are skipped and
  **Auto** announces to nobody when solo. The local warning is unaffected.

## 1.0.2

### Added
- **Visibility** options — show/hide per context: raid, party, or always (even
  solo). The bars still stay visible while unlocked so they can be positioned.
- **Only the overall bar** option — hide the individual healer bars and show
  just the aggregate (still computed from the whole group).

## 1.0.1

### Added
- **Overall opacity** and **Background opacity** sliders (Layout section) — fade
  the whole cluster and/or the empty bar track independently.

## 1.0.0

First public release.

### Added
- Per-healer mana bars plus an **overall** aggregate bar; healers detected via
  assigned raid role.
- Mana-regen indicators for **Innervate** and **Mana Tide Totem**, and a
  **drinking** indicator, shown as icons beside each bar.
- **Low-mana alerts**: blink the overall bar, a local raid-warning banner +
  sound, and an optional chat announce (`Healer mana below X%`) to a chosen
  channel, with hysteresis so it fires once per dip.
- **Hide dead healers** option; when off, dead healers are greyed out and sorted
  to the bottom. Dead healers are excluded from the overall aggregate either way.
- Bar colour modes: **class**, **static** (colour picker), or **gradient**
  (green at full → red at empty). Names are always class-coloured.
- Configurable **width, height, spacing, growth direction, bar texture and
  font** (with LibSharedMedia support and a font-size slider).
- Optional **ElvUI** texture/font matching.
- **Lock/unlock** dragging; the display hides while solo unless unlocked or in
  test mode.
- **Test mode** roster for solo tuning that includes your own character live
  (real name and mana).
- Options panel under *Interface → AddOns*, plus `/hmb` slash commands.
