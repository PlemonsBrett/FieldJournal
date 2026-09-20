local env = dofile("tests/wow_env.lua")

-- These functions moved out of Core/Bootstrap.lua and into Core/Migrations.lua,
-- where the destination is one flat per-character table instead of
-- db.<collection>[characterKey]. The reconciliation rules are unchanged.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
}

local function load()
    env.install()
    _G.GetRealmName = function() return "Ashenvale" end
    _G.UnitName = function() return "Wren" end
    return env.loadModules(MODULES)
end

local function byGUID(record) return record.guid end

local function test_merge_list_dedupes_by_identity_and_sorts_by_order()
    local fj = load()
    local target = {{guid = "a", order = 2}, {guid = "b", order = 1}}
    local source = {{guid = "b", order = 1}, {guid = "c", order = 3}}
    fj.Migrations.mergeList(target, source, byGUID)
    assert(#target == 3, "expected exactly one new record, got " .. #target)
    assert(target[1].guid == "b" and target[2].guid == "a" and target[3].guid == "c",
        "mergeList did not sort the merged list ascending by order")
end

local function test_merge_list_skips_identityless_records_and_non_tables()
    local fj = load()
    local target = {{guid = "a", order = 1}}
    fj.Migrations.mergeList(target, {{order = 5}}, byGUID)
    assert(#target == 1, "a record with no identity must not be merged in")
    fj.Migrations.mergeList(target, "not a table", byGUID)
    assert(#target == 1, "a non-table source must be ignored")
end

local function test_merge_into_character_keeps_existing_and_maxes_bestiary()
    local fj = load()
    local target = {entries = {kept = {body = "mine"}}}
    fj.Migrations.mergeIntoCharacter(target, {
        entries = {kept = {body = "theirs"}, fresh = {body = "new"}},
        encounters = {{guid = "g1", order = 1}},
        diaryEvents = {{key = "diary:1", seenAt = 10}},
        craftEvents = {{key = "craft:1", seenAt = 11}},
        bestiary = {["creature:1"] = {name = "Wolf", kills = 3,
            places = {Glade = {count = 2}}, drops = {["5"] = {name = "Pelt", count = 1}}, order = 7}},
    }, "first source")
    assert(target.entries.kept.body == "mine", "an existing entry must never be overwritten")
    assert(target.entries.fresh.body == "new", "a new entry must be merged in")
    assert(#target.encounters == 1, "the encounter was not merged")
    assert(#target.diaryEvents == 1, "the diary event was not merged")
    assert(#target.craftEvents == 1, "the craft event was not merged")

    fj.Migrations.mergeIntoCharacter(target, {
        bestiary = {["creature:1"] = {name = "Unidentified creature #1", kills = 5,
            places = {Glade = {count = 9}}, drops = {["5"] = {name = "Pelt", count = 4}}, order = 2}},
    }, "second source")
    local beast = target.bestiary["creature:1"]
    assert(beast.kills == 5, "kills must keep the higher of the two counts")
    assert(beast.order == 7, "order must keep the higher of the two values")
    assert(beast.name == "Wolf", "a real name must never be replaced by an Unidentified placeholder")
    assert(beast.places.Glade.count == 9, "a place must keep the higher encounter count")
    assert(beast.drops["5"].count == 4, "a drop must keep the higher count")
end

local function test_merge_into_character_copies_objective_state_and_bookmarks()
    local fj = load()
    local target = {objectiveState = {[7] = "already here"}}
    fj.Migrations.mergeIntoCharacter(target, {
        objectiveState = {[7] = "incoming", [8] = "fresh"},
        questBookmarks = {[9] = true},
    }, "a source")
    assert(target.objectiveState[7] == "already here", "an existing objective state must win")
    assert(target.objectiveState[8] == "fresh", "a new objective state must be copied")
    assert(target.questBookmarks[9] == true, "a quest bookmark must be copied")
end

local function test_account_slice_reshapes_the_old_account_table()
    local fj = load()
    local slice = fj.Migrations.accountSlice({
        characters = {["R:C"] = {one = {body = "x"}}},
        encounters = {["R:C"] = {{guid = "g1"}}},
        objectiveStates = {["R:C"] = {[1] = "a"}},
        questBookmarks = {["R:C"] = {[1] = true}},
        diaryEvents = "not a table",
    }, "R:C")
    assert(slice.entries.one.body == "x", "characters[key] must become entries")
    assert(#slice.encounters == 1, "encounters[key] must become encounters")
    assert(slice.objectiveState[1] == "a", "objectiveStates[key] must become objectiveState")
    assert(slice.questBookmarks[1] == true, "questBookmarks[key] must become questBookmarks")
    assert(slice.diaryEvents == nil, "a malformed collection must slice to nil, not throw")
    assert(slice.bestiary == nil, "an absent collection must slice to nil")
    assert(fj.Migrations.accountSlice(nil, "R:C") == nil, "a nil account must slice to nil")
end

return {
    test_merge_list_dedupes_by_identity_and_sorts_by_order = test_merge_list_dedupes_by_identity_and_sorts_by_order,
    test_merge_list_skips_identityless_records_and_non_tables = test_merge_list_skips_identityless_records_and_non_tables,
    test_merge_into_character_keeps_existing_and_maxes_bestiary = test_merge_into_character_keeps_existing_and_maxes_bestiary,
    test_merge_into_character_copies_objective_state_and_bookmarks = test_merge_into_character_copies_objective_state_and_bookmarks,
    test_account_slice_reshapes_the_old_account_table = test_account_slice_reshapes_the_old_account_table,
}
