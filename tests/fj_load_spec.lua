local env = dofile("tests/wow_env.lua")

-- Every Field Journal file, in .toc order. Each extraction task appends its
-- new module here so the suite always loads exactly what the client loads.
local MODULES = {
    "Core/ClientCompat.lua",
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/SlashCommands.lua",
    "Data/QuestLog.lua",
    "Data/Bestiary.lua",
    "Data/Diary.lua",
    "Data/Crafting.lua",
    "UI/Widgets.lua",
    "UI/NoteEditor.lua",
    "UI/Window.lua",
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
    assert(type(fj.ClientCompat) == "table", "FieldJournal.ClientCompat is missing")
    assertFunctions(fj.ClientCompat, "FieldJournal.ClientCompat", {"install", "restore", "safeRegion"})
    fj.ClientCompat.restore()
    assert(type(fj.Database) == "table", "FieldJournal.Database is missing")
    assertFunctions(fj.Database, "FieldJournal.Database", {"initialize"})
    assert(fj.Database.SCHEMA_VERSION == 2, "SCHEMA_VERSION changed unexpectedly")
    assert(type(fj.Database.defaults.char) == "table", "defaults.char is missing")
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

local function test_slash_commands_are_registered()
    local fj = env.loadModules(MODULES)
    assert(_G.SLASH_FIELDJOURNAL1 == "/fieldjournal", "the long slash command changed")
    assert(_G.SLASH_FIELDJOURNAL2 == "/fj", "the short slash command changed")
    assert(type(_G.SlashCmdList.FIELDJOURNAL) == "function", "the slash handler was not registered")
    assert(fj ~= nil, "the namespace must still be returned")
end

return {
    test_all_modules_load_into_one_namespace = test_all_modules_load_into_one_namespace,
    test_refresh_if_shown_is_safe_without_a_window = test_refresh_if_shown_is_safe_without_a_window,
    test_slash_commands_are_registered = test_slash_commands_are_registered,
}
