local env = dofile("tests/wow_env.lua")

-- Every Field Journal file, in .toc order. Each extraction task appends its
-- new module here so the suite always loads exactly what the client loads.
local MODULES = {
    "Core/Bootstrap.lua",
    "Data/QuestLog.lua",
    "Data/Bestiary.lua",
    "Data/Diary.lua",
    "Data/Crafting.lua",
    "UI/Widgets.lua",
    "UI/NoteEditor.lua",
    "UI/Window.lua",
    "FieldJournal.lua",
}

local function assertFunctions(tbl, label, names)
    for _, name in ipairs(names) do
        assert(type(tbl[name]) == "function", label .. "." .. name .. " is not a function")
    end
end

local function test_all_modules_load_into_one_namespace()
    local fj = env.loadModules(MODULES)
    assert(type(fj.frame) == "table", "FieldJournal.frame was not created")
    for _, name in ipairs({"QuestLog", "Bestiary", "Diary", "Crafting", "UI"}) do
        assert(type(fj[name]) == "table", "FieldJournal." .. name .. " sub-table is missing")
    end
    assertFunctions(fj, "FieldJournal",
        {"clean", "accessible", "characterKey", "currentZone", "currentPlace",
         "currentMapPosition", "creatureIDFromGUID", "itemName", "moneyText",
         "mergeList", "mergeCharacterCollections", "mergeAccountRecovery"})
    assertFunctions(fj, "FieldJournal", {"savedCharacterKey", "initializeCharacter"})
    assertFunctions(fj.UI, "FieldJournal.UI", {"Refresh", "RefreshIfShown"})
    assertFunctions(fj.UI, "FieldJournal.UI", {"makeLabel", "coloredRectangle", "makeButton"})
    assertFunctions(fj.UI, "FieldJournal.UI",
        {"questOptions", "refreshQuestPicker", "openQuestPicker", "createNoteEditor", "createQuestPicker"})
    assertFunctions(fj.UI, "FieldJournal.UI",
        {"matchingEntries", "zones", "renderDetailBlocks", "rememberedWhen", "rememberedPlace",
         "questStageStory", "marginStory", "showDetail", "createWindow"})
    assertFunctions(fj.QuestLog, "FieldJournal.QuestLog",
        {"recoveredBody", "addEntry", "questTitle", "findUniqueQuestMention", "updateNoteBody",
         "captureNotePage", "captureSpeech", "flushPendingSpeech", "isPlaceholder",
         "importCompletedQuests", "questSpeaker", "linkRecentConversation", "captureQuest",
         "activeQuests", "syncActiveQuestLog", "buildQuestViews", "beginNote", "closeNote",
         "questAccepted", "captureGossip"})
    assertFunctions(fj.Bestiary, "FieldJournal.Bestiary",
        {"observeUnit", "observedName", "recordEncounter", "captureLootSlots", "commitLootSlot",
         "clearLootSlots", "partyKill", "unitDied", "buildBestiaryViews"})
    assertFunctions(fj.Diary, "FieldJournal.Diary",
        {"addLifeEvent", "spellName", "learnedSpell", "currentGroup", "updateGroup",
         "resetGroupSnapshot", "bagSnapshot", "checkMerchant", "trainerShown", "trainerClosed",
         "merchantShown", "merchantBagUpdate", "merchantClosed", "readableItemName",
         "addBatchItem", "merchantItems", "groupLifeEvents", "itemSummary", "batchSection",
         "batchDescription", "buildLifeViews"})
    assertFunctions(fj.Crafting, "FieldJournal.Crafting",
        {"recordCraft", "recordSkillMessage", "recordGather", "tradeskillMessage", "craftedResult"})
end

local function test_refresh_if_shown_is_safe_without_a_window()
    local fj = env.loadModules(MODULES)
    fj.UI.window = nil
    fj.UI.RefreshIfShown()
end

return {
    test_all_modules_load_into_one_namespace = test_all_modules_load_into_one_namespace,
    test_refresh_if_shown_is_safe_without_a_window = test_refresh_if_shown_is_safe_without_a_window,
}
