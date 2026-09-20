local env = dofile("tests/wow_env.lua")

-- Mirrors tests/fj_database_spec.lua's hostileClient/clearClient pattern so
-- AceDB can actually be loaded and produce a real FieldJournal.db, which the
-- Profile Manager registration call is expected to receive.
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
    _G.LibStub = nil
    _G.LibAT = nil
end

local function clearClient()
    _G.GetRealmName, _G.UnitName, _G.UnitClass, _G.UnitRace = nil, nil, nil, nil
    _G.UnitFactionGroup, _G.GetLocale, _G.GetCurrentRegion = nil, nil, nil
    _G.FieldJournalDB, _G.FieldJournalCharacterDB = nil, nil
    _G.LibStub, _G.LibAT = nil, nil
end

local function loadStack()
    hostileClient()
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
    run("Core/DevTools.lua")
    return ns
end

-- Records each RegisterAddon-style call it receives; optionally raises to
-- exercise Core/DevTools.lua's pcall guarding around every LibAT call.
local function mockLibAT(shouldFail)
    local calls = {}
    local function maybeFail(name)
        if shouldFail then error("boom: " .. name .. " is broken on this client") end
    end
    local LibAT = {
        Logger = {
            RegisterAddon = function(name)
                calls.logger = name
                maybeFail("Logger.RegisterAddon")
                return {error = function() end, info = function() end}
            end,
        },
        ProfileManager = {
            RegisterAddon = function(self, opts)
                calls.profileManager = opts
                maybeFail("ProfileManager.RegisterAddon")
            end,
        },
        SetupWizard = {
            RegisterAddon = function(self, id, opts)
                calls.setupWizard = {id = id, opts = opts}
                maybeFail("SetupWizard.RegisterAddon")
            end,
        },
    }
    return LibAT, calls
end

-- Reproduces Core/Bootstrap.lua's ADDON_LOADED handler order: register the
-- logger before the database opens (so a database-open failure can still be
-- logged), then initialize the database, then register everything else.
local function runFullSequence(fj)
    fj.DevTools.registerLogger()
    fj.Database.initialize()
    fj.DevTools.initialize()
end

local function test_loads_without_libat()
    local fj = loadStack()
    runFullSequence(fj)
    assert(fj.log == nil, "FieldJournal.log must stay nil without LibAT installed")
    clearClient()
end

local function test_registers_with_libat_present()
    local fj = loadStack()
    local LibAT, calls = mockLibAT(false)
    _G.LibAT = LibAT
    runFullSequence(fj)

    assert(calls.logger == "FieldJournal", "Logger.RegisterAddon was not called with the addon name")
    assert(type(fj.log) == "table", "FieldJournal.log was not published from the mock logger")

    assert(calls.profileManager and calls.profileManager.name == "FieldJournal",
        "ProfileManager.RegisterAddon was not called with the addon name")
    assert(calls.profileManager.db == fj.db, "ProfileManager.RegisterAddon must receive FieldJournal.db")

    assert(calls.setupWizard and calls.setupWizard.id == "fieldjournal",
        "SetupWizard.RegisterAddon was not called with the expected id")
    assert(type(calls.setupWizard.opts.pages) == "table" and #calls.setupWizard.opts.pages > 0,
        "SetupWizard.RegisterAddon must receive at least one page")
    clearClient()
end

local function test_survives_libat_api_mismatch()
    local fj = loadStack()
    _G.LibAT = mockLibAT(true)
    local ok, err = pcall(runFullSequence, fj)
    assert(ok, "DevTools must never let a LibAT API mismatch escape: " .. tostring(err))
    assert(fj.log == nil, "a failed Logger.RegisterAddon must not publish a broken logger")
    clearClient()
end

return {
    test_loads_without_libat = test_loads_without_libat,
    test_registers_with_libat_present = test_registers_with_libat_present,
    test_survives_libat_api_mismatch = test_survives_libat_api_mismatch,
}
