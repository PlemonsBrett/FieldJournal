# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Field Journal is a World of Warcraft addon (targeting the "WoW Forever" beta client, `Interface: 16001`) that passively records quests, conversations, kills/loot, and crafting into a per-character journal UI (`/fj` or `/fieldjournal`). It is beta software developed and tested against one live account. See [README.md](README.md) for the full feature description and [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor workflow.

## Commands

Run all commands from the repo root.

**Run the full test suite** (Lua 5.1, no external dependencies):
```sh
lua5.1 tests/run_tests.lua
```
On Windows without `lua5.1` on PATH, use the installed interpreter directly, e.g. `& "C:\Program Files (x86)\Lua\5.1\lua.exe" tests/run_tests.lua`.

**Run a single spec file** — there's no built-in filter flag; either run it standalone with a one-line harness, or temporarily edit the `specs` list in `tests/run_tests.lua`. Every spec file is a self-contained script that `dofile("tests/wow_env.lua")`s the shim itself, so this works:
```sh
lua5.1 -e "_G.strmatch = string.match" -e "local t = dofile('tests/fj_database_spec.lua'); for n,f in pairs(t) do local ok,err = pcall(f); print(n, ok or err) end"
```

**Package a local zip** (no upload) — mirrors what CI's BigWigs packager step produces:
```powershell
tools/package.ps1
```

**Install the commit-msg hook** (once per clone) — enforces Conventional Commits, required by the changelog pipeline:
```sh
git config core.hooksPath .githooks
```

There is no separate lint/build step; the test suite is the correctness gate, and CI additionally dry-runs the BigWigs packager on every PR to catch packaging mistakes.

## Architecture

### Module loading and the shared namespace

WoW loads every file listed in `FieldJournal.toc`, in order, as a chunk called with `(addonName, addonTable)` as its vararg — `addonTable` is one shared table every module attaches to. `Core/Bootstrap.lua` initializes it (`local addonName, FieldJournal = ...`) and is the **first** Field Journal file loaded, after the vendored `Libs/`. The TOC load order is the dependency graph and must be respected when adding files:

```
Libs/ (LibStub, CallbackHandler-1.0, AceDB-3.0, AceSerializer-3.0, LibDeflate)
  → assets/QuestTextPack.lua
  → Core/Bootstrap.lua      (namespace init, character key, event registration/dispatch)
  → Core/Database.lua       (AceDB setup, schema version, defaults)
  → Core/Migrations.lua     (one-time legacy-data import)
  → Core/SlashCommands.lua  (/fj, /fieldjournal)
  → Core/DevTools.lua       (optional LibAT integration)
  → Data/QuestLog.lua, Bestiary.lua, Diary.lua, Crafting.lua
  → UI/Widgets.lua, NoteEditor.lua, Window.lua
```

`Core/Bootstrap.lua` owns the single `OnEvent` dispatcher for the whole addon — every WoW event the addon cares about is registered there and routed to a `Data/*` module function; other files never register their own event handlers.

### Persistence (AceDB-3.0)

`FieldJournal.db` is an AceDB-3.0 object (`Core/Database.lua`), opened against SavedVariable `FieldJournalDB` with `defaultProfile = true`. Two AceDB sections are used deliberately:
- `db.char` — one character's entire journal (entries, encounters, diaryEvents, craftEvents, bestiary, objectiveState, questBookmarks). This is *not* `db.profile`, because profiles are meant to be shared across characters and journal data never should be.
- `db.profile` — small UI prefs only (window position, last-open tab).

`Database.SCHEMA_VERSION` gates one-time migrations in `Core/Migrations.lua`. Both `schemaVersion` and `legacyMigrated` are deliberately given non-obvious defaults (0 and `false`, not the "current" values) because AceDB's `PLAYER_LOGOUT` handler deletes any stored value that equals its default — see the comment block at the top of `Core/Database.lua` before changing either default.

`Core/Bootstrap.lua`'s `initializeCharacter()` runs on `PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD`, points the namespace's flat fields (`FieldJournal.entries`, `.encounters`, `.bestiary`, etc.) at the logged-in character's `db.char` slot, and rebuilds the derived bestiary index from the persistent encounter log every load (existing higher totals/counts are never regressed).

Nothing in the persistence path throws on failure — `Database.initialize()` and friends catch errors, print a chat message, and let the addon continue running with recording disabled for that session rather than breaking the client.

### Vendored libraries are read-only, with one exception

Everything under `Libs/` is vendored and must never be hand-edited — with exactly one documented exception: `Libs/AceDB-3.0/AceDB-3.0.lua` has an inline patch (search for `FIELD JOURNAL PATCH`) fixing a load-time crash this client's `GetCurrentRegion()`/`UnitFactionGroup()`/`GetLocale()` answers trigger. If you need to change AceDB behavior again, patch that file directly (in place, clearly commented) rather than wrapping its globals from outside.

**Never temporarily reassign `GetCurrentRegion`, `GetRealmName`, `UnitName`, `UnitFactionGroup`, or `GetLocale`** anywhere in this codebase, even "restored afterwards." `tests/fj_no_global_reassignment_spec.lua` is a permanent regression guard for this: an earlier attempt to work around the AceDB load crash by wrapping these globals and restoring them permanently broke Blizzard's protected UI (unit-frame health bars) under the client's secret-value taint system, because restoring a wrapped global doesn't clear the taint mark. If a client incompatibility needs a workaround, patch the vendored file directly instead.

### Test strategy: real modules through a fake client, not mocks of the logic

`tests/wow_env.lua` is a minimal shim that stubs only the WoW globals touched at *load* time (`CreateFrame`, `SlashCmdList`, `time`, `date`, `tinsert`, `wipe`) and then `loadfile`s the **actual production `.lua` files** into a fresh namespace table, calling each chunk exactly as WoW would (`chunk("FieldJournal", ns)`). Spec files build on this to fake specific client quirks (e.g. `tests/fj_database_spec.lua`'s `hostileClient()` reproduces this beta client's exact hostile answers for `GetCurrentRegion`/`UnitFactionGroup`/`GetLocale`) and then exercise the real module code — there is no separate hand-maintained model of the business logic to keep in sync. `tests/run_tests.lua` is the aggregate runner; each spec file returns a `{ name = function() ... end }` table and a test passes if its function runs without raising.

### Release pipeline

Merging to `main` runs `tools/prepare_release.sh` (via `.github/workflows/prepare-release.yml`), which picks the next version, generates a changelog section with [git-cliff](https://git-cliff.org/) (`cliff.toml`, grouped by Conventional Commits type) via `tools/release_version.lua`, commits `chore: prepare release <version>` back to `main`, and opens a **draft** GitHub Release. That workflow authenticates as the `RELEASE_PAT` secret (not the default `GITHUB_TOKEN`) specifically so the push clears the `main` branch-protection ruleset and so the resulting release object isn't tied to `github-actions[bot]` (bot-created releases don't reliably fire `release: published` events for other workflows). Publishing the draft triggers `.github/workflows/publish-release.yml`, the only path that uploads the packaged zip to Wago.io. Full detail: [README.md § Continuous integration and Wago releases](README.md#continuous-integration-and-wago-releases).

Commit messages must follow Conventional Commits (`feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`, `chore`, `style`) — `cliff.toml`'s `commit_parsers` key the changelog grouping off these prefixes, and `chore: prepare release …` is specifically skipped so the automated commit doesn't show up in its own changelog.

### Optional external integration

`Core/DevTools.lua` is a soft, `pcall`-guarded integration with **Libs-AddonTools (LibAT)**, a separate standalone addon reached only via the global `_G.LibAT` when installed by the player — it is never vendored. Without it installed, `Core/DevTools.lua` is a complete no-op.
