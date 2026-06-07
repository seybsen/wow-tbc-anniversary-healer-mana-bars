# Changelog

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
- **Visibility** options — show/hide per context: raid, party, battleground,
  arena, or always (even solo). The bars still stay visible while unlocked so
  they can be positioned.
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
