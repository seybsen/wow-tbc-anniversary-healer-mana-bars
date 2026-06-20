# Design: Mark shapeshifted druids

**Date:** 2026-06-20
**Addon:** Healer Mana Bars (TBC 2.5.x Anniversary)
**Target version:** 1.0.17

## Problem

The addon reads mana with `UnitPower(unit, 0)` (the mana power index). For the
**player's own** druid this returns real mana even while shifted, but for **other
raid members** the server only replicates a unit's *currently active* power type.
A druid in Bear (active power = Rage) or Cat (active power = Energy) does not have
their mana replicated, so `UnitPower(otherDruid, 0)` returns **0**. Today that
renders as a misleading **0%** bar — indistinguishable from an out-of-mana healer
— and the 0 drags down the overall aggregate.

This was confirmed by research (Warcraft Wiki API notes; the comparable "Raid
Mana TBC" addon hides shifted druids; Druid Bar addons *estimate* rather than
read shifted mana). The existing AGENTS.md claim that "a shapeshifted druid still
reports real mana" is true only for the local player, not remote units.

## Goal

Make a remote shifted druid's bar honestly say "mana hidden — they're in form"
rather than "0% / out of mana", and stop their unreadable mana from polluting the
overall average.

## Core insight (why detection is reliable)

A unit's **active** power type *is* replicated to all clients. So:

```
shifted-mana-hidden druid  ⇔  class == "DRUID"
                              AND UnitPowerType(unit) ∈ { Rage(1), Energy(3) }
```

This both flags the condition and identifies the form (Rage → Bear, Energy →
Cat). Moonkin, Tree of Life, caster, and travel/aquatic/flight forms keep **mana**
as their active power type, so they fall through to the normal mana bar with no
special handling. No estimation, no guessing.

## Behavior (decisions locked in brainstorming)

A shifted druid's bar:

- **Greyed out**, empty fill (value 0), alpha 0.6, grey status-bar color, name
  text dimmed — reusing the existing "dead corpse" styling.
- Value text shows an **em-dash `—`** where the `%` normally is (not `0%`).
- The **form icon** (Bear / Cat) is shown in the existing status-icon row.
- **Excluded from the overall mana average** (their unreadable mana never enters
  `sumCur`/`sumMax`).
- **Still counted** in the overall bar's `Healers (N)` label (they are present
  healers, just momentarily unavailable). N and the averaged % may therefore
  differ (e.g. `Healers (5)` while only 4 contribute mana) — this is intended.
- Behind a new **toggle, default on**. When off → legacy behavior (counted in the
  average, shown as 0%).
- Shifted druids **stay in their normal roster position** (not sunk to the bottom
  like corpses), to avoid bars jumping when a druid flickers forms.

Precedence per bar: `overall → dead → shifted → normal`. A dead druid shows
"dead" (dead wins over shifted).

## Implementation

### 1. Detection — `Roster.lua`

New export `ns.EntryShiftedForm(entry)` returning `"bear"`, `"cat"`, or `nil`:

- Real unit: `UnitClass(unit) == "DRUID"` and `UnitPowerType(unit)` is Rage →
  `"bear"`, Energy → `"cat"`, else `nil`.
- Fake/test entry: return `entry.fake.form` (nil if unset).

Use `Enum.PowerType.Rage`/`.Energy` with numeric fallbacks (`1`/`3`), matching the
existing `MANA` pattern.

### 2. Per-tick computation — `RefreshValues` (`HealerManaBars.lua`)

Form is computed **every tick**, like `IsEntryDead`, because shifting does not
change the healer signature (so no Rebuild fires). In the healer aggregate loop,
split the single counter into two:

```lua
local sumCur, sumMax, readableCount, displayCount = 0, 0, 0, 0
for _, e in ipairs(healers) do
    local cur, max = UnitMana(e)
    e._cur, e._max = cur, max
    e._dead    = IsEntryDead(e)
    e._shifted = (DB.markShifted ~= false) and ns.EntryShiftedForm(e) or nil
    if not e._dead then
        displayCount = displayCount + 1                 -- counts shifted too
        if not e._shifted and max > 0 then
            sumCur, sumMax = sumCur + cur, sumMax + max
            readableCount = readableCount + 1           -- average + alert basis
        end
    end
end
```

- Overall label uses `displayCount`: `Healers (%d)`.
- Low-mana guard switches from the old `healerCount` to **`readableCount > 0`**,
  preventing a false low-mana alert when every healer is shifted (average 0 but
  nothing actually readable).

### 3. Render branch — `RefreshValues`

Add a branch after the `e._dead` branch, before the normal branch:

```lua
elseif e._shifted then
    bar:SetValue(0)
    bar:SetAlpha(0.6)
    bar:SetStatusBarColor(0.35, 0.35, 0.35)
    bar.label:SetText("|cff808080" .. (e.name or "?") .. "|r")
    bar.value:SetText("|cff808080—|r")
    wipe(g_iconScratch)
    g_iconScratch[1] = ns.ShiftedFormIcon(e._shifted)   -- bear/cat texture
    ns.SetBarIcons(bar, g_iconScratch)
```

Form icon textures (helper `ns.ShiftedFormIcon`, in `Roster.lua` or `Bars.lua`):

- Bear: `Interface\Icons\Ability_Racial_BearForm`
- Cat:  `Interface\Icons\Ability_Druid_CatForm`

(Exact texture paths to be confirmed in-game during implementation.)

### 4. Setting — `Core.lua` + panel

- `DEFAULTS.markShifted = true` in `modules/Core.lua` (near `hideDead`).
- New checkbox in `HealerManaBarsConfig.lua`, placed immediately after the
  "Hide dead healers" checkbox (same tab): **"Mark shapeshifted druids (grey
  out, show form icon, exclude from overall)"**, bound to `markShifted`, with a
  `MakeDesc` line explaining a remote druid in Bear/Cat can't report mana, so the
  bar is greyed with a form icon and left out of the average.

### 5. Test-mode demo — `Roster.lua`

Add `form = "cat"` to the fake druid *Zlarx* in `MakeFakeHealers` so `/hmb test`
shows the treatment live for tuning.

### 6. Docs & housekeeping (same change — AGENTS.md no-drift rule)

- Add `UnitPowerType` to `read_globals` in `.luacheckrc` (UnitClass, UnitPower,
  UnitPowerMax already present).
- **Fix AGENTS.md:** correct the "a shapeshifted druid still reports real mana"
  note to clarify it holds only for the local player; document the remote-unit
  replication limitation and this new marking behavior.
- README features section: describe the shifted-druid marking + toggle.
- `CHANGELOG.md`: add `## 1.0.17` section.
- Bump `## Version` to `1.0.17` in `HealerManaBars.toc`.

## Edge cases

- **Dead + shifted** → "dead" wins (dead branch precedes shifted branch).
- **All healers shifted** → `readableCount == 0` → no false low-mana alert;
  overall shows 0% with `Healers (N)` reflecting the present (shifted) healers.
- **Setting off** → legacy behavior (0%, counted in average).
- **Non-druid Energy/Rage users** (rogues, warriors) → never matched (class gate).
- **Combat** → pure styling/text updates, no secure-frame attribute writes, so no
  `InCombatLockdown` concern.
- **Form flicker** → bars stay in place (no re-sort), only restyle per tick.

## Out of scope

- Estimating a shifted druid's actual mana (the Druid Bar approach) — rejected as
  lossy and heavy for a lightweight addon.
- Sinking shifted druids to the bottom of the list.
- The local player's own druid already reports real mana while shifted; unchanged.

## Testing (in-client, per AGENTS.md)

1. `/hmb test` → Zlarx shows greyed bar, `—`, Cat icon; overall `Healers (N)`
   includes Zlarx but its mana is not averaged.
2. Live: party/raid with a druid healer; shift to Bear/Cat and confirm the bar
   greys with the correct form icon and drops out of the average, then returns to
   a normal bar on shifting back to caster/Tree/Moonkin.
3. Toggle the setting off → confirm legacy 0% behavior returns.
4. `luacheck` clean (run `tools/lint.ps1`).
