# Field Journal — WoW Forever beta

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

There is currently no rotating backup, no manual export/import, and no guarantee that a manual edit to an entry survives auto-regeneration or a future merge — see Roadmap below.

## Roadmap

This follows a phased resilience plan (`docs/superpowers/specs/2026-09-19-phase1-resilience-design.md` in this repo's history, not distributed with the addon). Remaining work:

- **Rotating self-heal backups** — an automatic snapshot of each character's data taken at login, capped and pruned, with a redesigned `/fj repair` that can restore from it. Replaces the old hand-maintained `FieldJournalRecoveryDB` snapshot pattern entirely.
- **Export / Import** — a manual `/fj export` / `/fj import` safety valve so players can back up or transfer their own data without touching SavedVariables files directly.
- **Edit-safety guarantees** — a per-record `edited` flag so a manual correction (via the note editor) is never silently overwritten by auto-regeneration, a merge, or a backup restore.
- **Repository polish** — CONTRIBUTING notes and a CLAUDE.md for future coding-agent sessions, once the data layer above has proven stable.

None of this is scheduled; it lands as time allows.

## Install and update

Copy the `FieldJournal` folder into the beta client's `Interface/AddOns` folder. The existing addon can be updated while the game is running, then loaded with `/reload`. This build uses the existing TOC file list, so no relog is needed. SavedVariables should not be edited while the game is running.

**WoW Forever Beta SavedVariables bug:** this client has a known bug where addon SavedVariables are written to disk correctly but fail to load back in on `/reload` or a cold client start ([tracked upstream](https://github.com/ClassicWoWCommunity/forever-bugs/issues/34)). Left unaddressed, this can look like Field Journal losing your journal — in practice the data is silently going unread each session and then getting overwritten with whatever partial state the client actually loaded, which *does* destroy real data over repeated reloads. Install [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) to work around it (it loads the SavedVariables file through the addon's normal file loader, which still works, instead of the client's broken special-case loader). After installing or updating Field Journal, re-run ForeverSVFix's "Repair after addon updates" step, and if you edit `FieldJournal.toc` by hand, keep its injected `## X-ForeverSVFix:` header line and the two loader lines it adds at the top of the file list.

## Quick validation

1. `/reload`, open `/fj`, and confirm all four tabs open without an error.
2. Accept a quest from an NPC, listen to them speak, then inspect that quest's margins. Check that the observed words and speaker are right.
3. Defeat and loot a creature. Check the bestiary count and item. An unopened loot slot should not count.
4. Learn a spell at a trainer, gather from a world object, and craft an item. Check the diary and crafting tabs.
5. `/reload` again and confirm those entries remain.

## Saved data

WoW writes `FieldJournalDB` to the account's `WTF/Account/<account>/SavedVariables/FieldJournal.lua` on `/reload` and logout. `/fj status` prints the current character key, schema version, migration state, and saved encounter/bestiary/crafting counts. If the bestiary list appears empty, use `/fj repair` to rebuild its index from the encounter history, then inspect the Bestiary tab. Do not replace the live SavedVariables file while the game is running.

## Earlier quest text

`QuestTextPack.lua` contains a small set of verified descriptions extracted from this beta client's quest cache. The completed quest API does not return the original conversations or completion time, so recovered entries are labeled as recovered descriptions. `tools/extract_quest_cache.py` can refresh that pack outside the game after the client has cached more quests. The pack is incomplete and beta specific.

## Later art

An illustrated map inside the journal can use the saved map coordinates to draw loose circles near recorded encounters and resources. This build records coordinates but does not draw the map yet.
