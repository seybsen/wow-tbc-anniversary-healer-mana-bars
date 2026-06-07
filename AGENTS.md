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
> | A setting/default | `DEFAULTS` (config) **and** `CORE_FALLBACK` (runtime), the panel widget + its `MakeDesc` text, `README.md`, this file |
> | A slash command | `README.md` command table **and** the `/hmb help` text in `HealerManaBars.lua` |
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
| `HealerManaBars.toc` | Load manifest. `## Version` lives here — bump on release. Loads config **before** runtime. |
| `HealerManaBarsConfig.lua` | Saved-var **defaults** (`DEFAULTS`), `HealerManaBars_EnsureDefaults`, and the **options panel** (Interface → AddOns). Loaded first. |
| `HealerManaBars.lua` | Runtime: roster → bars, value refresh, alerts, slash command, events. |
| `CHANGELOG.md` | Hand-written, shipped in releases (`manual-changelog` in `.pkgmeta`). Keep in sync with `## Version`. |
| `.pkgmeta` | BigWigsMods packager config (what to ship/ignore). |
| `.luacheckrc` | luacheck (linter) config: declares the WoW API globals so only real issues are reported. |
| `.github/workflows/release.yml` | CI: on any tag push, packages + publishes to GitHub Release and CurseForge. |
| `.github/workflows/lint.yml` | CI: runs `luacheck` on every push / PR. |
| `media/` | CurseForge listing art (`banner.png`, `icon.png`). **Not shipped** in the addon zip. |
| `README.md` | User-facing docs / CurseForge description. |

> **Untracked `HealerManaBars/` subfolder:** a byte-identical packaging staging
> copy. It is **not** loaded by the game and **not** tracked by git. Never edit
> it and never `git add` it — always edit the root files and add files
> explicitly (avoid `git add .`).

## Architecture & data flow

The two files communicate through a small set of globals:

- Config → core: `HealerManaBars_EnsureDefaults()`, the `HealerManaBarsDB` table.
- Core → config: hooks `HealerManaBars_Rebuild`, `HealerManaBars_ApplyLock`,
  `HealerManaBars_ApplyPosition`, and media helpers
  `HealerManaBars_TextureList/Path`, `HealerManaBars_FontList/Path`.
- `HealerManaBars_OpenConfig()` is called by `/hmb`.

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
- Bars are **pooled** (`g_bars`, `AcquireBar`) and re-styled each rebuild, so
  config changes apply live without recreating frames.

### Key design points / conventions

- **Mana via power index 0** (`Enum.PowerType.Mana`), so a shapeshifted druid
  still reports real mana.
- **Healer detection = assigned raid role only** (`UnitGroupRolesAssigned ==
  "HEALER"`). Class-guessing is intentionally avoided. **Exception:** when
  ungrouped (`not IsInGroup()`), the player is treated as a healer (no roles
  exist solo) and the display collapses to just the overall bar.
- **Polling, not events**, for values — trivial cost for a handful of bars and
  it transparently handles units going in/out of range.
- **No bundled libraries.** LibSharedMedia-3.0 and ElvUI are *optional* and read
  if another addon provides them (`LibStub`, `ElvUI[1]`). Built-in texture/font
  fallbacks exist. Do not embed libs; `.pkgmeta` has `enable-nolib-creation: no`.
- **`CORE_FALLBACK`** in the runtime backstops every DB key the core touches, in
  case the config file fails to load. Keep it in sync with `DEFAULTS` when you
  add a setting.

## WoW API gotchas (important — these caused real bugs)

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
- **Slider/dropdown sub-widgets** (Low/High labels) aren't exposed as parentKeys
  on every build — fall back to `_G[name.."Low"]`. Same defensive pattern for
  radio button text.
- Adding a setting touches up to **four** places: `DEFAULTS` (config),
  `CORE_FALLBACK` (runtime), a widget in `BuildPanel`, and the consuming logic.

## Testing (no automated harness — it's in-client)

There is no unit-test framework (WoW Lua can't run standalone here). Verify
in-game:

1. Drop the folder in `Interface/AddOns/`, launch, `/reload` after edits.
2. `/hmb test` — fake-healer roster incl. your live character, for tuning.
3. `/hmb status` — diagnostics (entries, shown bars, pool size, anchor pos).
   Always ask for this output on bug reports.
4. `/hmb unlock` to position; `/hmb lock` when done.
5. Watch for Lua errors on login/zone/role-change (enable `scriptErrors 1` or
   BugSack). Test solo, in a party, and in a raid — visibility and detection
   differ per context (`ShouldShowByContext`).

### Linting

`luacheck` runs in CI on every push/PR (`.github/workflows/lint.yml`) using the
root `.luacheckrc`. Run it locally before pushing if you have it:

```sh
luacheck .
```

The config declares the WoW API globals the addon uses, so undefined-global
warnings mean a **real typo** — fix them, don't silence them. When you call a
new WoW API, add it to `read_globals` in `.luacheckrc`; when you add a new
`HealerManaBars_*` export or saved-var global, add it to `globals`.

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
   `media`, `.luacheckrc`, `AGENTS.md`, `CLAUDE.md`), creates the GitHub
   Release, and uploads to each store whose secret is set.

The Action triggers on **any** tag (`tags: "**"`), so don't push throwaway tags.

### Distribution stores

Each store needs a secret (repo → Settings → Secrets → Actions) **and** an
`## X-*-ID` line in the `.toc`. A target with an empty secret is silently
skipped, so the env vars are safe to leave in place.

| Store | Secret | TOC field | Status |
|---|---|---|---|
| CurseForge | `CF_API_KEY` | `## X-Curse-Project-ID: 1566721` | live |
| WoWInterface | `WOWI_API_TOKEN` | `## X-WoWI-ID: 27153` | wired (needs secret) |
| Wago.io | `WAGO_API_TOKEN` | `## X-Wago-ID` | env wired (needs project ID + secret) |
| GitHub Releases | `GITHUB_TOKEN` (auto) | — | live |

To add a store: create the listing on the site to obtain its ID, add the
`## X-*-ID` to the `.toc`, add the secret, and uncomment its env var in
`release.yml`.
