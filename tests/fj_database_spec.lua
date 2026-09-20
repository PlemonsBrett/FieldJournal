local env = dofile("tests/wow_env.lua")

-- Reproduces this addon's actual client as closely as plain Lua allows:
-- GetCurrentRegion() answers outside AceDB's {US,KR,EU,TW,CN} table,
-- UnitFactionGroup() answers nil, and GetLocale() does not exist at all.
-- Loading AceDB-3.0 under these conditions is exactly what killed the live
-- client before Core/ClientCompat.lua existed.
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
    run("Core/ClientCompat.lua")
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
    -- Core/Database.lua restores the globals at load; the client's own broken
    -- answers must be back exactly as they were.
    assert(GetCurrentRegion() == 72, "Core/Database.lua did not restore GetCurrentRegion")
    assert(_G.GetLocale == nil, "Core/Database.lua did not restore the missing GetLocale")

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

return {
    test_acedb_initializes_on_a_client_with_a_broken_region = test_acedb_initializes_on_a_client_with_a_broken_region,
    test_defaults_populate_the_character_section = test_defaults_populate_the_character_section,
    test_initialize_is_safe_when_acedb_is_missing = test_initialize_is_safe_when_acedb_is_missing,
}
