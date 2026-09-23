local env = dofile("tests/wow_env.lua")

-- Every Field Journal file, in .toc order. Each extraction task appends its
-- new module here so the suite always loads exactly what the client loads.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
    "Core/Backup.lua",
    "Core/Export.lua",
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
    assertFunctions(fj.UI, "FieldJournal.UI",
        {"makeLabel", "coloredRectangle", "makeButton", "showCopyBox", "showPasteBox"})
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
        {"snapshotData", "shouldCapture", "capture", "describe",
         "dropSupersededPlaceholders", "repair"})
    assert(fj.Backup.SNAPSHOT_LIMIT == 5, "the rotating ring must keep five snapshots")
    assert(type(fj.Export) == "table", "FieldJournal.Export is missing")
    assertFunctions(fj.Export, "FieldJournal.Export",
        {"message", "buildPayload", "encode", "decode", "validate", "describePayload",
         "importString"})
    assert(fj.Export.ADDON_TAG == "FieldJournal", "the export addon tag changed")
    assert(fj.Export.PAYLOAD_VERSION == 1, "the export payload format version changed")
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

-- The string dialog behind /fj export and /fj import cannot be BUILT under this
-- harness: UI/Widgets.lua's helpers call the real CreateFontString, SetFont and
-- SetColorTexture, and tests/wow_env.lua's frames are no-ops. What can be proved
-- here is the contract that actually protects the player: both helpers run
-- inside a slash command, so neither may ever raise -- a client that refuses a
-- frame call must produce a chat line and a false return, not a Lua error popup.
local function test_the_string_dialog_helpers_never_throw_without_a_real_client()
    local fj = env.loadModules(MODULES)
    local captured = {}
    local original = print
    _G.print = function(...) captured[#captured + 1] = tostring((...)) end
    local copyOk, copyErr = pcall(fj.UI.showCopyBox, "Field Journal export", "hint", "abc")
    local pasteOk, pasteErr = pcall(fj.UI.showPasteBox, "Field Journal import", "hint", function() end)
    _G.print = original

    assert(copyOk, "showCopyBox raised instead of degrading: " .. tostring(copyErr))
    assert(pasteOk, "showPasteBox raised instead of degrading: " .. tostring(pasteErr))
    assert(copyErr == false, "showCopyBox must report failure as false, got " .. tostring(copyErr))
    assert(pasteErr == false, "showPasteBox must report failure as false, got " .. tostring(pasteErr))
    assert(#captured == 2, "each helper must explain itself exactly once, got " .. #captured)
    assert(captured[1]:find("export window could not be opened", 1, true),
        "unexpected export failure line: " .. captured[1])
    assert(captured[2]:find("import window could not be opened", 1, true),
        "unexpected import failure line: " .. captured[2])
end

local function test_visible_tabs_shows_everything_by_default()
    local fj = env.loadModules(MODULES)
    fj.db = {profile = {}}
    local visible = fj.UI.visibleTabs()
    assert(#visible == 4, "expected all four tabs by default, got " .. #visible)
    assert(visible[1][1] == "quests", "quests must be first")
end

local function test_visible_tabs_hides_a_disabled_tab_but_keeps_order()
    local fj = env.loadModules(MODULES)
    fj.db = {profile = {showBestiary = false}}
    local visible = fj.UI.visibleTabs()
    assert(#visible == 3, "expected three tabs with bestiary hidden, got " .. #visible)
    assert(visible[1][1] == "quests" and visible[2][1] == "diary" and visible[3][1] == "craft",
        "the remaining tabs must keep their relative order")
end

local function test_visible_tabs_always_keeps_quests_even_if_everything_else_is_off()
    local fj = env.loadModules(MODULES)
    fj.db = {profile = {showDiary = false, showBestiary = false, showCrafting = false}}
    local visible = fj.UI.visibleTabs()
    assert(#visible == 1 and visible[1][1] == "quests",
        "quests must never be hideable, got " .. #visible .. " tabs")
end

return {
    test_all_modules_load_into_one_namespace = test_all_modules_load_into_one_namespace,
    test_visible_tabs_shows_everything_by_default = test_visible_tabs_shows_everything_by_default,
    test_visible_tabs_hides_a_disabled_tab_but_keeps_order = test_visible_tabs_hides_a_disabled_tab_but_keeps_order,
    test_visible_tabs_always_keeps_quests_even_if_everything_else_is_off = test_visible_tabs_always_keeps_quests_even_if_everything_else_is_off,
    test_the_string_dialog_helpers_never_throw_without_a_real_client = test_the_string_dialog_helpers_never_throw_without_a_real_client,
    test_refresh_if_shown_is_safe_without_a_window = test_refresh_if_shown_is_safe_without_a_window,
    test_window_position_round_trips_through_the_profile = test_window_position_round_trips_through_the_profile,
    test_window_position_defaults_to_center_without_a_saved_point = test_window_position_defaults_to_center_without_a_saved_point,
    test_window_position_functions_are_safe_without_a_database = test_window_position_functions_are_safe_without_a_database,
    test_slash_commands_are_registered = test_slash_commands_are_registered,
}
