# Mark Shapeshifted Druids — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a remote druid in Bear/Cat form as a greyed, em-dashed bar with a form icon, excluded from the overall mana average, behind a default-on toggle.

**Architecture:** Detection is `class == "DRUID"` + `UnitPowerType ∈ {Rage, Energy}` (the active power type *is* replicated for other units, unlike mana). Form is computed per-tick in `RefreshValues` (shifting doesn't change the healer signature, so no Rebuild fires). The render reuses the existing "dead corpse" greyed styling and the status-icon row.

**Tech Stack:** Lua 5.1 (WoW sandbox), TBC 2.5.x Anniversary client. No standalone test runner — the automated gate is `luacheck`; behavior is verified in-client via `/hmb test` and `/hmb status`.

## Global Constraints

- `## Interface: 20505`; Lua 5.1 sandbox — no `io`/`os`/`require`, no external libs.
- Cross-file exports go on the private `ns` table, read at call time, never captured at file scope.
- New WoW API globals must be added to `read_globals` in `.luacheckrc` or luacheck fails CI.
- Any behaviour/setting change must update docs in the **same** change (README, AGENTS.md, CHANGELOG, `.toc` `## Version`, panel `MakeDesc`).
- `DEFAULTS` in `modules/Core.lua` is the single source of truth for saved-var defaults.
- Target release version: **1.0.17**.

**Testing convention (all tasks):** there is no unit-test harness. Each task's "test" step = run `luacheck` (via `tools/lint.ps1` or `luacheck .`) and confirm zero warnings/errors, plus the in-client check noted in the task. Reload with `/reload` after `.lua` edits.

---

### Task 1: Detection + form-icon helpers (`Roster.lua`, `.luacheckrc`)

**Files:**
- Modify: `modules/Roster.lua` (add two `ns` exports near the top, after `local _, ns = ...`)
- Modify: `.luacheckrc` (add `UnitPowerType` to `read_globals`)

**Interfaces:**
- Produces: `ns.EntryShiftedForm(entry) -> "bear" | "cat" | nil` — given a build entry (`{ unit = "raidN" }` or `{ fake = {...} }`), returns the mana-hiding form or nil.
- Produces: `ns.ShiftedFormIcon(form) -> texturePath` — maps `"bear"`/`"cat"` to an icon path.

- [ ] **Step 1: Add the power-type constants and helpers to `Roster.lua`**

Insert after `local _, ns = ...` (line 9):

```lua
-- Active power type IS replicated for other units (unlike a shifted druid's
-- mana, power index 0, which is not). So a remote druid in Bear reports Rage and
-- in Cat reports Energy — that's how we detect a mana-hidden form and which one.
local RAGE   = (Enum and Enum.PowerType and Enum.PowerType.Rage)   or 1
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local SHIFT_ICON = {
    bear = "Interface\\Icons\\Ability_Racial_BearForm",
    cat  = "Interface\\Icons\\Ability_Druid_CatForm",
}

-- "bear" / "cat" when this entry is a druid whose mana can't be read (shifted),
-- else nil. Fakes carry an explicit form field for test mode.
function ns.EntryShiftedForm(entry)
    if entry.fake then return entry.fake.form end
    if not entry.unit then return nil end
    local _, class = UnitClass(entry.unit)
    if class ~= "DRUID" then return nil end
    local ptype = UnitPowerType(entry.unit)
    if ptype == RAGE   then return "bear" end
    if ptype == ENERGY then return "cat"  end
    return nil
end

function ns.ShiftedFormIcon(form)
    return SHIFT_ICON[form]
end
```

- [ ] **Step 2: Declare `UnitPowerType` for the linter**

In `.luacheckrc`, find the `read_globals` list containing `UnitPower` / `UnitPowerMax` and add `"UnitPowerType",` alongside them (keep alphabetical/local ordering as the file uses).

- [ ] **Step 3: Lint**

Run: `tools\lint.ps1` (or `luacheck .`)
Expected: zero warnings/errors. (Before Step 2, luacheck would flag `UnitPowerType` as an undefined global — confirming the declaration is what fixes it.)

- [ ] **Step 4: Commit**

```bash
git add modules/Roster.lua .luacheckrc
git commit -m "feat: detect shapeshifted druids via active power type"
```

---

### Task 2: Aggregate split + shifted render branch (`HealerManaBars.lua`)

**Files:**
- Modify: `modules/../HealerManaBars.lua` — `RefreshValues` (lines 56–152)

**Interfaces:**
- Consumes: `ns.EntryShiftedForm`, `ns.ShiftedFormIcon` (Task 1); `DB.markShifted` (Task 3 — until then `nil`, and `DB.markShifted ~= false` treats nil as on, so this task is testable before the setting exists).
- Produces: per-entry transient `e._shifted` used only within `RefreshValues`.

- [ ] **Step 1: Replace the aggregate loop with the two-counter version**

Replace lines 62–70 (the `local sumCur, sumMax, healerCount` loop) with:

```lua
    -- Two counters: displayCount drives the "Healers (N)" label (every present,
    -- alive healer, incl. shifted druids); readableCount + the sums drive the
    -- average and the low-mana alert (only healers whose mana we can actually
    -- read — not shifted, not dead, max>0).
    local sumCur, sumMax, readableCount, displayCount = 0, 0, 0, 0
    for _, e in ipairs(healers) do
        local cur, max = UnitMana(e)
        e._cur, e._max = cur, max
        e._dead    = IsEntryDead(e)
        e._shifted = (DB.markShifted ~= false) and ns.EntryShiftedForm(e) or nil
        if not e._dead then
            displayCount = displayCount + 1
            if not e._shifted and max > 0 then
                sumCur, sumMax, readableCount = sumCur + cur, sumMax + max, readableCount + 1
            end
        end
    end
```

- [ ] **Step 2: Point the low-mana guard and label at the right counters**

In the `overall` branch, change the `low` line (was `local low = (healerCount > 0) and ...`) to use `readableCount`:

```lua
            local low = (readableCount > 0) and (pct * 100 < threshold)
```

And the label line (was `... Healers (%d)..., healerCount`) to use `displayCount`:

```lua
            bar.label:SetText(string.format("|cffffffffHealers (%d)|r", displayCount))
```

- [ ] **Step 3: Add the shifted render branch**

Between the `elseif e._dead then` block (ends line 119 with its `SetBarIcons(bar, EMPTY_ICONS)`) and the final `else` (normal bar, line 120), insert a new branch:

```lua
        elseif e._shifted then
            -- Remote shifted druid: mana not readable. Grey it, show an em-dash
            -- and the form icon; it's excluded from the average above.
            bar:SetValue(0)
            bar:SetAlpha(0.6)
            bar:SetStatusBarColor(0.35, 0.35, 0.35)
            bar.label:SetText("|cff808080" .. (e.name or "?") .. "|r")
            bar.value:SetText("|cff808080—|r")
            wipe(g_iconScratch)
            g_iconScratch[1] = ns.ShiftedFormIcon(e._shifted)
            ns.SetBarIcons(bar, g_iconScratch)
```

- [ ] **Step 4: Lint**

Run: `tools\lint.ps1`
Expected: zero warnings/errors.

- [ ] **Step 5: In-client smoke check**

`/reload`, then in a group with a druid healer: shift to Cat → that bar greys, shows `—` and the cat icon, and the overall `Healers (N)` keeps counting them while the % rises (their 0 no longer drags it). Shift back → normal bar returns. (Full test-mode demo comes in Task 4.)

- [ ] **Step 6: Commit**

```bash
git add HealerManaBars.lua
git commit -m "feat: grey shifted druids and drop them from the mana average"
```

---

### Task 3: Setting — default + panel toggle (`Core.lua`, `HealerManaBarsConfig.lua`)

**Files:**
- Modify: `modules/Core.lua` — `DEFAULTS` (after the `hideDead` line, ~line 23)
- Modify: `HealerManaBarsConfig.lua` — `BuildGeneralTab` (after the `hideDead` checkbox, ~line 286)

**Interfaces:**
- Produces: `DB.markShifted` (boolean, default `true`) — consumed by Task 2.

- [ ] **Step 1: Add the default**

In `modules/Core.lua`, after the `hideDead` line add:

```lua
    markShifted  = true,       -- grey shifted druids (Bear/Cat), show form icon, exclude from overall
```

- [ ] **Step 2: Add the panel checkbox + description**

In `HealerManaBarsConfig.lua` `BuildGeneralTab`, immediately after the `hideDead` `MakeCheckbox` line, add:

```lua
    MakeCheckbox(child, y, "Mark shapeshifted druids (grey out, show form icon, exclude from overall)", "markShifted")
    MakeDesc(child, y, "A druid in Bear or Cat form doesn't report mana for other " ..
        "raid members (the game only sends their active Rage/Energy). Rather than " ..
        "show a misleading 0%, their bar is greyed with a form icon and left out " ..
        "of the overall average. Your own druid always reports real mana.")
```

- [ ] **Step 3: Lint**

Run: `tools\lint.ps1`
Expected: zero warnings/errors.

- [ ] **Step 4: In-client check**

`/reload`, open options (`/hmb config`) → General tab shows the new checkbox (checked). Uncheck it → a shifted druid reverts to the legacy 0% bar and is counted in the average again.

- [ ] **Step 5: Commit**

```bash
git add modules/Core.lua HealerManaBarsConfig.lua
git commit -m "feat: add 'Mark shapeshifted druids' option (default on)"
```

---

### Task 4: Test-mode demo (`Roster.lua`)

**Files:**
- Modify: `modules/Roster.lua` — `MakeFakeHealers` (the `Zlarx` entry, ~line 55)

**Interfaces:**
- Consumes: `ns.EntryShiftedForm` reads `entry.fake.form` (Task 1).

- [ ] **Step 1: Give the fake druid a form**

In `MakeFakeHealers`, add `form = "cat"` to the `Zlarx` table:

```lua
        { name = "Zlarx",    class = "DRUID",   max = 3900, form = "cat",
          regenIcon = "Interface\\Icons\\Spell_Nature_Lightning" },          -- Innervate
```

- [ ] **Step 2: Lint**

Run: `tools\lint.ps1`
Expected: zero warnings/errors.

- [ ] **Step 3: In-client check**

`/reload`, `/hmb test` → Zlarx renders greyed with `—` and the cat icon; the overall `Healers (N)` still includes Zlarx but its mana is not in the average. Verify `/hmb status` runs without error.

- [ ] **Step 4: Commit**

```bash
git add modules/Roster.lua
git commit -m "test: demo shifted-druid marking in test mode (Zlarx in Cat)"
```

---

### Task 5: Docs + version bump

**Files:**
- Modify: `AGENTS.md` (the "Mana via power index 0" key-design bullet)
- Modify: `README.md` (features/detection section)
- Modify: `CHANGELOG.md` (new top section)
- Modify: `HealerManaBars.toc` (`## Version`)

- [ ] **Step 1: Correct the AGENTS.md note**

Replace the existing bullet — "**Mana via power index 0** (`Enum.PowerType.Mana`), so a shapeshifted druid still reports real mana." — with:

```markdown
- **Mana via power index 0** (`Enum.PowerType.Mana`). This returns real mana for
  **your own** shifted druid, but the server only replicates a *remote* unit's
  **active** power, so a remote druid in Bear/Cat (active power Rage/Energy)
  reports mana 0. Those druids are detected via `UnitPowerType` (Rage→Bear,
  Energy→Cat) and, when `markShifted` is on, drawn greyed with a form icon and
  excluded from the overall average instead of showing a misleading 0%
  (`ns.EntryShiftedForm` in `Roster.lua`). Moonkin/Tree/caster/travel keep mana
  as their active power and need no special handling.
```

- [ ] **Step 2: README features**

Add a feature line near the detection/usage description, e.g.:

```markdown
- **Shapeshift-aware:** a raid druid in Bear or Cat form (whose mana the game
  doesn't report to others) is greyed with a form icon and left out of the
  overall average, rather than shown as a misleading 0%. Toggle: "Mark
  shapeshifted druids" (General tab, on by default).
```

- [ ] **Step 3: CHANGELOG**

Add to the top of `CHANGELOG.md`:

```markdown
## 1.0.17

- Shapeshifted druids (Bear/Cat) in your raid no longer show a misleading 0%
  mana bar. Their mana isn't reported to other players, so the bar is greyed
  with a form icon and excluded from the overall average. New "Mark
  shapeshifted druids" option (General tab, on by default) controls this.
```

- [ ] **Step 4: Bump the TOC version**

In `HealerManaBars.toc`, set `## Version:` to `1.0.17`.

- [ ] **Step 5: Lint (sanity) + commit**

Run: `tools\lint.ps1` (no code change, but confirm still clean)

```bash
git add AGENTS.md README.md CHANGELOG.md HealerManaBars.toc
git commit -m "docs: document shifted-druid handling; bump to 1.0.17"
```

---

## Self-Review

**Spec coverage:** detection (T1), per-tick render + aggregate split + readableCount alert guard (T2), setting/default/panel/MakeDesc (T3), test-mode demo (T4), `.luacheckrc` global (T1), AGENTS.md fix + README + CHANGELOG + `.toc` (T5). All spec sections map to a task. Edge cases (dead>shifted precedence, all-shifted no-false-alert, setting-off legacy, combat-safe) are realized by the branch ordering and `readableCount` guard in T2 — no separate task needed.

**Placeholder scan:** none — every code step carries the literal edit.

**Type consistency:** `ns.EntryShiftedForm`/`ns.ShiftedFormIcon` defined in T1 and consumed verbatim in T2/T4; `DB.markShifted` defined T3, read T2 with nil-safe `~= false`; `e._shifted`/`e._dead`/`displayCount`/`readableCount` named consistently within T2.
