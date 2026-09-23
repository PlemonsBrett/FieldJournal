local env = dofile("tests/wow_env.lua")

-- Reproduces this addon's actual client as closely as plain Lua allows:
-- GetCurrentRegion() answers outside AceDB's {US,KR,EU,TW,CN} table,
-- UnitFactionGroup() answers nil, and GetLocale() does not exist at all.
-- These are exactly the hostile values the AceDB-3.0.lua patch (see
-- Libs/AceDB-3.0/AceDB-3.0.lua) must survive.
local function hostileClient()
    env.install()
    _G.GetRealmName = function() return "TestRealm" end
    _G.UnitName = function() return "TestChar" end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitRace = function() return "Human", "Human" end
    _G.UnitFactionGroup = function() return nil end
    _G.GetLocale = nil
    _G.GetCurrentRegion = function() return 72 end
    _G.FieldJournalDB = nil
    _G.FieldJournalCharacterDB = nil
    _G.FieldJournalRecoveryDB, _G.FieldJournalRecoveryDB2, _G.FieldJournalRecoveryDB3 = nil, nil, nil
    -- LibStub caches libraries by major version for the whole Lua state, and
    -- AceDB-3.0 returns early (before its key computation) when it is already
    -- registered. Reset LibStub so the file body really runs again.
    _G.LibStub = nil
end

local function clearClient()
    _G.GetRealmName, _G.UnitName, _G.UnitClass, _G.UnitRace = nil, nil, nil, nil
    _G.UnitFactionGroup, _G.GetLocale, _G.GetCurrentRegion = nil, nil, nil
    _G.FieldJournalDB, _G.FieldJournalCharacterDB = nil, nil
    _G.LibStub = nil
end

local function capturePrint()
    local lines = {}
    local original = print
    _G.print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return lines, function() _G.print = original end
end

-- Loads the real .toc order for everything this spec needs. CallbackHandler is
-- deliberately left out: AceDB treats it as optional (CallbackDummy) and this
-- addon never registers a database callback.
local function loadStack(withAceDB)
    hostileClient()
    local ns = {}
    local function run(path)
        local chunk, err = loadfile(path)
        assert(chunk, "could not load " .. path .. ": " .. tostring(err))
        chunk("FieldJournal", ns)
    end
    if withAceDB then
        dofile("Libs/LibStub/LibStub.lua")
        dofile("Libs/AceDB-3.0/AceDB-3.0.lua")
    end
    run("Core/Bootstrap.lua")
    run("Core/Database.lua")
    return ns
end

local function test_acedb_initializes_on_a_client_with_a_broken_region()
    local fj = loadStack(true)
    -- These values must be exactly what the hostile client set them to --
    -- AceDB-3.0.lua's patch calls them directly and never reassigns them (see
    -- tests/fj_no_global_reassignment_spec.lua for the stronger, source-level
    -- guarantee; this assertion alone would also have passed under the
    -- abandoned wrap-then-restore shim, so it does not by itself distinguish
    -- "never touched" from "wrapped and restored").
    assert(GetCurrentRegion() == 72, "something reassigned GetCurrentRegion — it must never be touched")
    assert(_G.GetLocale == nil, "something reassigned GetLocale — it must never be touched")
    assert(UnitFactionGroup("player") == nil, "something reassigned UnitFactionGroup — it must never be touched")

    local lines, release = capturePrint()
    local db = fj.Database.initialize()
    release()
    assert(db ~= nil, "initialize returned nil: " .. tostring(fj.databaseError))
    assert(fj.databaseError == nil, "initialize set an error on the happy path: "
        .. tostring(fj.databaseError))
    assert(fj.db == db, "FieldJournal.db was not published")
    assert(type(_G.FieldJournalDB) == "table", "AceDB did not populate the SavedVariables global")
    assert(#lines >= 0, "print capture must not throw")
    clearClient()
end

local function test_defaults_populate_the_character_section()
    local fj = loadStack(true)
    local lines, release = capturePrint()
    local db = fj.Database.initialize()
    release()
    local charData = db.char
    for _, field in ipairs({"entries", "encounters", "diaryEvents", "craftEvents",
                            "bestiary", "objectiveState", "questBookmarks", "backups"}) do
        assert(type(charData[field]) == "table", "db.char." .. field .. " is not a table")
    end
    assert(charData.nextOrder == 0, "db.char.nextOrder must start at 0, got "
        .. tostring(charData.nextOrder))
    assert(charData.legacyMigrated == false,
        "legacyMigrated must default to false, not nil, so `true` survives AceDB's logout strip")
    assert(fj.Database.SCHEMA_VERSION == 2, "SCHEMA_VERSION changed unexpectedly")
    assert(fj.Database.defaults.char.schemaVersion == 0,
        "schemaVersion must default to 0 so a stored 2 is distinguishable from a fresh character")
    assert(fj.Database.initialize() == db, "initialize must be idempotent")
    clearClient()
end

local function test_profile_defaults_are_present()
    local fj = loadStack(true)
    assert(type(fj.Database.defaults.profile) == "table", "defaults.profile is missing")
    assert(fj.Database.defaults.profile.lastTab == "quests",
        "defaults.profile.lastTab must default to \"quests\", got " .. tostring(fj.Database.defaults.profile.lastTab))
    assert(fj.Database.defaults.profile.windowPoint == nil,
        "defaults.profile.windowPoint must default to nil until the player moves the window")
    assert(fj.Database.defaults.profile.showDiary == true,
        "defaults.profile.showDiary must default to true")
    assert(fj.Database.defaults.profile.showBestiary == true,
        "defaults.profile.showBestiary must default to true")
    assert(fj.Database.defaults.profile.showCrafting == true,
        "defaults.profile.showCrafting must default to true")
    local lines, release = capturePrint()
    local db = fj.Database.initialize()
    release()
    assert(#lines == 0, "the happy path must not print anything")
    assert(type(db.profile) == "table", "db.profile was not created by AceDB")
    assert(db.profile.lastTab == "quests", "db.profile.lastTab did not copy its default")
    clearClient()
end

local function test_initialize_is_safe_when_acedb_is_missing()
    local fj = loadStack(false)
    local lines, release = capturePrint()
    local db = fj.Database.initialize()
    release()
    assert(db == nil, "initialize must return nil when AceDB is not loaded")
    assert(fj.db == nil, "FieldJournal.db must stay nil when AceDB is not loaded")
    assert(type(fj.databaseError) == "string", "databaseError must be set for /fj status")
    assert(#lines == 1, "exactly one chat line must explain the failure, got " .. #lines)
    clearClient()
end

local function test_acedb_survives_a_nil_realm_and_a_nil_character_name()
    hostileClient()
    _G.GetRealmName = function() return nil end
    _G.UnitName = function() return nil end
    local ns = {}
    local function run(path)
        local chunk, err = loadfile(path)
        assert(chunk, "could not load " .. path .. ": " .. tostring(err))
        chunk("FieldJournal", ns)
    end
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/AceDB-3.0/AceDB-3.0.lua")
    run("Core/Bootstrap.lua")
    run("Core/Database.lua")
    local lines, release = capturePrint()
    local db = ns.Database.initialize()
    release()
    assert(db ~= nil, "initialize returned nil with a nil realm/character name: " .. tostring(ns.databaseError))
    clearClient()
end

-- The six globals AceDB-3.0.lua's inline patch (Libs/AceDB-3.0/AceDB-3.0.lua)
-- guards with fjCall. GetLocale is included even though hostileClient()
-- already leaves it nil by default, so every guarded global gets the same
-- individual coverage below.
local GUARDED_GLOBALS_FOR_ACEDB = {
    "GetRealmName", "UnitName", "UnitClass", "UnitRace", "UnitFactionGroup",
    "GetCurrentRegion", "GetLocale",
}

-- Each of AceDB-3.0.lua's six guarded globals must be safe to load against
-- even when the global does not exist at all on the client (not merely
-- returns a bad value) -- this is the exact class of bug the fjCall patch
-- exists to prevent, and the whole reason the abandoned Core/ClientCompat.lua
-- shim guarded every one of these, not just GetLocale.
local function test_acedb_survives_each_guarded_global_being_completely_absent()
    for _, name in ipairs(GUARDED_GLOBALS_FOR_ACEDB) do
        hostileClient()
        _G[name] = nil
        local ok, err = pcall(dofile, "Libs/LibStub/LibStub.lua")
        assert(ok, "Libs/LibStub/LibStub.lua failed to load: " .. tostring(err))
        local acedbOk, acedbErr = pcall(dofile, "Libs/AceDB-3.0/AceDB-3.0.lua")
        assert(acedbOk, "Libs/AceDB-3.0/AceDB-3.0.lua crashed with " .. name
            .. " completely absent: " .. tostring(acedbErr))
        clearClient()
    end
end

-- Each of AceDB-3.0.lua's six guarded globals must also be safe to load
-- against when the client's real function exists but throws instead of
-- returning a value -- fjCall's pcall is what protects against this case.
local function test_acedb_survives_each_guarded_global_throwing()
    for _, name in ipairs(GUARDED_GLOBALS_FOR_ACEDB) do
        hostileClient()
        _G[name] = function() error("boom: " .. name .. " is broken on this client") end
        local ok, err = pcall(dofile, "Libs/LibStub/LibStub.lua")
        assert(ok, "Libs/LibStub/LibStub.lua failed to load: " .. tostring(err))
        local acedbOk, acedbErr = pcall(dofile, "Libs/AceDB-3.0/AceDB-3.0.lua")
        assert(acedbOk, "Libs/AceDB-3.0/AceDB-3.0.lua crashed with " .. name
            .. " throwing: " .. tostring(acedbErr))
        clearClient()
    end
end

-- Core/Backup.lua deep-copies db.char into every snapshot and deep-copies a
-- snapshot back out on restore. Both directions depend on this being a true
-- independent copy, so it is published rather than re-implemented there.
local function test_deep_copy_is_a_true_independent_copy()
    local fj = loadStack(true)
    local deepCopy = fj.Database.deepCopy
    assert(type(deepCopy) == "function", "Core/Database.lua must publish deepCopy")

    assert(deepCopy(7) == 7, "a number must pass straight through")
    assert(deepCopy("text") == "text", "a string must pass straight through")
    assert(deepCopy(nil) == nil, "nil must pass straight through")

    local source = {
        name = "Wolf",
        places = {Glade = {count = 2}},
        list = {{guid = "g1"}, {guid = "g2"}},
    }
    local copy = deepCopy(source)
    assert(copy ~= source, "the top-level table must be a new table")
    assert(copy.places ~= source.places, "a nested table must be a new table")
    assert(copy.places.Glade ~= source.places.Glade, "the copy must be deep, not two levels")
    assert(copy.list[2].guid == "g2", "array parts must be copied too")
    assert(copy.list[2] ~= source.list[2], "array members must be new tables")

    source.places.Glade.count = 99
    source.name = "changed"
    assert(copy.places.Glade.count == 2, "mutating the source must not reach the copy")
    assert(copy.name == "Wolf", "mutating the source must not reach the copy")

    copy.places.Glade.count = 1
    assert(source.places.Glade.count == 99, "mutating the copy must not reach the source")
    clearClient()
end

return {
    test_acedb_initializes_on_a_client_with_a_broken_region = test_acedb_initializes_on_a_client_with_a_broken_region,
    test_defaults_populate_the_character_section = test_defaults_populate_the_character_section,
    test_profile_defaults_are_present = test_profile_defaults_are_present,
    test_initialize_is_safe_when_acedb_is_missing = test_initialize_is_safe_when_acedb_is_missing,
    test_acedb_survives_a_nil_realm_and_a_nil_character_name = test_acedb_survives_a_nil_realm_and_a_nil_character_name,
    test_acedb_survives_each_guarded_global_being_completely_absent = test_acedb_survives_each_guarded_global_being_completely_absent,
    test_acedb_survives_each_guarded_global_throwing = test_acedb_survives_each_guarded_global_throwing,
    test_deep_copy_is_a_true_independent_copy = test_deep_copy_is_a_true_independent_copy,
}
