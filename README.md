# Field Journal — WoW Forever beta

Open the journal with `/fj` or `/fieldjournal`. This version has four tabs:

- **Quests** keeps the quest log text, observed NPC dialogue, readable notes, kills and picked up quest items in chronological margins. It links speech from a recent quest giver when the speaker and location match one unambiguous quest. Previous quest stages and completed objectives are crossed out.
- **Daily diary** records newly learned spells, group joins, and merchant purchases and sales when the client exposes enough information.
- **Bestiary** counts creatures seen falling, their locations, and items actually looted from those creatures. Counts are personal observations, not drop rates.
- **Crafting & gathering** records loot from world objects, completed crafts reported by the client, and skill milestones at 20, 25, 35, 40, 50, 75, 100 and every 25 thereafter.

Records are saved per character in `FieldJournalDB` (managed by AceDB-3.0; existing pre-AceDB data migrates automatically the first time each character logs in). The addon never registers the protected combat log event. Kill detection uses party kill and observed unit death events; missing client events can leave gaps. Loot is attached to a creature or object only when the loot window supplies its source GUID and the item is actually taken. Merchant entries compare bags and money while a merchant is open; unrelated simultaneous changes can affect the account. Speech and note links can be changed manually from the quest tab.

## Install and update

Copy the `FieldJournal` folder into the beta client's `Interface/AddOns` folder. The existing addon can be updated while the game is running, then loaded with `/reload`. This build uses the existing TOC file list, so no relog is needed. SavedVariables should not be edited while the game is running.

**WoW Forever Beta SavedVariables bug:** this client has a known bug where addon SavedVariables are written to disk correctly but fail to load back in on `/reload` or a cold client start ([tracked upstream](https://github.com/ClassicWoWCommunity/forever-bugs/issues/34)). Left unaddressed, this can look like Field Journal losing your journal — in practice the data is silently going unread each session and then getting overwritten with whatever partial state the client actually loaded, which *does* destroy real data over repeated reloads. Install [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) to work around it (it loads the SavedVariables file through the addon's normal file loader, which still works, instead of the client's broken special-case loader). After installing or updating Field Journal, re-run ForeverSVFix's "Repair after addon updates" step, and if you edit `FieldJournal.toc` by hand, keep its injected `## X-ForeverSVFix:` header line and the two loader lines it adds at the top of the file list.

## Quick validation

1. `/reload`, open `/fj`, and confirm all four tabs open without an error.
2. Accept a quest from an NPC, listen to them speak, then inspect that quest's margins. Check that the observed words and speaker are right.
3. Defeat and loot a creature. Check the bestiary count and item. An unopened loot slot should not count.
4. Learn a spell at a trainer, gather from a world object, and craft an item. Check the diary and crafting tabs.
5. `/reload` again and confirm those entries remain.

## Earlier quest text

`QuestTextPack.lua` contains a small set of verified descriptions extracted from this beta client's quest cache. The completed quest API does not return the original conversations or completion time, so recovered entries are labeled as recovered descriptions. `tools/extract_quest_cache.py` can refresh that pack outside the game after the client has cached more quests. The pack is incomplete and beta specific.

## Later art

An illustrated map inside the journal can use the saved map coordinates to draw loose circles near recorded encounters and resources. This build records coordinates but does not draw the map yet.

## Local saves and recovery

WoW writes `FieldJournalDB` to the account's `WTF/Account/<account>/SavedVariables/FieldJournal.lua` on `/reload` and logout. Version 0.7.1 initializes the saved character record at login, world entry, and when the journal opens. It also reconciles the bestiary from the saved encounter list without erasing recorded loot. `/fj status` prints the current character key, saved encounter count, and bestiary species count. If the bestiary list appears empty, use `/fj repair` to rebuild its index from the encounter history, then inspect the Bestiary tab. A separate backup of Rimurai's current SavedVariables was made before this update. Do not replace the live SavedVariables file while the game is running.

## 0.7.2 persistence repair

This build adds `FieldJournalCharacterDB` as a character-scoped SavedVariables backup alongside the account-level `FieldJournalDB`. At startup it merges available saved entries, encounters, loot and crafting records by stable keys, so repeated reloads do not create duplicates. The installed `QuestTextPack.lua` on Rimurai's computer also includes a one-time local recovery snapshot from the richer account save observed at 12:19 on 19 September 2026. The downloadable generic addon package does not contain this personal snapshot. The recovery overlay is available separately and should be kept private. `/fj status` now reports encounter, bestiary and crafting counts plus whether that recovery overlay loaded.

Two beta game processes were running during investigation. If both play sessions remain active, a stale process can overwrite the account SavedVariables file on reload or exit. The character-scoped backup protects this addon from an older process that does not know about the new backup, but simultaneous writes from two updated clients can still conflict. Close the unused client when convenient, after ensuring the active character is safely logged out.

## 0.7.3 recovery update

A second, different live client snapshot contained another mining node and crafted items. The local recovery overlay now includes both snapshots. Startup merges encounter records by creature GUID and activity records by their event identity. The two snapshots contain 14 distinct encounter GUIDs. The generic zip remains free of Rimurai's personal records; the installed overlay is local to this computer.

## 0.7.4 recovery update

The earliest saved backup adds five more unique encounters. The installed local overlay now merges three snapshots with 19 distinct creature GUIDs in total. The generic package remains free of those personal snapshots.

## 0.8.0 daily pages

The left page selects dates with recorded activity. The right page groups that day's raw records into sections. Repeated loot from the same world object appears as one gathering activity with item totals; crafts at the same place within a short session appear as one batch; and consecutive sales or purchases with the same vendor appear as one visit with combined item and money totals. Underlying saved events remain separate so detail is not discarded. The Bestiary list now shows each encounter count once. Vendor names are captured from bag item links when available, which improves future diary entries; older unknown items may still appear by item ID. This build also includes all three local recovery snapshots for Rimurai's installation.
