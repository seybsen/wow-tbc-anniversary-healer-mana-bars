# Changelog

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
