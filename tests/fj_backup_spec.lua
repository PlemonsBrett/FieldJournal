local env = dofile("tests/wow_env.lua")

-- Core/Bootstrap.lua is loaded because Task 4 drives its OnEvent dispatcher
-- from this same spec; Database and Migrations are loaded because Core/Backup.lua
-- reads deepCopy, counts, countText, mergeIntoCharacter and highestOrder off
-- the shared namespace at call time.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
    "Core/Backup.lua",
}

local function load()
    env.install()
    _G.GetRealmName = function() return "Ashenvale" end
    _G.UnitName = function() return "Wren" end
    _G.FieldJournalCharacterDB = nil
    local fj = env.loadModules(MODULES)
    -- initializeCharacter's tail calls into modules this spec does not load.
    fj.Diary.resetGroupSnapshot = function() end
    fj.QuestLog.syncActiveQuestLog = function() end
    fj.Bestiary.observeUnit = function() end
    fj.UI.createWindow = function() fj.UI.window = true end
    fj.UI.RefreshIfShown = function() end
    return fj
end

-- Exactly the shape Core/Database.lua's defaults.char produces.
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

local function quietly(fn, ...)
    local lines, release = capturePrint()
    local ok, err = pcall(fn, ...)
    release()
    assert(ok, "the backup module threw: " .. tostring(err))
    return lines
end

local function test_snapshot_data_is_a_deep_copy_without_the_backups_field()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", body = "one", order = 1}
    charData.backups[1] = {at = 1, counts = {}, data = {}}

    local data = fj.Backup.snapshotData(charData)
    assert(data.backups == nil,
        "a snapshot must never contain the ring itself -- that nests every snapshot in the next")
    assert(data.entries["quest:1"].body == "one", "the snapshot must carry the entries")
    assert(data.nextOrder == charData.nextOrder, "the snapshot must carry nextOrder")
    assert(data.schemaVersion == charData.schemaVersion, "the snapshot must carry schemaVersion")
    assert(data.objectiveState ~= nil, "the snapshot must carry objectiveState")
    assert(data.questBookmarks ~= nil, "the snapshot must carry questBookmarks")

    assert(data.entries ~= charData.entries, "the snapshot must not alias the live collection")
    assert(data.entries["quest:1"] ~= charData.entries["quest:1"],
        "the snapshot must deep-copy each record, not alias it")
    charData.entries["quest:1"].body = "changed later"
    assert(data.entries["quest:1"].body == "one",
        "mutating live data must never reach an already-taken snapshot")
end

local function test_first_capture_prepends_a_snapshot_with_time_counts_and_data()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", body = "one", order = 1}
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5}

    _G.time = function() return 1000 end
    local taken, reason = fj.Backup.capture(charData)
    _G.time = os.time

    assert(taken == true, "the very first snapshot must always be taken, reason " .. tostring(reason))
    assert(reason == "first", "expected reason 'first', got " .. tostring(reason))
    assert(#charData.backups == 1, "the ring must hold exactly one snapshot")
    local snapshot = charData.backups[1]
    assert(snapshot.at == 1000, "the snapshot must record when it was taken")
    assert(snapshot.counts.entries == 1, "the snapshot must record its own entry count")
    assert(snapshot.counts.encounters == 1, "the snapshot must record its own encounter count")
    assert(snapshot.data.entries["quest:1"].body == "one", "the snapshot must carry the data")
end

local function test_capture_skips_an_identical_snapshot()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", body = "one", order = 1}
    fj.Backup.capture(charData)

    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(charData)
    release()
    assert(taken == false, "an unchanged journal must not be snapshotted again")
    assert(reason == "identical", "expected reason 'identical', got " .. tostring(reason))
    assert(#charData.backups == 1, "the ring must still hold exactly one snapshot")
    assert(#lines == 0, "a routine skip must not say anything in chat, got " .. #lines .. " lines")
end

local function test_capture_records_a_snapshot_when_counts_change()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", body = "one", order = 1}
    fj.Backup.capture(charData)

    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5}
    local taken, reason = fj.Backup.capture(charData)
    assert(taken == true, "a changed journal must be snapshotted")
    assert(reason == "changed", "expected reason 'changed', got " .. tostring(reason))
    assert(#charData.backups == 2, "the ring must now hold two snapshots")
    assert(charData.backups[1].counts.encounters == 1, "the newest snapshot must be first")
    assert(charData.backups[2].counts.encounters == 0, "the older snapshot must be pushed down")
end

local function test_the_ring_never_grows_past_the_snapshot_limit()
    local fj = load()
    local charData = freshChar()
    for index = 1, 12 do
        charData.encounters[index] = {guid = "g" .. index, name = "Wolf", seenAt = index}
        local taken, reason = fj.Backup.capture(charData)
        assert(taken == true, "snapshot " .. index .. " should have been taken, got " .. tostring(reason))
    end
    assert(#charData.backups == fj.Backup.SNAPSHOT_LIMIT,
        "the ring must stay capped at " .. fj.Backup.SNAPSHOT_LIMIT .. ", got " .. #charData.backups)
    assert(charData.backups[1].counts.encounters == 12, "the newest snapshot must be first")
    assert(charData.backups[fj.Backup.SNAPSHOT_LIMIT].counts.encounters == 8,
        "the oldest surviving snapshot must be the fifth most recent, got "
            .. charData.backups[fj.Backup.SNAPSHOT_LIMIT].counts.encounters)
end

-- The whole point of the guard: a damaged session must never be allowed to
-- rotate five good snapshots out of the ring one login at a time.
local function test_capture_refuses_when_a_monotonic_collection_shrank()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5}
    charData.encounters[2] = {guid = "g2", name = "Bear", seenAt = 6}
    fj.Backup.capture(charData)

    table.remove(charData.encounters)

    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(charData)
    release()
    assert(taken == false, "a shrunken journal must never rotate the ring")
    assert(reason == "shrunk", "expected reason 'shrunk', got " .. tostring(reason))
    assert(#charData.backups == 1, "the good snapshot must still be in the ring")
    assert(charData.backups[1].counts.encounters == 2, "the good snapshot must be untouched")
    assert(table.concat(lines, "\n"):find("/fj repair", 1, true),
        "the warning must point the player at /fj repair, got:\n" .. table.concat(lines, "\n"))
end

local function test_capture_refuses_when_the_journal_is_empty_but_the_ring_is_not()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", body = "one", order = 1}
    fj.Backup.capture(charData)

    -- The signature of the SavedVariables file failing to load: everything gone.
    charData.entries["quest:1"] = nil

    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(charData)
    release()
    assert(taken == false, "a wholesale wipe must never rotate the ring")
    assert(reason == "emptied", "expected reason 'emptied', got " .. tostring(reason))
    assert(#charData.backups == 1, "the good snapshot must still be in the ring")
    assert(table.concat(lines, "\n"):find("/fj repair", 1, true),
        "the warning must point the player at /fj repair, got:\n" .. table.concat(lines, "\n"))
end

-- Data/QuestLog.lua's addEntry deletes entries["past:<id>"] when the player
-- captures a real quest's text. That is normal play, so the entry count
-- dropping must NOT be treated as data loss and must not freeze the ring.
local function test_capture_tolerates_a_superseded_placeholder_entry_disappearing()
    local fj = load()
    local charData = freshChar()
    charData.entries["past:101"] = {key = "past:101", kind = "pastQuest", questID = 101, body = "old one"}
    charData.entries["past:102"] = {key = "past:102", kind = "pastQuest", questID = 102, body = "old two"}
    charData.entries["quest:100"] = {key = "quest:100", kind = "quest", questID = 100, body = "kept"}
    fj.Backup.capture(charData)

    charData.entries["past:101"] = nil
    charData.entries["past:102"] = nil
    charData.entries["quest:101"] = {key = "quest:101", kind = "quest", questID = 101, body = "new"}

    local taken, reason = fj.Backup.capture(charData)
    assert(taken == true, "a superseded placeholder must not block the snapshot, got " .. tostring(reason))
    assert(reason == "changed", "expected reason 'changed', got " .. tostring(reason))
    assert(#charData.backups == 2, "the ring must have rotated normally")
end

local function test_capture_is_safe_without_a_database()
    local fj = load()
    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(nil)
    release()
    assert(taken == false, "capture must refuse when there is no character data")
    assert(reason == "unavailable", "expected reason 'unavailable', got " .. tostring(reason))
    assert(#lines == 0,
        "a degraded database already prints its own error; capture must not pile on, got " .. #lines)
end

return {
    test_snapshot_data_is_a_deep_copy_without_the_backups_field = test_snapshot_data_is_a_deep_copy_without_the_backups_field,
    test_first_capture_prepends_a_snapshot_with_time_counts_and_data = test_first_capture_prepends_a_snapshot_with_time_counts_and_data,
    test_capture_skips_an_identical_snapshot = test_capture_skips_an_identical_snapshot,
    test_capture_records_a_snapshot_when_counts_change = test_capture_records_a_snapshot_when_counts_change,
    test_the_ring_never_grows_past_the_snapshot_limit = test_the_ring_never_grows_past_the_snapshot_limit,
    test_capture_refuses_when_a_monotonic_collection_shrank = test_capture_refuses_when_a_monotonic_collection_shrank,
    test_capture_refuses_when_the_journal_is_empty_but_the_ring_is_not = test_capture_refuses_when_the_journal_is_empty_but_the_ring_is_not,
    test_capture_tolerates_a_superseded_placeholder_entry_disappearing = test_capture_tolerates_a_superseded_placeholder_entry_disappearing,
    test_capture_is_safe_without_a_database = test_capture_is_safe_without_a_database,
}
