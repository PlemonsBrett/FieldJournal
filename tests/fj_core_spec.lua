local env = dofile("tests/wow_env.lua")

local function load()
    return env.loadModules({"Core/Bootstrap.lua"})
end

local function test_clean_trims_and_guards_non_strings()
    local fj = load()
    assert(fj.clean("  hello  ") == "hello", "clean did not trim both ends")
    assert(fj.clean("no padding") == "no padding", "clean altered an already-clean string")
    assert(fj.clean("\n\tspaced\t\n") == "spaced", "clean did not trim tabs and newlines")
    assert(fj.clean("a  b") == "a  b", "clean collapsed interior whitespace")
    assert(fj.clean("") == "", "clean did not return empty for an empty string")
    assert(fj.clean(nil) == "", "clean did not return empty for nil")
    assert(fj.clean(42) == "", "clean did not return empty for a number")
end

local function test_money_text_formats_coin_amounts()
    local fj = load()
    assert(fj.moneyText(0) == "0 copper", "zero should read as 0 copper")
    assert(fj.moneyText(nil) == "0 copper", "nil should read as 0 copper")
    assert(fj.moneyText(-5) == "0 copper", "negative amounts clamp to 0 copper")
    assert(fj.moneyText(10000) == "1 gold", "whole gold should omit silver and copper")
    assert(fj.moneyText(10101) == "1 gold, 1 silver, 1 copper", "mixed amount formatted wrong")
    assert(fj.moneyText("250") == "2 silver, 50 copper", "numeric strings should be accepted")
    assert(fj.moneyText(100) == "1 silver", "exact silver should omit copper")
end

local function test_creature_id_from_guid()
    local fj = load()
    assert(fj.creatureIDFromGUID("Creature-0-1234-0-11-448-000136DF0A") == "448",
        "did not pull the creature ID out of a well-formed GUID")
    assert(fj.creatureIDFromGUID("Vehicle-0-1234-0-11-999-000136DF0A") == "999",
        "did not pull the creature ID out of a Vehicle GUID")
    assert(fj.creatureIDFromGUID("Player-1234-56789ABC") == nil,
        "a player GUID has no creature ID")
    assert(fj.creatureIDFromGUID(nil) == nil, "nil GUID must return nil")
    assert(fj.creatureIDFromGUID(42) == nil, "non-string GUID must return nil")
end

local function test_accessible_defaults_to_true_without_client_guards()
    local fj = load()
    _G.canaccessvalue, _G.issecretvalue = nil, nil
    assert(fj.accessible("anything") == true,
        "without canaccessvalue/issecretvalue every value is accessible")
end

return {
    test_clean_trims_and_guards_non_strings = test_clean_trims_and_guards_non_strings,
    test_money_text_formats_coin_amounts = test_money_text_formats_coin_amounts,
    test_creature_id_from_guid = test_creature_id_from_guid,
    test_accessible_defaults_to_true_without_client_guards = test_accessible_defaults_to_true_without_client_guards,
}
