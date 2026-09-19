local function test_acedb_new_creates_per_character_table()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")

    -- AceDB-3.0 computes realm/char/class/race/faction/locale/region keys at
    -- file-load time, so these WoW globals must exist before the dofile below.
    _G.GetRealmName = function() return "TestRealm" end
    _G.UnitName = function() return "TestChar" end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitRace = function() return "Human", "Human" end
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.GetLocale = function() return "enUS" end
    _G.GetCurrentRegion = function() return 1 end
    _G.CreateFrame = function()
        return {
            RegisterEvent = function() end,
            SetScript = function() end,
        }
    end

    dofile("Libs/AceDB-3.0/AceDB-3.0.lua")

    _G.FieldJournalTestDB = nil
    local AceDB = LibStub:GetLibrary("AceDB-3.0")
    local db = AceDB:New("FieldJournalTestDB", {char = {entries = {}}}, true)

    db.char.entries.foo = "bar"
    assert(type(FieldJournalTestDB) == "table", "AceDB did not populate the global SavedVariables table")
    assert(db.char.entries.foo == "bar", "db.char did not persist the written value")

    _G.GetRealmName, _G.UnitName, _G.UnitClass, _G.UnitRace = nil, nil, nil, nil
    _G.UnitFactionGroup, _G.GetLocale, _G.GetCurrentRegion = nil, nil, nil
    _G.CreateFrame = nil
end

return {
    test_acedb_new_creates_per_character_table = test_acedb_new_creates_per_character_table,
}
