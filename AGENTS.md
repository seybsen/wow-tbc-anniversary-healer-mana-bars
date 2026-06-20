# AGENTS.md — Healer Mana Bars

Guidance for AI agents (and humans) working in this repo. Read this before
making changes.

> ## ⚠️ Keep docs in sync — no drift, ever
>
> **Every change that alters behaviour, settings, commands, or the release/build
> setup MUST update the docs in the same change.** Treat docs as part of the
> code; a behaviour change with stale docs is an incomplete change.
>
> Before you finish, check each doc surface and update whatever your change
> touched:
>
> | If you change… | Update |
> |---|---|
> | A user-visible behaviour/feature | `README.md` (features, detection, usage) and this `AGENTS.md` |
> | A setting/default | `DEFAULTS` in `Core.lua` (single source), the panel widget + its `MakeDesc` text, `README.md`, this file |
> | A slash command | `README.md` command table **and** the `/hmb help` text in `Slash.lua` |
> | Anything user-facing, for a release | add a `## X.Y.Z` section to `CHANGELOG.md` and bump `## Version` in the `.toc` (see Release process) |
> | Architecture / flow / API gotchas | this `AGENTS.md` |
>
> In-game `MakeDesc` strings in `HealerManaBarsConfig.lua` are documentation too
> — keep them accurate. After any change, re-read the affected docs and confirm
> they still describe the real behaviour.

## What this is

A lightweight World of Warcraft addon for **Classic Anniversary (TBC 2.5.x)**.
It draws one mana bar per raid healer plus an aggregate "overall" bar, with
regen/drinking indicators and configurable low-mana alerts.

- **Game/engine:** TBC 2.5.x Anniversary. `## Interface: 20505` in the `.toc`.
- **Language:** Lua 5.1 (WoW's sandboxed Lua — no `io`, `os`, `require`, no
  `math.randomseed`, no external Lua libs).
- **Slash command:** `/hmb` (alias `/healermanabars`).
- **Saved variables:** `HealerManaBarsDB` (global, per-account).
- **No build step for the addon itself** — it runs as plain `.lua` from the
  `Interface/AddOns/HealerManaBars/` folder. "Building" only happens at release
  time (zip packaging, see below).

## File map

| File | Role |
|---|---|
| `HealerManaBars.toc` | Load manifest. `## Version` lives here — bump on release. Loads config **before** the runtime modules. |
| `HealerManaBarsConfig.lua` | The **options panel** (Interface → AddOns). Loaded first; runs at panel-open time. |
| `modules/Core.lua` | Saved-var **defaults** (`DEFAULTS` + `ns.EnsureDefaults`/`ns.ApplyDefaults`), media resolvers, colour helpers, `ns.Print`. |
| `modules/Auras.lua` | Regen/drink aura name sets, the combat-log **Mana Tide** tracker, Innervate right-click default. All spell-ID based. |
| `modules/Roster.lua` | Roster scan → ordered entries (`ns.BuildEntries`), healer detection, healer signature, **test-mode** fake roster. |
| `modules/Bars.lua` | Bar **pool** (`ns.bars`/`ns.AcquireBar`), secure click overlay, styling, per-element layout, status icons, cluster stacking. |
| `modules/Alerts.lua` | Low-mana local warning (`ns.FireLocalAlert`) and chat announce (`ns.FireAnnounce`) incl. the SAY/YELL guard. |
| `HealerManaBars.lua` | The **engine**: anchor + visibility, `Rebuild`, `RefreshValues`, low-mana latch, OnUpdate loop, events, login init. |
| `modules/Slash.lua` | The `/hmb` slash command (incl. the `/hmb help` text). |
| `CHANGELOG.md` | Hand-written, shipped in releases (`manual-changelog` in `.pkgmeta`). Keep in sync with `## Version`. |
| `.pkgmeta` | BigWigsMods packager config (what to ship/ignore). |
| `.luacheckrc` | luacheck (linter) config: declares the WoW API globals so only real issues are reported. |
| `.github/workflows/release.yml` | CI: on any tag push, packages + publishes to GitHub Release and CurseForge. |
| `.github/workflows/lint.yml` | CI: runs `luacheck` on every push / PR. |
| `media/` | CurseForge listing art (`banner.png`, `icon.png`). **Not shipped** in the addon zip. |
| `tools/` | Dev-only helpers (`lint.ps1` — Docker-wrapped luacheck). **Not shipped** in the addon zip. |
| `README.md` | User-facing docs / CurseForge description. |

## Architecture & data flow

All files share the **private addon table** (`local _, ns = ...`, passed to
every file of the addon), not the global namespace. The only global the addon
defines is the saved variable `HealerManaBarsDB`. Conventions:

- **Module exports are functions on `ns`** (`ns.BuildEntries`, `ns.StyleBar`,
  `ns.FireAnnounce`, …); module-private state stays file-local (e.g. the Mana
  Tide GUID map never leaves `Auras.lua` — the engine asks `ns.UnitTideIcon`).
- **Shared state lives on `ns`**: `ns.db` (the saved-var alias, set at login by
  `ns.ApplyDefaults`), `ns.anchor` (the movable container), `ns.bars` (the bar
  pool). It is **read at call time, never captured at file scope**, so nothing
  depends on `.toc` load order.
- All cross-file calls run at *runtime* (login / events / panel-open), never at
  file-load time — so each file's `ns.*` are always set by then regardless of
  `.toc` load order.
- Panel ↔ runtime surface: the panel reads `ns.EnsureDefaults`, `ns.DEFAULTS`,
  the live-apply hooks `ns.Rebuild`/`ns.ApplyLock`, and the media helpers
  `ns.TextureList/Path`, `ns.FontList/Path`; the runtime calls `ns.OpenConfig`
  (from `/hmb`).

Runtime loop:

```
PLAYER_LOGIN ─► ApplyDefaults ─► InitAnchor ─► Rebuild
roster/role/zone events ─► Rebuild
OnUpdate (every frame):
  • blink the overall bar (smooth, every frame)
  • throttle to ~10 Hz, then:
      - test mode: TickTestMode
      - if grouped & roster/death signature changed ─► Rebuild
      - else RefreshValues(entries, healers)   ← cheap polling, no UNIT_* events
```

- **`Rebuild()`** rebuilds the bar list from scratch: visibility gate →
  `BuildEntries()` → pool bars → `LayoutBars` → `RefreshValues`.
- **`BuildEntries()`** returns `entries` (what to draw, overall always on top)
  and `healers` (everyone aggregated, even when individual bars are hidden).
- **`RefreshValues()`** aggregates mana, drives the overall bar, the low-mana
  latch (`g_lowActive`, with +5% hysteresis), per-bar colour/icons.
- Bars are **pooled** (`ns.bars`, `ns.AcquireBar` in `Bars.lua`) and re-styled each rebuild, so
  config changes apply live without recreating frames. Element placement is data-
  driven: `AcquireBar` only *creates* the name/value font strings; their anchors
  are (re)applied every rebuild in `LayoutBarElements` (`nameSide`/`valueSide`)
  and `SetBarIcons` (`iconSide`), so the per-element layout options switch live.
  Don't re-add fixed `SetPoint`s in `AcquireBar`. Fill direction (`fillDir`) uses
  `StatusBar:SetReverseFill`, guarded (`if bar.SetReverseFill then …`) since older
  clients lack it.

### Key design points / conventions

- **Mana via power index 0** (`Enum.PowerType.Mana`). This returns real mana for
  **your own** shifted druid, but the server only replicates a *remote* unit's
  **active** power, so a remote druid in Bear/Cat (active power Rage/Energy)
  reports mana 0 — not their real mana. Those druids are detected via
  `UnitPowerType` (Rage→Bear, Energy→Cat) by `ns.EntryShiftedForm` (`Roster.lua`)
  and, when `markShifted` is on (default), drawn greyed with a form icon and
  excluded from the overall average instead of showing a misleading 0%. They
  stay counted in the `Healers (N)` label (`displayCount`) but not in the average
  or the low-mana alert (`readableCount`). Moonkin/Tree/caster/travel keep mana
  as their active power and need no special handling.
- **Healer detection = assigned raid role only** (`UnitGroupRolesAssigned ==
  "HEALER"`). Class-guessing is intentionally avoided. **Exception:** when
  ungrouped (`not IsInGroup()`), the player is treated as a healer (no roles
  exist solo) and the display collapses to just the overall bar.
- **Polling, not events**, for values — trivial cost for a handful of bars and
  it transparently handles units going in/out of range.
- **Regen/drink auras matched by spell ID, not name.** `REGEN_SPELL_IDS` /
  `DRINK_SPELL_IDS` are resolved to the client-locale name at login
  (`BuildAuraNameSets` via `GetSpellInfo`), so detection works on non-English
  clients. Ranks share a name, so one ID per spell covers all ranks. Add new
  indicators by spell ID, never by a hard-coded English string.
- **No bundled libraries.** LibSharedMedia-3.0 and ElvUI are *optional* and read
  if another addon provides them (`LibStub`, `ElvUI[1]`). Built-in texture/font
  fallbacks exist. Do not embed libs; `.pkgmeta` has `enable-nolib-creation: no`.
- **`DEFAULTS` is the single source of truth** for saved-var defaults and lives
  in **`Core.lua`** (not the panel), so the DB is fully seeded even if the panel
  file fails to load. `ns.EnsureDefaults` fills missing keys (and migrates the
  pre-1.0 `blinkThreshold`). There is no second fallback copy to keep in sync.
- **Each bar carries a secure click overlay** (`bar.secure`, a
  `SecureActionButtonTemplate` button covering the bar) for click-to-target /
  the right-click spell. `EnsureSecure` creates it; `UpdateSecure` re-points it
  each rebuild (`type1="target"`/`unit`; plus `type2="spell"`/`spell2` when a
  right-click spell is configured).
  Overlay mouse is on only while **locked**, so unlocked = draggable. Overall and
  test bars have no real unit, so their attributes are cleared (clicks no-op).
  Two settings drive it: `clickToTarget` (master left-click toggle) and
  `rightClickSpell` (the spell cast on right-click; `""` = off, cast by name via
  `spell2`). `rightClickSpell` defaults are **class-dependent**, so — like `pos`
  — it's `nil` in `DEFAULTS` and seeded once at login (Innervate for druids, `""`
  otherwise); `nil` means "never seeded", so a user-cleared `""` is not re-seeded.
  `ComputeInnervate` resolves Innervate's localized name (spell ID, locale-proof)
  for that default. The panel's spell field previews the resolved icon via
  `MakeEditBox(..., { spellIcon = true })` — `GetSpellInfo(name)` is spellbook-
  scoped, so an icon = a spell the player can actually cast.

## WoW API gotchas (important — these caused real bugs)

- **Secure frames can't be touched in combat.** `SetAttribute`, and the
  create/`SetPoint` of a `SecureActionButtonTemplate`, are blocked while
  `InCombatLockdown()`. `EnsureSecure`/`UpdateSecure` no-op in combat; the addon
  registers `PLAYER_REGEN_ENABLED` (→ `Rebuild`) to re-apply once combat ends.
  Consequence: if the roster reorders mid-fight, a bar's click target can briefly
  point at the old unit until combat ends — this is a hard engine limit, not a
  bug to "fix". Never call these on a secure frame from the OnUpdate timer.
- **`SendChatMessage` to `SAY`/`YELL` is blocked from automated code**
  (`ADDON_ACTION_BLOCKED` → "protected function UNKNOWN()"). Those channels need
  a hardware event (key/click). `PARTY`/`RAID`/`RAID_WARNING` are fine from the
  timer. `FireAnnounce`/`ResolveChannel` guard against this; don't reintroduce a
  SAY/YELL auto-send. Solo `AUTO` resolves to **no channel**.
- **ColorPicker has two APIs:** modern `ColorPickerFrame:SetupColorPickerAndShow`
  (Anniversary/retail engine) vs legacy `.func/.previousValues`. `MakeColorRow`
  supports both — keep both paths.
- **Settings panel registration** uses modern `Settings.RegisterCanvasLayout*`
  with a fallback to classic `InterfaceOptions_AddCategory`. Same for opening.
- **The panel is tabbed.** `BuildPanel` only builds the title + tab buttons and,
  per tab, a `UIPanelScrollFrameTemplate` page; each page's widgets live in a
  `Build<Tab>Tab(child)` function (General/Layout/Colours/Alerts) that runs the
  same shared y-cursor over its own scroll child. `show(idx)` toggles page
  visibility + `LockHighlight`. Add a setting's widget to the relevant
  `Build<Tab>Tab`, not `BuildPanel`.
- **Slider/dropdown sub-widgets** (Low/High labels) aren't exposed as parentKeys
  on every build — fall back to `_G[name.."Low"]`. Same defensive pattern for
  radio button text.
- Adding a setting touches **three** places: `DEFAULTS` (`Core.lua`), a widget in
  the relevant `Build<Tab>Tab`, and the consuming logic.

## Testing (no automated harness — it's in-client)

There is no unit-test framework (WoW Lua can't run standalone here). Verify
in-game:

1. Drop the folder in `Interface/AddOns/`, launch, `/reload` after edits
   (a `.toc` change — new/renamed files — needs a full client restart).
2. `/hmb test` — fake-healer roster incl. your live character, for tuning.
3. `/hmb status` — diagnostics (entries, shown bars, pool size, anchor pos).
   Always ask for this output on bug reports.
4. `/hmb unlock` to position; `/hmb lock` when done.
5. Watch for Lua errors on login/zone/role-change (enable `scriptErrors 1` or
   BugSack). Test solo, in a party, and in a raid — visibility and detection
   differ per context (`ShouldShowByContext`).

### Linting

`luacheck` runs in CI on every push/PR (`.github/workflows/lint.yml`) using the
root `.luacheckrc`. **Run it locally before pushing** — it has caught real
undeclared-global bugs that slipped past in-game testing (the game has the API;
the linter doesn't, until it's declared).

There's no native Lua/luacheck on Windows, so the local lint runs through Docker.
`tools/lint.ps1` wraps it (matches CI; first run pulls a small image, then it's
cached):

```powershell
tools\lint.ps1                 # whole repo, same as CI
tools\lint.ps1 HealerManaBars.lua
```

It exits non-zero on warnings/errors. If you have a native `luacheck` (e.g. the
standalone `luacheck.exe` from the lunarmodules/luacheck releases, or via
luarocks), `luacheck .` from the repo root works too. The `tools/` dir is
dev-only and excluded from the release zip (`.pkgmeta`).

The config declares the WoW API globals the addon uses, so undefined-global
warnings mean a **real typo** — fix them, don't silence them. When you call a
new WoW API, add it to `read_globals` in `.luacheckrc`. Cross-file exports go
through the private `ns` table, not globals, so they need no `.luacheckrc` entry;
only add to `globals` when you introduce a genuinely new `_G` name (e.g. a new
saved variable or slash binding).

## Release process

Releases are tag-driven via the BigWigsMods packager (GitHub Action).

**Checklist for a release:**

1. Bump `## Version` in `HealerManaBars.toc`.
2. Add a matching section to the **top** of `CHANGELOG.md` (it ships as the
   release notes; `manual-changelog`).
3. Commit (see git note below).
4. Tag `vX.Y.Z` (annotated) and push the tag — the workflow does the rest:
   ```powershell
   git push origin main
   git push origin vX.Y.Z      # or: git push origin main --follow-tags
   ```
5. The Action packages the zip (excluding `.git*`, `.github`, `.pkgmeta`,
   `media`, `tools`, `.luacheckrc`, `AGENTS.md`, `CLAUDE.md`), creates the
   GitHub Release, and uploads to each store whose secret is set.

The Action triggers on **any** tag (`tags: "**"`), so don't push throwaway tags.

### Distribution stores

Each store needs a secret (repo → Settings → Secrets → Actions) **and** an
`## X-*-ID` line in the `.toc`. A target with an empty secret is silently
skipped, so the env vars are safe to leave in place.

| Store | Secret | TOC field | Status |
|---|---|---|---|
| CurseForge | `CF_API_KEY` | `## X-Curse-Project-ID: 1566721` | live |
| WoWInterface | `WOWI_API_TOKEN` | `## X-WoWI-ID: 27154` | wired (needs secret) |
| Wago.io | `WAGO_API_TOKEN` | `## X-Wago-ID: XKqAVbKy` | wired (needs secret) |
| GitHub Releases | `GITHUB_TOKEN` (auto) | — | live |

To add a store: create the listing on the site to obtain its ID, add the
`## X-*-ID` to the `.toc`, add the secret, and uncomment its env var in
`release.yml`.
