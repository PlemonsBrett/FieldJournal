# Changelog

## 0.8.3-beta

### Fixed

- Name legacy fields in migration warnings

## 0.8.2-beta

### Added

- Add the rotating five-slot backup ring with a data-loss guard
- Restore a lost journal from the backup ring without aliasing or resurrecting placeholders
- Take one backup snapshot at login, never on a zone change
- Restore from the backup ring in /fj repair and add /fj backup


### Changed

- Publish deepCopy, highestOrder and countText for the backup module


### Documentation

- Document the rotating backup ring, /fj backup and the redesigned /fj repair
- Refresh stale Backup.lua comments left by the Task 2 and 3 fix rounds


### Fixed

- Close the entries-wipe gap and guard the ring against throws
- Stop /fj repair from reporting a false restore when a merge only reintroduces then re-drops a placeholder
- Keep the per-character mirror and make it a complete second copy

## 0.8.1-beta

### Added

- Add commit-msg hook to enforce Conventional Commits and improve release process

## 0.8.0-beta

## What's Changed
* feat: draft releases on merge and publish to Wago when accepted by @PlemonsBrett in https://github.com/PlemonsBrett/FieldJournal/pull/13

## New Contributors
* @PlemonsBrett made their first contribution in https://github.com/PlemonsBrett/FieldJournal/pull/13

**Full Changelog**: https://github.com/PlemonsBrett/FieldJournal/commits/v0.8.0-beta

## Settings panel and tab visibility

The journal's header now carries a small button beside the close button. It opens a settings panel holding Export, Import, Backup now and Repair — the same four actions as the slash commands, running the same code, so none of them has to be typed any more.

The panel also holds three per-character checkboxes for the Daily diary, Bestiary and Crafting & gathering tabs. Unchecking one removes that tab from the tab row straight away, with no gap left behind, and returns you to Quests if you were reading the tab you just hid. The Quests tab is never hideable.

**Hiding a tab never stops recording.** Everything the addon watched before it is still recorded and stored in the background; the setting changes only what the tab row displays. Re-check the box later and the tab comes back carrying everything that happened while it was hidden. The choices are stored per character alongside the window position, so they survive a logout.

## Export and import

`/fj export` turns the current character's journal into a single printable string and shows it in a small window with the whole string already selected — press Ctrl-C and paste it into a text file, a chat message, or another machine. The string is your journal compressed and encoded, so it uses only letters, digits and parentheses and survives being copied through anything. The rotating backup ring is deliberately **not** included: the receiving character builds its own, and carrying five extra copies would multiply the string's size for no benefit.

`/fj import` opens a box to paste a string into (WoW's chat line is capped at 255 characters, far shorter than any real export, so pasting into the box is the normal path; `/fj import <string>` still works for short strings and macros). Nothing is merged until the string has been decoded, decompressed, read, and confirmed to be a Field Journal export of a journal schema this version understands. Anything else — another addon's export string, a half-copied one, one from a future version — is refused with a message saying which check failed, and your journal is left exactly as it was.

An import merges rather than replaces, with the same identity-based, never-overwrite, keep-the-higher-count rules the addon uses everywhere else: your own records always win, nothing is duplicated, and importing the same string twice reports that there was nothing to add. It works on a copy of the decoded data, so an imported record is never the same table as the string you pasted; it re-applies the rule that removes an earlier-quest placeholder once you have captured that quest's real text, so importing cannot make a quest appear twice; and it lifts the record counter above everything it just added so new records cannot collide with imported ones. After a successful import the bestiary index is rebuilt from the encounter log, exactly as `/fj repair` does, so creatures restored from the string are counted in the same command.

This also makes `/fj export` a cross-character and cross-machine transfer: export on one character, import on another.

## Rotating self-heal backups

Field Journal now keeps its own backups. At each login it takes a snapshot of the current character's journal and stores it in a five-slot rotating ring inside that character's saved data. A snapshot is skipped when nothing has changed since the last one, and — importantly — it is also skipped, with a warning, when the character has *fewer* records than its most recent snapshot. That second rule exists so a session that loads damaged or empty data can never quietly rotate five good snapshots out of the ring one login at a time.

`/fj repair` now does two things. First it merges every snapshot in the ring back into the live journal, using the same identity-based, never-overwrite, keep-the-higher-count rules the addon has always used for merges, and reports exactly what that recovered (or "no repair needed"). Then it rebuilds the bestiary index from the encounter log as it always did — so an encounter recovered from a backup is counted in the same command. The restore always works on a copy of the snapshot, so a restored record is never the same table as the backup's own record, and it re-applies the rule that deletes an earlier-quest placeholder once you have captured that quest's real text, so a restore cannot resurrect quests you have already replaced.

New command: `/fj backup` lists the ring with each snapshot's timestamp and record counts, and `/fj backup now` takes one immediately (honouring the same skip rules). `/fj status` now reports how full the ring is and when the newest snapshot was taken.

This replaces the `FieldJournalRecoveryDB` / `DB2` / `DB3` pattern permanently: those hand-added globals existed only because data was lost and spliced back in by hand, and no future incident needs a new one. They are still never written to, and their contents were already absorbed by the AceDB migration below.

The per-character `FieldJournalCharacterDB` mirror is deliberately **kept**, not retired. It is the only copy of a character's journal that lives in a different saved-variables file from the account-wide `FieldJournalDB` — and losing that account file whole is exactly the 0.7.x failure an in-file backup ring cannot defend against. It now also carries quest bookmarks and in-flight objective progress, making it a complete second copy.

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
