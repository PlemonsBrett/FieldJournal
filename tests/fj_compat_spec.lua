local env = dofile("tests/wow_env.lua")

-- Loads only the shim, into a fresh namespace. The shim installs itself at the
-- bottom of its own file, exactly as it does in the client.
local function loadShim()
    env.install()
    local ns = {}
    local chunk, err = loadfile("Core/ClientCompat.lua")
    assert(chunk, "could not load Core/ClientCompat.lua: " .. tostring(err))
    chunk("FieldJournal", ns)
    return ns
end

local function test_safe_region_clamps_anything_outside_one_to_five()
    local fj = loadShim()
    local safeRegion = fj.ClientCompat.safeRegion
    assert(safeRegion(1) == 1, "1 is a valid region index and must pass through")
    assert(safeRegion(5) == 5, "5 is a valid region index and must pass through")
    assert(safeRegion(3) == 3, "3 is a valid region index and must pass through")
    assert(safeRegion(0) == 1, "0 is out of range and must clamp to 1")
    assert(safeRegion(6) == 1, "6 is out of range and must clamp to 1")
    assert(safeRegion(72) == 1, "this client's out-of-range value must clamp to 1")
    assert(safeRegion(-1) == 1, "a negative region must clamp to 1")
    assert(safeRegion(2.5) == 1, "a fractional region is not a valid array index")
    assert(safeRegion(nil) == 1, "a missing region must clamp to 1")
    assert(safeRegion("US") == 1, "a string region must clamp to 1")
    fj.ClientCompat.restore()
end

local function test_get_current_region_is_safe_when_the_client_returns_garbage()
    env.install()
    _G.GetCurrentRegion = function() return 72 end
    local fj = loadShim()
    assert(GetCurrentRegion() == 1, "the wrapper must clamp this client's 72 down to 1")
    local regionTable = {"US", "KR", "EU", "TW", "CN"}
    assert(regionTable[GetCurrentRegion()] == "US",
        "AceDB's own lookup must now produce a string, not nil")
    fj.ClientCompat.restore()
    assert(GetCurrentRegion() == 72, "restore must give the client its own function back")
    _G.GetCurrentRegion = nil
end

local function test_get_current_region_is_safe_when_the_client_has_none()
    env.install()
    _G.GetCurrentRegion = nil
    local fj = loadShim()
    assert(GetCurrentRegion() == 1, "a missing client function must still answer a valid index")
    fj.ClientCompat.restore()
    assert(_G.GetCurrentRegion == nil, "restore must remove a global the client never had")
end

local function test_unit_faction_group_falls_back_to_neutral_and_keeps_second_return()
    env.install()
    _G.UnitFactionGroup = function() return nil, nil end
    local fj = loadShim()
    assert(UnitFactionGroup("player") == "Neutral",
        "a nil faction would make AceDB concatenate nil at line 263")
    fj.ClientCompat.restore()

    _G.UnitFactionGroup = function() return "Alliance", "Alliance-localised" end
    fj = loadShim()
    local english, localized = UnitFactionGroup("player")
    assert(english == "Alliance", "a real faction must pass straight through")
    assert(localized == "Alliance-localised",
        "the wrapper must not swallow the second return value other addons read")
    fj.ClientCompat.restore()
    _G.UnitFactionGroup = nil
end

local function test_get_locale_falls_back_to_en_us()
    env.install()
    _G.GetLocale = nil
    local fj = loadShim()
    assert(GetLocale() == "enUS", "a missing GetLocale would make AceDB call :lower() on nil")
    assert(GetLocale():lower() == "enus", "AceDB lowercases the result, so it must be a string")
    fj.ClientCompat.restore()

    _G.GetLocale = function() return "deDE" end
    fj = loadShim()
    assert(GetLocale() == "deDE", "a real locale must pass straight through")
    fj.ClientCompat.restore()
    _G.GetLocale = nil
end

local function test_get_realm_name_falls_back_to_unknown_realm()
    env.install()
    _G.GetRealmName = function() return nil end
    local fj = loadShim()
    assert(GetRealmName() == "Unknown realm",
        "a nil realm would make AceDB concatenate nil at line 259")
    fj.ClientCompat.restore()

    _G.GetRealmName = function() return "Azeroth" end
    fj = loadShim()
    assert(GetRealmName() == "Azeroth", "a real realm must pass straight through")
    fj.ClientCompat.restore()
    _G.GetRealmName = nil
end

local function test_get_realm_name_is_safe_when_the_client_has_none()
    env.install()
    _G.GetRealmName = nil
    local fj = loadShim()
    assert(GetRealmName() == "Unknown realm", "a missing client function must still answer a valid realm")
    fj.ClientCompat.restore()
    assert(_G.GetRealmName == nil, "restore must remove a global the client never had")
end

local function test_unit_name_falls_back_to_unknown_character()
    env.install()
    _G.UnitName = function() return nil end
    local fj = loadShim()
    assert(UnitName("player") == "Unknown character",
        "a nil character would make AceDB concatenate nil at line 260")
    fj.ClientCompat.restore()

    _G.UnitName = function() return "Thrall" end
    fj = loadShim()
    assert(UnitName("player") == "Thrall", "a real character must pass straight through")
    fj.ClientCompat.restore()
    _G.UnitName = nil
end

local function test_unit_name_is_safe_when_the_client_has_none()
    env.install()
    _G.UnitName = nil
    local fj = loadShim()
    assert(UnitName("player") == "Unknown character", "a missing client function must still answer a valid character")
    fj.ClientCompat.restore()
    assert(_G.UnitName == nil, "restore must remove a global the client never had")
end

local function test_install_is_idempotent()
    env.install()
    local raw = function() return "Home" end
    _G.GetRealmName = raw
    local fj = loadShim()
    -- Install has already been called once when the shim loaded.
    -- Call it again to verify it doesn't double-wrap.
    fj.ClientCompat.install()
    -- restore() must hand back the exact original function reference, not a wrapper.
    -- If a second install() captured the already-installed wrapper as "original",
    -- restore() would put that wrapper back, and this assertion would fail.
    fj.ClientCompat.restore()
    assert(_G.GetRealmName == raw, "restore() must return the exact original function after double install()")
    _G.GetRealmName = nil
end

local function test_restore_is_idempotent()
    env.install()
    local raw = function() return "frFR" end
    _G.GetLocale = raw
    local fj = loadShim()
    fj.ClientCompat.restore()
    assert(_G.GetLocale == raw, "restore must return the exact original function")
    -- Call restore again - should be safe and do nothing
    fj.ClientCompat.restore()
    assert(_G.GetLocale == raw, "calling restore() twice must still return the original function")
    _G.GetLocale = nil
end

local function test_restore_before_install_is_safe()
    env.install()
    local raw = function() return "TestRealm" end
    _G.GetRealmName = raw
    -- Create a fresh namespace that won't auto-call install()
    local ns = {}
    local chunk, err = loadfile("Core/ClientCompat.lua")
    assert(chunk, "could not load Core/ClientCompat.lua: " .. tostring(err))
    chunk("FieldJournal", ns)
    -- The module will have called install() when it loaded, so restore it first
    ns.ClientCompat.restore()
    assert(_G.GetRealmName == raw, "first restore() must return the original function")
    -- Now call restore again before any new install() - should not error and not change anything
    ns.ClientCompat.restore()
    assert(_G.GetRealmName == raw, "calling restore() twice must not error and leave globals unchanged")
    _G.GetRealmName = nil
end

return {
    test_safe_region_clamps_anything_outside_one_to_five = test_safe_region_clamps_anything_outside_one_to_five,
    test_get_current_region_is_safe_when_the_client_returns_garbage = test_get_current_region_is_safe_when_the_client_returns_garbage,
    test_get_current_region_is_safe_when_the_client_has_none = test_get_current_region_is_safe_when_the_client_has_none,
    test_unit_faction_group_falls_back_to_neutral_and_keeps_second_return = test_unit_faction_group_falls_back_to_neutral_and_keeps_second_return,
    test_get_locale_falls_back_to_en_us = test_get_locale_falls_back_to_en_us,
    test_get_realm_name_falls_back_to_unknown_realm = test_get_realm_name_falls_back_to_unknown_realm,
    test_get_realm_name_is_safe_when_the_client_has_none = test_get_realm_name_is_safe_when_the_client_has_none,
    test_unit_name_falls_back_to_unknown_character = test_unit_name_falls_back_to_unknown_character,
    test_unit_name_is_safe_when_the_client_has_none = test_unit_name_is_safe_when_the_client_has_none,
    test_install_is_idempotent = test_install_is_idempotent,
    test_restore_is_idempotent = test_restore_is_idempotent,
    test_restore_before_install_is_safe = test_restore_before_install_is_safe,
}
