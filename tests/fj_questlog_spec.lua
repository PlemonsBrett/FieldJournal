local env = dofile("tests/wow_env.lua")

local function load()
    return env.loadModules({"Core/Bootstrap.lua", "Data/QuestLog.lua"})
end

local function test_is_placeholder_only_matches_unrecovered_past_quests()
    local fj = load()
    local isPlaceholder = fj.QuestLog.isPlaceholder
    assert(isPlaceholder(nil) == false, "nil is not a placeholder")
    assert(isPlaceholder({kind = "quest", body = "This quest was completed before Field Journal"}) == false,
        "only pastQuest entries can be placeholders")
    assert(isPlaceholder({kind = "pastQuest",
        body = "This quest was completed before Field Journal began keeping notes."}) == true,
        "the completed-before-journal wording marks a placeholder")
    assert(isPlaceholder({kind = "pastQuest",
        body = "The original words have not been found."}) == true,
        "the words-not-found wording marks a placeholder")
    assert(isPlaceholder({kind = "pastQuest", body = "A real recovered description."}) == false,
        "a recovered description is not a placeholder")
    assert(isPlaceholder({kind = "pastQuest"}) == false, "a bodyless pastQuest is not a placeholder")
end

local function test_update_note_body_joins_pages_in_order()
    local fj = load()
    local single = {pages = {[1] = "  only page  "}}
    fj.QuestLog.updateNoteBody(single)
    assert(single.body == "only page", "a one-page note must not be labelled, got: " .. single.body)

    local multi = {pages = {[1] = "first", [3] = "third"}}
    fj.QuestLog.updateNoteBody(multi)
    assert(multi.body == "Page 1\nfirst\n\nPage 3\nthird",
        "multi-page notes must be labelled and ordered, got: " .. multi.body)
end

return {
    test_is_placeholder_only_matches_unrecovered_past_quests = test_is_placeholder_only_matches_unrecovered_past_quests,
    test_update_note_body_joins_pages_in_order = test_update_note_body_joins_pages_in_order,
}
