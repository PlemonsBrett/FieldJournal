local env = dofile("tests/wow_env.lua")

-- The whole slash-command surface, driven through the real handler the addon
-- registers as SlashCmdList.FIELDJOURNAL. UI/ is not loaded; the two UI calls
-- the handler makes are stubbed below.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
    "Core/Backup.lua",
    "Core/SlashCommands.lua",
}

local function load()
    env.install()
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

return {
    test_fj_backup_lists_the_ring = test_fj_backup_lists_the_ring,
    test_fj_backup_now_takes_a_snapshot = test_fj_backup_now_takes_a_snapshot,
    test_fj_repair_restores_from_the_ring_and_rebuilds_the_bestiary_index = test_fj_repair_restores_from_the_ring_and_rebuilds_the_bestiary_index,
    test_fj_repair_is_safe_with_no_database = test_fj_repair_is_safe_with_no_database,
    test_fj_status_reports_the_backup_ring = test_fj_status_reports_the_backup_ring,
}
