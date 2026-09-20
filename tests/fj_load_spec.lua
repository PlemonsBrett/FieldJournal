local env = dofile("tests/wow_env.lua")

-- Every Field Journal file, in .toc order. Each extraction task appends its
-- new module here so the suite always loads exactly what the client loads.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
    "Core/Backup.lua",
    "Core/SlashCommands.lua",
    "Core/DevTools.lua",
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
         "currentMapPosition", "creatureIDFromGUID", "itemName", "moneyText"})
    assertFunctions(fj, "FieldJournal", {"initializeCharacter"})
    assert(fj.savedCharacterKey == nil, "savedCharacterKey moved to Migrations.legacyCharacterKey")
    assert(fj.mergeList == nil, "mergeList moved to FieldJournal.Migrations")
    assert(fj.mergeCharacterCollections == nil, "mergeCharacterCollections moved to Migrations.mergeIntoCharacter")
    assert(fj.mergeAccountRecovery == nil, "mergeAccountRecovery moved to Migrations.accountSlice")
    assertFunctions(fj.UI, "FieldJournal.UI", {"Refresh", "RefreshIfShown"})
    assertFunctions(fj.UI, "FieldJournal.UI", {"makeLabel", "coloredRectangle", "makeButton"})
    assertFunctions(fj.UI, "FieldJournal.UI",
        {"questOptions", "refreshQuestPicker", "openQuestPicker", "createNoteEditor", "createQuestPicker"})
    assertFunctions(fj.UI, "FieldJournal.UI",
        {"matchingEntries", "zones", "renderDetailBlocks", "rememberedWhen", "rememberedPlace",
         "questStageStory", "marginStory", "showDetail", "createWindow",
         "saveWindowPosition", "restoreWindowPosition"})
    assert(type(fj.Database) == "table", "FieldJournal.Database is missing")
    assertFunctions(fj.Database, "FieldJournal.Database", {"initialize", "deepCopy"})
    assert(fj.Database.SCHEMA_VERSION == 2, "SCHEMA_VERSION changed unexpectedly")
    assert(type(fj.Database.defaults.char) == "table", "defaults.char is missing")
    assert(type(fj.Database.defaults.profile) == "table", "defaults.profile is missing")
    assert(type(fj.DevTools) == "table", "FieldJournal.DevTools is missing")
    assertFunctions(fj.DevTools, "FieldJournal.DevTools", {"registerLogger", "initialize"})
    assert(type(fj.logError) == "function", "FieldJournal.logError is missing")
    assert(type(fj.Migrations) == "table", "FieldJournal.Migrations is missing")
    assertFunctions(fj.Migrations, "FieldJournal.Migrations",
        {"run", "migrateLegacy", "legacyCharacterKey", "accountSlice", "counts",
         "mergeList", "mergeIntoCharacter", "highestOrder", "countText"})
    assert(type(fj.Backup) == "table", "FieldJournal.Backup is missing")
    assertFunctions(fj.Backup, "FieldJournal.Backup",
        {"snapshotData", "shouldCapture", "capture", "describe"})
    assert(fj.Backup.SNAPSHOT_LIMIT == 5, "the rotating ring must keep five snapshots")
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

-- A minimal stand-in for a WoW frame, exposing only GetPoint/SetPoint.
-- Deliberately not routed through tests/wow_env.lua's noopFrame() mock (whose
-- every method is a no-op returning nil, by design) since these two
-- functions specifically need a controllable point to round-trip.
local function fakeFrame(initialPoint)
    local calls = {}
    return {
        GetPoint = function()
            if not initialPoint then return nil end
            return initialPoint.point, nil, initialPoint.relativePoint, initialPoint.x, initialPoint.y
        end,
        SetPoint = function(_, point, relativeTo, relativePoint, x, y)
            calls.setPoint = {point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y}
        end,
    }, calls
end

local function test_window_position_round_trips_through_the_profile()
    local fj = env.loadModules(MODULES)
    fj.db = {profile = {}}

    local movedFrame = fakeFrame({point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -20})
    fj.UI.saveWindowPosition(movedFrame)
    local saved = fj.db.profile.windowPoint
    assert(saved and saved.point == "TOPLEFT" and saved.relativePoint == "TOPLEFT"
        and saved.x == 10 and saved.y == -20, "saveWindowPosition did not record the frame's point")

    local restoredFrame, calls = fakeFrame()
    fj.UI.restoreWindowPosition(restoredFrame)
    assert(calls.setPoint and calls.setPoint.point == "TOPLEFT" and calls.setPoint.relativePoint == "TOPLEFT"
        and calls.setPoint.x == 10 and calls.setPoint.y == -20,
        "restoreWindowPosition did not apply the saved point")
end

local function test_window_position_defaults_to_center_without_a_saved_point()
    local fj = env.loadModules(MODULES)
    fj.db = {profile = {}}
    local frame, calls = fakeFrame()
    fj.UI.restoreWindowPosition(frame)
    assert(calls.setPoint and calls.setPoint.point == "CENTER",
        "restoreWindowPosition must default to CENTER when nothing is saved")
end

local function test_window_position_functions_are_safe_without_a_database()
    local fj = env.loadModules(MODULES)
    fj.db = nil
    local frame, calls = fakeFrame({point = "TOPLEFT", relativePoint = "TOPLEFT", x = 1, y = 2})
    fj.UI.saveWindowPosition(frame) -- must not throw with no FieldJournal.db to write into

    local restoredFrame, restoreCalls = fakeFrame()
    fj.UI.restoreWindowPosition(restoredFrame)
    assert(restoreCalls.setPoint and restoreCalls.setPoint.point == "CENTER",
        "restoreWindowPosition must fall back to CENTER when FieldJournal.db is nil")
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
    test_window_position_round_trips_through_the_profile = test_window_position_round_trips_through_the_profile,
    test_window_position_defaults_to_center_without_a_saved_point = test_window_position_defaults_to_center_without_a_saved_point,
    test_window_position_functions_are_safe_without_a_database = test_window_position_functions_are_safe_without_a_database,
    test_slash_commands_are_registered = test_slash_commands_are_registered,
}
