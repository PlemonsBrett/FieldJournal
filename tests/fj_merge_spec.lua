local env = dofile("tests/wow_env.lua")

-- Updated in the task that moves these functions into Core/Bootstrap.lua.
local MODULES = {
    "Core/Bootstrap.lua",
}

local function loadWithDB()
    local fj = env.loadModules(MODULES)
    fj.db = {
        nextOrder = 0, characters = {}, objectiveStates = {}, questBookmarks = {},
        encounters = {}, diaryEvents = {}, craftEvents = {}, bestiary = {},
    }
    return fj
end

local function byGUID(record) return record.guid end

local function test_merge_list_dedupes_by_identity_and_sorts_by_order()
    local fj = loadWithDB()
    local target = {{guid = "a", order = 2}, {guid = "b", order = 1}}
    local source = {{guid = "b", order = 1}, {guid = "c", order = 3}}
    fj.mergeList(target, source, byGUID)
    assert(#target == 3, "expected exactly one new record, got " .. #target)
    assert(target[1].guid == "b" and target[2].guid == "a" and target[3].guid == "c",
        "mergeList did not sort the merged list ascending by order")
end

local function test_merge_list_skips_identityless_records_and_non_tables()
    local fj = loadWithDB()
    local target = {{guid = "a", order = 1}}
    fj.mergeList(target, {{order = 5}}, byGUID)
    assert(#target == 1, "a record with no identity must not be merged in")
    fj.mergeList(target, "not a table", byGUID)
    assert(#target == 1, "a non-table source must be ignored")
end

local function test_merge_character_collections_keeps_existing_and_maxes_bestiary()
    local fj = loadWithDB()
    fj.db.characters["R:C"] = {kept = {body = "mine"}}
    fj.mergeCharacterCollections("R:C", {
        entries = {kept = {body = "theirs"}, fresh = {body = "new"}},
        encounters = {{guid = "g1", order = 1}},
        diaryEvents = {{key = "diary:1", seenAt = 10}},
        craftEvents = {{key = "craft:1", seenAt = 11}},
        bestiary = {["creature:1"] = {name = "Wolf", kills = 3,
            places = {Glade = {count = 2}}, drops = {["5"] = {name = "Pelt", count = 1}}, order = 7}},
    })
    assert(fj.db.characters["R:C"].kept.body == "mine", "an existing entry must never be overwritten")
    assert(fj.db.characters["R:C"].fresh.body == "new", "a new entry must be merged in")
    assert(#fj.db.encounters["R:C"] == 1, "the encounter was not merged")
    assert(#fj.db.diaryEvents["R:C"] == 1, "the diary event was not merged")
    assert(#fj.db.craftEvents["R:C"] == 1, "the craft event was not merged")

    fj.mergeCharacterCollections("R:C", {
        bestiary = {["creature:1"] = {name = "Unidentified creature #1", kills = 5,
            places = {Glade = {count = 9}}, drops = {["5"] = {name = "Pelt", count = 4}}, order = 2}},
    })
    local beast = fj.db.bestiary["R:C"]["creature:1"]
    assert(beast.kills == 5, "kills must keep the higher of the two counts")
    assert(beast.order == 7, "order must keep the higher of the two values")
    assert(beast.name == "Wolf", "a real name must never be replaced by an Unidentified placeholder")
    assert(beast.places.Glade.count == 9, "a place must keep the higher encounter count")
    assert(beast.drops["5"].count == 4, "a drop must keep the higher count")
end

local function test_merge_account_recovery_raises_next_order()
    local fj = loadWithDB()
    fj.db.nextOrder = 3
    fj.mergeAccountRecovery({
        characters = {["R:C"] = {one = {body = "x"}}},
        encounters = {["R:C"] = {{guid = "g1"}}},
        nextOrder = 9,
    })
    assert(fj.db.characters["R:C"].one.body == "x", "recovery entries were not merged")
    assert(#fj.db.encounters["R:C"] == 1, "recovery encounters were not merged")
    assert(fj.db.nextOrder == 9, "nextOrder must rise to the recovery snapshot's value")
    fj.mergeAccountRecovery(nil)
    fj.mergeAccountRecovery({})
    assert(fj.db.nextOrder == 9, "a nil or shapeless recovery table must be a no-op")
end

return {
    test_merge_list_dedupes_by_identity_and_sorts_by_order = test_merge_list_dedupes_by_identity_and_sorts_by_order,
    test_merge_list_skips_identityless_records_and_non_tables = test_merge_list_skips_identityless_records_and_non_tables,
    test_merge_character_collections_keeps_existing_and_maxes_bestiary = test_merge_character_collections_keeps_existing_and_maxes_bestiary,
    test_merge_account_recovery_raises_next_order = test_merge_account_recovery_raises_next_order,
}
