-- Field Journal: AceDB-3.0 setup, schema version and per-character defaults.
--
-- Loads early in the Core/ block, after the Libs/ block and after Bootstrap's
-- frame/event setup, before any Data/ or UI/ file. AceDB-3.0's own file-load-time
-- crash on this client (see the patch comment in Libs/AceDB-3.0/AceDB-3.0.lua) is
-- fixed directly in that vendored file, so this file has no global-restoration
-- timing to coordinate.

local FieldJournal = select(2, ...)

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
--
-- profile holds the opposite of char: preferences a player would want shared
-- across their own characters (window position, last-open tab), never
-- journal data. AceDB is opened with defaultProfile = true below, so each
-- character auto-selects its own profile by default -- nothing here is
-- actually shared until a player deliberately points two characters at the
-- same profile (Libs-AddonTools' Profile Manager, if installed, or
-- db:SetProfile()).
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
    profile = {
        windowPoint = nil,
        lastTab = "quests",
    },
}

-- Deep-copy helper for plain data tables (no metatables, functions, or cycles).
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = deepCopy(v)
    end
    return dst
end

-- Grab references to every pre-AceDB global before AceDB:New touches the
-- SavedVariables table. AceDB reuses the same table object and its logout
-- handler only prunes the sections it knows about, so deep-copy here to ensure
-- the migration reads from a snapshot that cannot be affected by anything AceDB
-- does afterwards.
local function captureLegacy()
    local legacy = {recovery = {}}
    if type(FieldJournalDB) == "table" then legacy.account = deepCopy(FieldJournalDB) end
    if type(FieldJournalCharacterDB) == "table" then legacy.character = deepCopy(FieldJournalCharacterDB) end
    for _, name in ipairs({"FieldJournalRecoveryDB", "FieldJournalRecoveryDB2", "FieldJournalRecoveryDB3"}) do
        local snapshot = _G[name]
        if type(snapshot) == "table" then
            legacy.recovery[#legacy.recovery + 1] = {name = name, data = deepCopy(snapshot)}
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
        if FieldJournal.logError then FieldJournal.logError(FieldJournal.databaseError) end
        return nil
    end

    local ok, result = pcall(lib.New, lib, "FieldJournalDB", Database.defaults, true)
    if not ok or type(result) ~= "table" then
        FieldJournal.databaseError = tostring(result)
        print("Field Journal: could not open the database (" .. tostring(result)
            .. "); the journal cannot record this session.")
        if FieldJournal.logError then FieldJournal.logError(FieldJournal.databaseError) end
        return nil
    end

    FieldJournal.db = result

    if FieldJournal.Migrations and FieldJournal.Migrations.run then
        local mOk, mErr = pcall(FieldJournal.Migrations.run, result.char, legacy)
        if not mOk then
            FieldJournal.migrationError = tostring(mErr)
            print("Field Journal: the legacy migration failed unexpectedly (" .. tostring(mErr) .. ").")
            if FieldJournal.logError then FieldJournal.logError(FieldJournal.migrationError) end
        end
    end

    return result
end
