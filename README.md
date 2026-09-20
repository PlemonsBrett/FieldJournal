# Field Journal — WoW Forever beta

> 🎨 **Artists wanted!** The journal already records map coordinates, creature IDs and item IDs for everything it sees — it just doesn't draw any of it yet. If you can make icons, portraits, or a journal-style map, see [issue #6](https://github.com/PlemonsBrett/FieldJournal/issues/6). No Lua required to contribute a mockup or asset set.

Open the journal with `/fj` or `/fieldjournal`. This version has four tabs:

- **Quests** keeps the quest log text, observed NPC dialogue, readable notes, kills and picked up quest items in chronological margins. It links speech from a recent quest giver when the speaker and location match one unambiguous quest. Previous quest stages and completed objectives are crossed out.
- **Daily diary** records newly learned spells, group joins, and merchant purchases and sales when the client exposes enough information.
- **Bestiary** counts creatures seen falling, their locations, and items actually looted from those creatures. Counts are personal observations, not drop rates.
- **Crafting & gathering** records loot from world objects, completed crafts reported by the client, and skill milestones at 20, 25, 35, 40, 50, 75, 100 and every 25 thereafter.

The addon never registers the protected combat log event. Kill detection uses party kill and observed unit death events; missing client events can leave gaps. Loot is attached to a creature or object only when the loot window supplies its source GUID and the item is actually taken. Merchant entries compare bags and money while a merchant is open; unrelated simultaneous changes can affect the account. Speech and note links can be changed manually from the quest tab.

See [CHANGELOG.md](CHANGELOG.md) for the version history.

## Current status

This is beta software, developed and tested against one live account. The codebase is split into a namespaced module layout (`Core/`, `Data/`, `UI/`) with a hand-rolled Lua test suite (`tests/run_tests.lua`).

Journal data is stored per character via AceDB-3.0 (`FieldJournalDB.char`). Existing data from before this migration is imported automatically, once, the first time each character logs in — see [CHANGELOG.md](CHANGELOG.md) for details. The old data is never deleted, only read, so it remains a fallback if anything about the migration ever needs to be redone.

Each character also keeps a rotating ring of five automatic backup snapshots, taken at login, plus a second complete copy in its own per-character saved-variables file. `/fj repair` restores from those snapshots. There is still no manual export/import, and no guarantee that a manual edit to an entry survives auto-regeneration or a future merge — see Roadmap below.

## Roadmap

This follows a phased resilience plan (`docs/superpowers/specs/2026-09-19-phase1-resilience-design.md` in this repo's history, not distributed with the addon). See the [milestones](https://github.com/PlemonsBrett/FieldJournal/milestones) and [open issues](https://github.com/PlemonsBrett/FieldJournal/issues) for what's up for grabs — issues labeled [`good first issue`](https://github.com/PlemonsBrett/FieldJournal/labels/good%20first%20issue) are small, self-contained, and don't need deep addon-development experience.

- **Export / Import** — a manual `/fj export` / `/fj import` safety valve so players can back up or transfer their own data without touching SavedVariables files directly.
- **Edit-safety guarantees** — a per-record `edited` flag so a manual correction (via the note editor) is never silently overwritten by auto-regeneration, a merge, or a backup restore.
- **Repository polish** — a CLAUDE.md for future coding-agent sessions, once the data layer above has proven stable. (Contribution guidelines now live in [CONTRIBUTING.md](CONTRIBUTING.md).)
- **Phase 2 (UI/UX) and Phase 3 (visual polish, art)** — exploratory, no design work started; see the open issues.

None of this is scheduled; it lands as time allows.

## Install and update

Copy the `FieldJournal` folder into the beta client's `Interface/AddOns` folder. The existing addon can be updated while the game is running, then loaded with `/reload`. This build uses the existing TOC file list, so no relog is needed. SavedVariables should not be edited while the game is running.

**WoW Forever Beta SavedVariables bug:** this client has a known bug where addon SavedVariables are written to disk correctly but fail to load back in on `/reload` or a cold client start ([tracked upstream](https://github.com/ClassicWoWCommunity/forever-bugs/issues/34)). Left unaddressed, this can look like Field Journal losing your journal — in practice the data is silently going unread each session and then getting overwritten with whatever partial state the client actually loaded, which *does* destroy real data over repeated reloads. Install [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) to work around it (it loads the SavedVariables file through the addon's normal file loader, which still works, instead of the client's broken special-case loader). After installing or updating Field Journal, re-run ForeverSVFix's "Repair after addon updates" step, and if you edit `FieldJournal.toc` by hand, keep its injected `## X-ForeverSVFix:` header line and the two loader lines it adds at the top of the file list.

## Continuous integration and Wago releases

GitHub Actions runs the Lua 5.1 suite (`tests/run_tests.lua`) on every pull request and push to `main`, and dry-runs the [BigWigs packager](https://github.com/BigWigsMods/packager) so a bad zip fails before anyone publishes it.

Merging to `main` prepares a **draft** GitHub Release. It does not upload to Wago.io yet:

1. Tests must pass.
2. The pipeline chooses the next version (keeps `FieldJournal.toc` on the first release; uses a TOC bump if you already changed it; otherwise increments the patch and keeps any `-beta` / `-alpha` suffix).
3. It prepends that version to `CHANGELOG.md` using [git-cliff](https://git-cliff.org/) (`cliff.toml`) to group the Conventional Commits since the last `v*` tag, commits `chore: prepare release <version>` to `main`, and opens a draft release with the packaged zip attached.

Publishing that draft (GitHub → Releases → Edit draft → Publish) is what uploads the Forever zip (`Interface: 16001` → Wago patch `1.60.1`) to Wago project `bGoyor60`. The publish job fails if repository secret `WAGO_API_KEY` is missing. Local zips can still be built with `tools/package.ps1`.

## Quick validation

1. `/reload`, open `/fj`, and confirm all four tabs open without an error.
2. Accept a quest from an NPC, listen to them speak, then inspect that quest's margins. Check that the observed words and speaker are right.
3. Defeat and loot a creature. Check the bestiary count and item. An unopened loot slot should not count.
4. Learn a spell at a trainer, gather from a world object, and craft an item. Check the diary and crafting tabs.
5. `/reload` again and confirm those entries remain.

## Saved data

WoW writes `FieldJournalDB` to the account's `WTF/Account/<account>/SavedVariables/FieldJournal.lua` on `/reload` and logout, and a complete per-character second copy to `WTF/Account/<account>/<realm>/<character>/SavedVariables/FieldJournal.lua`. `/fj status` prints the current character key, schema version, migration state, saved encounter/bestiary/crafting counts, and how full the backup ring is. `/fj backup` lists the five rotating snapshots; `/fj backup now` takes one on the spot. If data looks missing, or the bestiary list appears empty, use `/fj repair`: it merges anything the backup ring still has back in, then rebuilds the bestiary index from the encounter history. Repairing is safe to run more than once — it never overwrites or duplicates what is already there. Do not replace the live SavedVariables file while the game is running.

## Earlier quest text

`QuestTextPack.lua` contains a small set of verified descriptions extracted from this beta client's quest cache. The completed quest API does not return the original conversations or completion time, so recovered entries are labeled as recovered descriptions. `tools/extract_quest_cache.py` can refresh that pack outside the game after the client has cached more quests. The pack is incomplete and beta specific.

## Later art

An illustrated map inside the journal can use the saved map coordinates to draw loose circles near recorded encounters and resources. This build records coordinates but does not draw the map yet.
