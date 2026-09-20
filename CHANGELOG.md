# Changelog

## 0.8.1-beta

### Added

- Add commit-msg hook to enforce Conventional Commits and improve release process

## 0.8.0-beta

## What's Changed
* feat: draft releases on merge and publish to Wago when accepted by @PlemonsBrett in https://github.com/PlemonsBrett/FieldJournal/pull/13

## New Contributors
* @PlemonsBrett made their first contribution in https://github.com/PlemonsBrett/FieldJournal/pull/13

**Full Changelog**: https://github.com/PlemonsBrett/FieldJournal/commits/v0.8.0-beta

## AceDB-3.0 persistence migration

Journal data now lives in an AceDB-3.0-managed per-character store (`FieldJournalDB.char`) instead of the raw account-wide table indexed by hand-built character keys. A one-time migration runs automatically the first time each character logs in: it reads the old `characters`/`encounters`/`diaryEvents`/`craftEvents`/`bestiary`/`objectiveStates`/`questBookmarks` tables (plus the per-character `FieldJournalCharacterDB` mirror and any `FieldJournalRecoveryDB`/`DB2`/`DB3` snapshots), merges them with the same identity-based, never-overwrite rules the addon has always used, and marks itself done so it never re-runs. The old data is left untouched on disk as a fallback. `/fj status` now reports the schema version and whether the legacy migration has completed.

This also fixes the long-standing crash on this beta client where the vendored AceDB-3.0 library could fail to load at all (`AceDB-3.0.lua:268: attempt to concatenate local 'regionKey' (a nil value)`), via a small, clearly-commented patch to that vendored file's load-time key computation — the one deliberate exception to this project's rule that vendored libraries are never hand-edited.

Also discovered during this work: the WoW Forever Beta client has its own bug where SavedVariables are written to disk correctly but fail to load back in on `/reload` or a cold start. See the README's Install section for the [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) workaround — this is a client bug, not a Field Journal bug, but it can look like Field Journal losing data if left unaddressed.

## 0.8.0 daily pages

The left page selects dates with recorded activity. The right page groups that day's raw records into sections. Repeated loot from the same world object appears as one gathering activity with item totals; crafts at the same place within a short session appear as one batch; and consecutive sales or purchases with the same vendor appear as one visit with combined item and money totals. Underlying saved events remain separate so detail is not discarded. The Bestiary list now shows each encounter count once. Vendor names are captured from bag item links when available, which improves future diary entries; older unknown items may still appear by item ID. This build also includes all three local recovery snapshots for Rimurai's installation.

## 0.7.4 recovery update

The earliest saved backup adds five more unique encounters. The installed local overlay now merges three snapshots with 19 distinct creature GUIDs in total. The generic package remains free of those personal snapshots.

## 0.7.3 recovery update

A second, different live client snapshot contained another mining node and crafted items. The local recovery overlay now includes both snapshots. Startup merges encounter records by creature GUID and activity records by their event identity. The two snapshots contain 14 distinct encounter GUIDs. The generic zip remains free of Rimurai's personal records; the installed overlay is local to this computer.

## 0.7.2 persistence repair

This build adds `FieldJournalCharacterDB` as a character-scoped SavedVariables backup alongside the account-level `FieldJournalDB`. At startup it merges available saved entries, encounters, loot and crafting records by stable keys, so repeated reloads do not create duplicates. The installed `QuestTextPack.lua` on Rimurai's computer also includes a one-time local recovery snapshot from the richer account save observed at 12:19 on 19 September 2026. The downloadable generic addon package does not contain this personal snapshot. The recovery overlay is available separately and should be kept private. `/fj status` now reports encounter, bestiary and crafting counts plus whether that recovery overlay loaded.

Two beta game processes were running during investigation. If both play sessions remain active, a stale process can overwrite the account SavedVariables file on reload or exit. The character-scoped backup protects this addon from an older process that does not know about the new backup, but simultaneous writes from two updated clients can still conflict. Close the unused client when convenient, after ensuring the active character is safely logged out.

## 0.7.1 saved character record

Initializes the saved character record at login, world entry, and when the journal opens. Reconciles the bestiary from the saved encounter list without erasing recorded loot. `/fj status` prints the current character key, saved encounter count, and bestiary species count. If the bestiary list appears empty, use `/fj repair` to rebuild its index from the encounter history, then inspect the Bestiary tab. A separate backup of Rimurai's current SavedVariables was made before this update.
