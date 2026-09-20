-- Field Journal: AceDB-3.0 setup, schema version and per-character defaults.
--
-- This is the first file that loads after the Libs/ block, so it is the first
-- place that can undo Core/ClientCompat.lua's temporary global wrappers.
-- Do that before anything else: AceDB-3.0 captured everything it needed while
-- its own file was loading, so nothing below depends on the wrappers staying.

local FieldJournal = select(2, ...)

if FieldJournal.ClientCompat then FieldJournal.ClientCompat.restore() end

local Database = {}
FieldJournal.Database = Database

-- Bump only when defaults.char's shape changes in a way that needs a migration
-- step. Version 1 was the pre-AceDB account-wide shape; 2 is this one.
Database.SCHEMA_VERSION = 2

-- defaults.char is one character's entire journal, flat. Everything the old
-- account-wide FieldJournalDB kept under a "<realm>:<char>" key lives here.
-- We deliberately do not use db.profile (profiles are meant to be shared
-- between characters, which is never right for a personal activity log) and
-- we keep db.global empty (no genuinely account-wide data has been identified).
--
-- Two default values are chosen against the obvious reading, both because of
-- AceDB's removeDefaults pass at PLAYER_LOGOUT, which deletes any stored value
-- that equals its default and lets copyDefaults put it back at the next load:
--
--   schemaVersion defaults to 0, NOT to SCHEMA_VERSION. If it defaulted to 2,
--   a character genuinely stored at 2 would be stripped to nil on logout and
--   be indistinguishable from a brand new character. A future SCHEMA_VERSION 3
--   could then never tell "already at 2" from "fresh", and would skip or
--   re-run its migration. Defaulting to 0 and writing the real version
--   explicitly after migrations keeps the stored number meaningful.
--
--   legacyMigrated defaults to false, NOT nil. `true` never equals `false`, so
--   once the one-time migration sets it, it always survives logout.
--
-- nextOrder is new here and is not in the design spec's sketch: it used to be
-- a single account-wide counter on FieldJournalDB, shared by entry ordering
-- and bestiary/encounter ordering. AceDB exposes no account-wide slot we want
-- to use, and the counter is only ever compared within one character's own
-- collections, so it becomes per-character. Core/Migrations.lua seeds it high
-- enough that no new record can collide with a migrated one.
--
-- backups is reserved for Core/Backup.lua (Plan 3b) and is never read here.
-- It is declared now so Plan 3b needs no migration step of its own.
Database.defaults = {
    char = {
        schemaVersion = 0,
        legacyMigrated = false,
        nextOrder = 0,
        entries = {},
        encounters = {},
        diaryEvents = {},
        craftEvents = {},
        bestiary = {},
        objectiveState = {},
        questBookmarks = {},
        backups = {},
    },
}

-- Grab references to every pre-AceDB global before AceDB:New touches the
-- SavedVariables table. AceDB only ever adds keys to that table -- it reuses
-- the same table object and its logout handler only prunes the sections it
-- knows about -- so the legacy keys would survive anyway. Capturing first is
-- belt and braces: the migration reads from these references, never from the
-- global, so it cannot be affected by anything AceDB does afterwards.
local function captureLegacy()
    local legacy = {recovery = {}}
    if type(FieldJournalDB) == "table" then legacy.account = FieldJournalDB end
    if type(FieldJournalCharacterDB) == "table" then legacy.character = FieldJournalCharacterDB end
    for _, name in ipairs({"FieldJournalRecoveryDB", "FieldJournalRecoveryDB2", "FieldJournalRecoveryDB3"}) do
        local snapshot = _G[name]
        if type(snapshot) == "table" then
            legacy.recovery[#legacy.recovery + 1] = {name = name, data = snapshot}
        end
    end
    return legacy
end

--- Creates the AceDB object, runs any pending migration, publishes
--  FieldJournal.db, and returns it. Called once, from Core/Bootstrap.lua's
--  ADDON_LOADED handler. Idempotent.
--
--  Never throws. If the database cannot be opened the addon loads with
--  FieldJournal.db nil, which every capture path already treats as "do
--  nothing" -- the journal stops recording for the session but the client
--  stays up and nothing on disk is modified.
function Database.initialize()
    if FieldJournal.db then return FieldJournal.db end

    local legacy = captureLegacy()

    local lib = LibStub and LibStub("AceDB-3.0", true)
    if not lib then
        FieldJournal.databaseError = "AceDB-3.0 is not loaded"
        print("Field Journal: AceDB-3.0 did not load; the journal cannot record this session.")
        return nil
    end

    local ok, result = pcall(lib.New, lib, "FieldJournalDB", Database.defaults, true)
    if not ok or type(result) ~= "table" then
        FieldJournal.databaseError = tostring(result)
        print("Field Journal: could not open the database (" .. tostring(result)
            .. "); the journal cannot record this session.")
        return nil
    end

    FieldJournal.db = result

    if FieldJournal.Migrations and FieldJournal.Migrations.run then
        FieldJournal.Migrations.run(result.char, legacy)
    end

    return result
end
