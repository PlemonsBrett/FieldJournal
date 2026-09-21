local env = dofile("tests/wow_env.lua")

-- The whole slash-command surface, driven through the real handler the addon
-- registers as SlashCmdList.FIELDJOURNAL. UI/ is not loaded; the two UI calls
-- the handler makes are stubbed below.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
    "Core/Backup.lua",
    "Core/Export.lua",
    "Core/SlashCommands.lua",
}

local function load()
    env.install()
    -- The real vendored libraries, exactly as tests/fj_export_spec.lua loads
    -- them: /fj export drives the genuine compression and serialisation here,
    -- never a stand-in for it.
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")
    _G.GetRealmName = function() return "Ashenvale" end
    _G.UnitName = function() return "Wren" end
    _G.FieldJournalCharacterDB = nil
    _G.FieldJournalRecoveryDB, _G.FieldJournalRecoveryDB2, _G.FieldJournalRecoveryDB3 = nil, nil, nil
    local fj = env.loadModules(MODULES)
    fj.Diary.resetGroupSnapshot = function() end
    fj.QuestLog.syncActiveQuestLog = function() end
    fj.Bestiary.observeUnit = function() end
    fj.UI.createWindow = function() fj.UI.window = true end
    fj.UI.RefreshIfShown = function() end
    -- UI/Widgets.lua is not loaded here: its helpers call the real
    -- CreateFontString/SetFont, which this harness does not provide. The two
    -- string dialogs are recorded instead, so the wiring can be asserted without
    -- a client. UI/Widgets.lua's own never-throws contract is covered by
    -- tests/fj_load_spec.lua.
    fj.UI.shown = {}
    fj.UI.showCopyBox = function(title, hint, text)
        fj.UI.shown.copy = {title = title, hint = hint, text = text}
        return true
    end
    fj.UI.showPasteBox = function(title, hint, onAccept)
        fj.UI.shown.paste = {title = title, hint = hint, onAccept = onAccept}
        return true
    end
    return fj
end

local function freshChar()
    return {
        schemaVersion = 2, legacyMigrated = true, nextOrder = 0,
        entries = {}, encounters = {}, diaryEvents = {}, craftEvents = {},
        bestiary = {}, objectiveState = {}, questBookmarks = {}, backups = {},
    }
end

local function capturePrint()
    local lines = {}
    local original = print
    _G.print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return lines, function() _G.print = original end
end

local function run(command)
    local lines, release = capturePrint()
    local ok, err = pcall(_G.SlashCmdList.FIELDJOURNAL, command)
    release()
    assert(ok, "/fj " .. command .. " threw: " .. tostring(err))
    return table.concat(lines, "\n")
end

local function withCharacter(fj, charData)
    fj.db = {char = charData}
    -- initializeCharacter() returns early when it has already loaded this
    -- character key, so clear it first: an export/import test points the same
    -- namespace at a second charData table within one test.
    fj.loadedCharacterKey = nil
    fj.initializeCharacter()
end

local function test_fj_backup_lists_the_ring()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    withCharacter(fj, charData)
    fj.Backup.capture(charData)

    local output = run("backup")
    assert(output:find("1 of 5 backup snapshots", 1, true),
        "expected a ring summary line, got:\n" .. output)
    assert(output:find("1 entries", 1, true), "expected the snapshot's counts, got:\n" .. output)
    assert(#charData.backups == 1, "listing the ring must never take a snapshot")
end

local function test_fj_backup_now_takes_a_snapshot()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    withCharacter(fj, charData)

    local output = run("backup now")
    assert(#charData.backups == 1, "'/fj backup now' must take a snapshot")
    assert(output:find("took a backup snapshot", 1, true),
        "expected a confirmation line, got:\n" .. output)

    local second = run("backup now")
    assert(#charData.backups == 1,
        "'/fj backup now' must honour the same skip-if-unchanged rule as a login snapshot")
    assert(second:find("nothing has changed", 1, true),
        "expected the unchanged explanation, got:\n" .. second)
end

local function test_fj_repair_restores_from_the_ring_and_rebuilds_the_bestiary_index()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "Creature-0-0-0-0-99-0001", name = "Wolf",
        place = "Glade", zone = "Glade", seenAt = 5, order = 1}
    withCharacter(fj, charData)
    fj.Backup.capture(charData)

    charData.encounters = {}
    charData.bestiary = {}

    local output = run("repair")

    assert(#charData.encounters == 1,
        "the lost encounter must be restored from the ring, got " .. #charData.encounters)
    assert(charData.bestiary["creature:99"] ~= nil,
        "the bestiary index must then be rebuilt from the restored encounter")
    assert(charData.bestiary["creature:99"].kills == 1, "the rebuilt index must count the kill")
    assert(output:find("restored 1 encounters", 1, true),
        "the restore must report itself before the index rebuild line, got:\n" .. output)
end

local function test_fj_repair_is_safe_with_no_database()
    local fj = load()
    fj.db = nil
    local output = run("repair")
    assert(output:find("not available", 1, true),
        "expected the degraded-database explanation, got:\n" .. output)
end

local function test_fj_status_reports_the_backup_ring()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    withCharacter(fj, charData)
    fj.Backup.capture(charData)

    local output = run("status")
    assert(output:find("backups 1/5", 1, true),
        "expected the backup ring state in /fj status, got:\n" .. output)
    assert(output:find("schema v2", 1, true),
        "the existing status fields must be unchanged, got:\n" .. output)
    assert(output:find("legacy migration yes", 1, true),
        "the existing status fields must be unchanged, got:\n" .. output)
end

local function test_fj_export_opens_a_copy_box_with_a_printable_string()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    withCharacter(fj, charData)

    local output = run("export")
    local shown = fj.UI.shown.copy
    assert(shown, "'/fj export' must open the copy box, chat was:\n" .. output)
    assert(shown.title == "Field Journal export", "unexpected dialog title: " .. tostring(shown.title))
    assert(type(shown.text) == "string" and #shown.text > 0, "the dialog must be given the export string")
    assert(not shown.text:find("[^%w%(%)]"), "the export string must be printable")
    assert(output:find("export ready", 1, true), "expected a chat confirmation, got:\n" .. output)

    local payload = fj.Export.decode(shown.text)
    assert(payload and payload.data.entries["quest:1"].body == "one",
        "the string in the dialog must be this character's own journal")
    assert(#charData.backups == 0, "exporting must never write to the backup ring")
end

local function test_fj_export_refuses_an_empty_journal_without_opening_a_dialog()
    local fj = load()
    withCharacter(fj, freshChar())
    local output = run("export")
    assert(fj.UI.shown.copy == nil, "an empty journal must not open a dialog")
    assert(output:find("journal is empty", 1, true), "expected the empty-journal message, got:\n" .. output)
end

local function test_fj_import_with_a_string_merges_and_rebuilds_the_bestiary_index()
    local fj = load()
    local source = freshChar()
    source.encounters[1] = {guid = "Creature-0-0-0-0-99-0001", name = "Wolf",
        place = "Glade", zone = "Glade", seenAt = 5, order = 1}
    withCharacter(fj, source)
    local text = fj.Export.encode(source)

    local target = freshChar()
    withCharacter(fj, target)
    local output = run("import " .. text)

    assert(#target.encounters == 1, "the encounter must be imported, got " .. #target.encounters)
    assert(target.bestiary["creature:99"] ~= nil, "the bestiary index must then be rebuilt")
    assert(target.bestiary["creature:99"].kills == 1, "the rebuilt index must count the kill")
    assert(output:find("imported 1 encounters", 1, true), "expected the import report, got:\n" .. output)
    assert(output:find("rebuilt the bestiary index", 1, true), "expected the rebuild line, got:\n" .. output)
end

local function test_fj_import_with_no_argument_opens_the_paste_box()
    local fj = load()
    local source = freshChar()
    source.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    withCharacter(fj, source)
    local text = fj.Export.encode(source)

    local target = freshChar()
    withCharacter(fj, target)
    run("import")
    local shown = fj.UI.shown.paste
    assert(shown, "'/fj import' with no argument must open the paste box")
    assert(shown.title == "Field Journal import", "unexpected dialog title: " .. tostring(shown.title))
    assert(type(shown.onAccept) == "function", "the paste box must be given an accept callback")

    local lines, release = capturePrint()
    local ok, err = pcall(shown.onAccept, text)
    release()
    assert(ok, "the paste box's accept callback threw: " .. tostring(err))
    assert(target.entries["quest:1"] ~= nil, "accepting the paste box must import the string")
    assert(table.concat(lines, "\n"):find("imported 1 entries", 1, true),
        "expected the import report, got:\n" .. table.concat(lines, "\n"))
end

local function test_fj_import_rejects_junk_without_changing_anything()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    withCharacter(fj, charData)

    local output = run("import this is not an export string")
    assert(output:find("not a Field Journal export", 1, true), "expected a clear rejection, got:\n" .. output)
    assert(output:find("rebuilt the bestiary index", 1, true) == nil,
        "a refused import must not run the index rebuild, got:\n" .. output)
    assert(charData.entries["quest:1"].body == "one", "a refused import must change nothing")
end

local function test_fj_export_and_import_are_safe_with_no_database()
    local fj = load()
    fj.db = nil
    fj.charData = nil
    local exportOutput = run("export")
    assert(exportOutput:find("not available", 1, true),
        "expected the degraded explanation, got:\n" .. exportOutput)
    local importOutput = run("import anything")
    assert(importOutput:find("not available", 1, true),
        "expected the degraded explanation, got:\n" .. importOutput)
end

return {
    test_fj_backup_lists_the_ring = test_fj_backup_lists_the_ring,
    test_fj_backup_now_takes_a_snapshot = test_fj_backup_now_takes_a_snapshot,
    test_fj_repair_restores_from_the_ring_and_rebuilds_the_bestiary_index = test_fj_repair_restores_from_the_ring_and_rebuilds_the_bestiary_index,
    test_fj_repair_is_safe_with_no_database = test_fj_repair_is_safe_with_no_database,
    test_fj_status_reports_the_backup_ring = test_fj_status_reports_the_backup_ring,
    test_fj_export_opens_a_copy_box_with_a_printable_string = test_fj_export_opens_a_copy_box_with_a_printable_string,
    test_fj_export_refuses_an_empty_journal_without_opening_a_dialog = test_fj_export_refuses_an_empty_journal_without_opening_a_dialog,
    test_fj_import_with_a_string_merges_and_rebuilds_the_bestiary_index = test_fj_import_with_a_string_merges_and_rebuilds_the_bestiary_index,
    test_fj_import_with_no_argument_opens_the_paste_box = test_fj_import_with_no_argument_opens_the_paste_box,
    test_fj_import_rejects_junk_without_changing_anything = test_fj_import_rejects_junk_without_changing_anything,
    test_fj_export_and_import_are_safe_with_no_database = test_fj_export_and_import_are_safe_with_no_database,
}
