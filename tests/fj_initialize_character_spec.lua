local env = dofile("tests/wow_env.lua")

-- initializeCharacter() is the riskiest rewrite in Task 4: it is the first
-- function to read FieldJournal.db.char instead of the old raw FieldJournalDB
-- shape, and it decides whether the FieldJournalCharacterDB backup mirror gets
-- overwritten this session. These tests drive it directly against a plain
-- Lua table shaped like an AceDB object -- there is no need to load the real
-- vendored AceDB-3.0.lua, since initializeCharacter only ever reads
-- FieldJournal.db and FieldJournal.db.char.

-- Loads only Core/Bootstrap.lua into a fresh namespace. initializeCharacter's
-- tail calls into Data/ and UI/ modules this spec does not load, but a fresh
-- or freshly-migrated character always starts every collection empty, so the
-- reconciliation loops above those calls never iterate -- the four calls
-- below are the only ones actually reached, and are stubbed accordingly.
local function load()
    env.install()
    _G.GetRealmName = function() return "Ashenvale" end
    _G.UnitName = function() return "Wren" end
    _G.FieldJournalCharacterDB = nil
    local ns = {}
    local chunk, err = loadfile("Core/Bootstrap.lua")
    assert(chunk, "could not load Core/Bootstrap.lua: " .. tostring(err))
    chunk("FieldJournal", ns)
    ns.Diary.resetGroupSnapshot = function() end
    ns.QuestLog.syncActiveQuestLog = function() end
    ns.Bestiary.observeUnit = function() end
    ns.UI.createWindow = function() ns.UI.window = true end
    return ns
end

local function freshCharData(overrides)
    local charData = {
        legacyMigrated = false,
        nextOrder = 0,
        entries = {},
        encounters = {},
        diaryEvents = {},
        craftEvents = {},
        bestiary = {},
        objectiveState = {},
        questBookmarks = {},
    }
    for key, value in pairs(overrides or {}) do charData[key] = value end
    return charData
end

local NAMESPACE_FIELDS = {"entries", "encounters", "diaryEvents", "craftEvents",
    "bestiary", "objectiveState", "questBookmarks"}

local function test_fresh_character_populates_all_namespace_fields_from_db_char()
    local fj = load()
    local charData = freshCharData({legacyMigrated = true})
    fj.db = {char = charData}
    fj.initializeCharacter()
    assert(fj.charData == charData, "FieldJournal.charData must point at db.char")
    for _, field in ipairs(NAMESPACE_FIELDS) do
        assert(type(fj[field]) == "table", "FieldJournal." .. field .. " was not populated")
        assert(fj[field] == charData[field],
            "FieldJournal." .. field .. " must be the same table as db.char." .. field)
    end
    assert(type(_G.FieldJournalCharacterDB) == "table",
        "the mirror must be written once a character's migration has completed")
    assert(_G.FieldJournalCharacterDB.entries == fj.entries,
        "the mirror's entries must be the same table FieldJournal uses")
end

local function test_degraded_database_leaves_namespace_fields_nil()
    local fj = load()
    fj.db = nil
    fj.initializeCharacter()
    assert(fj.charData == nil, "FieldJournal.charData must stay nil when FieldJournal.db is nil")
    for _, field in ipairs(NAMESPACE_FIELDS) do
        assert(fj[field] == nil, "FieldJournal." .. field .. " must stay nil when FieldJournal.db is nil")
    end
    assert(_G.FieldJournalCharacterDB == nil, "the mirror must not be touched when there is no database")
end

-- Direct regression test for the reviewer's Critical finding: when the
-- one-time migration throws, Core/Migrations.lua deliberately leaves
-- charData.legacyMigrated false so the next session retries it. If
-- initializeCharacter rewrote the FieldJournalCharacterDB mirror anyway, that
-- retry would have nothing left to recover from -- the mirror must be left
-- exactly as it was.
local function test_failed_migration_does_not_clobber_the_existing_mirror()
    local fj = load()
    _G.FieldJournalCharacterDB = {key = "old key", entries = {sentinel = true}, encounters = {"kept"},
        diaryEvents = {}, craftEvents = {}, bestiary = {}}
    local charData = freshCharData({legacyMigrated = false})
    fj.db = {char = charData}
    fj.initializeCharacter()
    assert(_G.FieldJournalCharacterDB.key == "old key",
        "a pending-retry migration must not overwrite the existing mirror's key")
    assert(_G.FieldJournalCharacterDB.entries.sentinel == true,
        "a pending-retry migration must not overwrite the existing mirror's real backup data")
    assert(_G.FieldJournalCharacterDB.encounters[1] == "kept",
        "a pending-retry migration must not overwrite the existing mirror's real backup data")
end

local function test_completed_migration_rewrites_the_mirror()
    local fj = load()
    _G.FieldJournalCharacterDB = {key = "old key", entries = {sentinel = true}, encounters = {"stale"},
        diaryEvents = {}, craftEvents = {}, bestiary = {}}
    local charData = freshCharData({legacyMigrated = true})
    fj.db = {char = charData}
    fj.initializeCharacter()
    assert(_G.FieldJournalCharacterDB.key == fj.characterKey(),
        "a completed migration must rewrite the mirror under the current character key")
    assert(_G.FieldJournalCharacterDB.entries == fj.entries,
        "a completed migration must rewrite the mirror's entries to point at the live data")
    assert(_G.FieldJournalCharacterDB.entries.sentinel == nil,
        "a completed migration must replace the stale mirror content, not merge into it")
end

return {
    test_fresh_character_populates_all_namespace_fields_from_db_char =
        test_fresh_character_populates_all_namespace_fields_from_db_char,
    test_degraded_database_leaves_namespace_fields_nil = test_degraded_database_leaves_namespace_fields_nil,
    test_failed_migration_does_not_clobber_the_existing_mirror =
        test_failed_migration_does_not_clobber_the_existing_mirror,
    test_completed_migration_rewrites_the_mirror = test_completed_migration_rewrites_the_mirror,
}
