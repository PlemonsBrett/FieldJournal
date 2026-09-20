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

-- Review finding 1 (Critical): entries is excluded from the MONOTONIC list so
-- normal past:<id> placeholder churn doesn't freeze the ring, but a wipe of
-- entries to exactly zero must never be waved through just because the other
-- four collections are healthy and the five-collection total is still well
-- above zero.
local function test_capture_refuses_when_entries_alone_is_wiped_to_zero()
    local fj = load()
    local charData = freshChar()
    for index = 1, 300 do
        charData.entries["quest:" .. index] = {key = "quest:" .. index, body = "body " .. index, order = index}
    end
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 1}
    charData.diaryEvents[1] = {key = "diary1", seenAt = 1}
    charData.craftEvents[1] = {key = "craft1", seenAt = 1}
    charData.bestiary["wolf"] = {name = "Wolf", kills = 1, order = 1}
    fj.Backup.capture(charData)

    -- entries wiped to zero; the other four collections are untouched.
    charData.entries = {}

    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(charData)
    release()
    assert(taken == false,
        "wiping entries to zero must never rotate the ring, even with the other four collections healthy")
    assert(reason == "emptied", "expected reason 'emptied', got " .. tostring(reason))
    assert(#charData.backups == 1, "the good snapshot must still be in the ring")
    assert(charData.backups[1].counts.entries == 300, "the good snapshot must be untouched")
    assert(table.concat(lines, "\n"):find("/fj repair", 1, true),
        "the warning must point the player at /fj repair, got:\n" .. table.concat(lines, "\n"))
end

-- Review finding 2 (Important): shouldCapture must not throw when the live
-- data is malformed (the shape a hand-edited SavedVariables file produces --
-- a collection field present but not a table). Migrations.counts() calls
-- pairs(charData.entries or {}), and pairs() raises on ANY non-table
-- argument, so an entries field holding a plain string reproduces exactly
-- that crash and exercises the pcall wrapped around shouldCapture's body.
local function test_capture_is_safe_when_a_live_collection_field_is_malformed()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 1}
    fj.Backup.capture(charData)

    charData.entries = "corrupted"

    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(charData)
    release()
    assert(taken == false, "capture must not throw when a live collection field is malformed")
    assert(reason == "unavailable", "expected reason 'unavailable', got " .. tostring(reason))
    assert(#charData.backups == 1, "the ring must be untouched")
    assert(#lines == 0, "an unavailable verdict must not print anything, got " .. #lines .. " lines")
end

-- Review finding 2 (Important), the describe() half: a snapshot's own stored
-- data can be just as malformed as live data (a partially written entry), and
-- snapshotCounts falls back to Migrations.counts(snapshot.data) in that case,
-- which raises on the same shape (pairs() on a non-table entries field).
-- describe() must degrade, not throw.
local function test_describe_is_safe_when_a_snapshot_is_malformed()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 1}
    fj.Backup.capture(charData)

    charData.backups[1].counts = nil
    charData.backups[1].data.entries = "corrupted"

    local ok, lines = pcall(fj.Backup.describe, charData)
    assert(ok, "describe must not throw when a snapshot's stored data is malformed")
    assert(type(lines) == "table" and #lines >= 1, "describe must still return chat-ready lines")
end

-- Review finding 3 (Important): shouldCapture must not stop at ring[1]. If the
-- newest snapshot is unreadable but an older one is good, a shrink must still
-- be caught against that older, readable baseline.
local function test_capture_falls_back_to_the_first_readable_snapshot_when_the_newest_is_garbage()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 1}
    charData.encounters[2] = {guid = "g2", name = "Bear", seenAt = 2}
    fj.Backup.capture(charData)

    charData.encounters[3] = {guid = "g3", name = "Boar", seenAt = 3}
    fj.Backup.capture(charData)
    assert(#charData.backups == 2, "setup: two snapshots should exist before corrupting the newest")

    -- Corrupt the newest snapshot (ring[1]) in place -- the signature of a
    -- hand-edited or partially-written saved-variables entry.
    charData.backups[1] = {at = 999, counts = "not a table", data = "also not a table"}

    -- Shrink relative to ring[2]'s good baseline (encounters == 2): drop to 0.
    table.remove(charData.encounters)
    table.remove(charData.encounters)

    local lines, release = capturePrint()
    local taken, reason = fj.Backup.capture(charData)
    release()
    assert(taken == false, "a shrunk journal must still be caught even when the newest snapshot is unreadable")
    assert(reason == "shrunk", "expected reason 'shrunk' (checked against ring[2]), got " .. tostring(reason))
    assert(#charData.backups == 2, "the ring must be untouched -- neither slot should have rotated")
    assert(table.concat(lines, "\n"):find("/fj repair", 1, true),
        "the warning must point the player at /fj repair, got:\n" .. table.concat(lines, "\n"))
end

local function test_repair_restores_a_collection_lost_since_the_snapshot()
    local fj = load()
    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", kind = "quest", questID = 1, body = "one", order = 1}
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5, order = 2}
    charData.bestiary["creature:1"] = {key = "creature:1", name = "Wolf", kills = 3,
        places = {Glade = {count = 2}}, drops = {}, order = 3}
    fj.Backup.capture(charData)

    -- The saved file came back with two collections emptied.
    charData.encounters = {}
    charData.bestiary = {}

    local lines, release = capturePrint()
    local restored, reason = fj.Backup.repair(charData)
    release()

    assert(restored == true, "repair must report that it restored something")
    assert(reason == "restored", "expected reason 'restored', got " .. tostring(reason))
    assert(#charData.encounters == 1, "the lost encounter must come back")
    assert(charData.bestiary["creature:1"].kills == 3, "the lost bestiary record must come back")
    assert(charData.entries["quest:1"].body == "one", "surviving entries must be untouched")
    local joined = table.concat(lines, "\n")
    assert(joined:find("1 encounters", 1, true), "the report must name what it restored:\n" .. joined)
    assert(joined:find("1 bestiary species", 1, true), "the report must name what it restored:\n" .. joined)
end

local function test_repair_is_idempotent()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5, order = 1}
    charData.diaryEvents[1] = {key = "diary:1", seenAt = 7, order = 7}
    charData.craftEvents[1] = {key = "craft:1", seenAt = 8, order = 8}
    fj.Backup.capture(charData)
    charData.encounters = {}

    quietly(fj.Backup.repair, charData)
    quietly(fj.Backup.repair, charData)
    quietly(fj.Backup.repair, charData)

    assert(#charData.encounters == 1,
        "repeated repairs must not duplicate encounters, got " .. #charData.encounters)
    assert(#charData.diaryEvents == 1,
        "repeated repairs must not duplicate diary events, got " .. #charData.diaryEvents)
    assert(#charData.craftEvents == 1,
        "repeated repairs must not duplicate craft events, got " .. #charData.craftEvents)
end

local function test_repair_reports_no_repair_needed_when_nothing_is_missing()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5, order = 1}
    fj.Backup.capture(charData)

    local lines, release = capturePrint()
    local restored, reason = fj.Backup.repair(charData)
    release()

    assert(restored == false, "repair must report that nothing needed restoring")
    assert(reason == "nothing", "expected reason 'nothing', got " .. tostring(reason))
    assert(table.concat(lines, "\n"):find("no repair needed", 1, true),
        "expected the no-repair-needed line, got:\n" .. table.concat(lines, "\n"))
    assert(#charData.encounters == 1, "repair must not change a healthy journal")
end

-- Migrations.mergeIntoCharacter inserts source record tables by reference. If
-- the snapshot were merged directly, a restored record and the backup's own
-- record would be the same Lua table forever after.
local function test_repair_does_not_alias_live_records_to_the_snapshot()
    local fj = load()
    local charData = freshChar()
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5, order = 1}
    fj.Backup.capture(charData)
    charData.encounters = {}

    quietly(fj.Backup.repair, charData)

    local live = charData.encounters[1]
    local stored = charData.backups[1].data.encounters[1]
    assert(live ~= nil and stored ~= nil, "the encounter must exist on both sides")
    assert(live.guid == stored.guid, "the same encounter must have been restored")
    assert(live ~= stored, "a restored record must be a copy, never the snapshot's own table")
    live.name = "edited later"
    assert(stored.name == "Wolf", "editing a restored record must never rewrite the backup")
end

local function test_repair_drops_placeholders_the_player_has_already_replaced()
    local fj = load()
    local charData = freshChar()
    charData.entries["past:101"] = {key = "past:101", kind = "pastQuest", questID = 101,
        body = "This quest was completed before Field Journal was installed."}
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5, order = 1}
    fj.Backup.capture(charData)

    -- The player captures the real quest text, which deletes the placeholder
    -- exactly as Data/QuestLog.lua's addEntry does, and then loses encounters.
    charData.entries["past:101"] = nil
    charData.entries["quest:101"] = {key = "quest:101", kind = "quest", questID = 101,
        body = "the words I actually heard", order = 9}
    charData.encounters = {}

    quietly(fj.Backup.repair, charData)

    assert(charData.entries["quest:101"] ~= nil, "the real quest entry must survive the repair")
    assert(charData.entries["past:101"] == nil,
        "a placeholder the player has already replaced must not be resurrected by a restore")
    assert(#charData.encounters == 1, "the genuinely lost encounter must still be restored")
end

local function test_repair_raises_next_order_above_every_restored_record()
    local fj = load()
    local charData = freshChar()
    charData.nextOrder = 40
    charData.encounters[1] = {guid = "g1", name = "Wolf", seenAt = 5, order = 40}
    fj.Backup.capture(charData)

    charData.encounters = {}
    charData.nextOrder = 0

    quietly(fj.Backup.repair, charData)
    assert(charData.nextOrder == 40,
        "nextOrder must rise above every restored record so new ones cannot collide, got "
            .. tostring(charData.nextOrder))
end

local function test_repair_is_safe_with_an_empty_ring_and_a_missing_database()
    local fj = load()

    local lines, release = capturePrint()
    local restored, reason = fj.Backup.repair(freshChar())
    release()
    assert(restored == false, "repair must refuse when the ring is empty")
    assert(reason == "empty", "expected reason 'empty', got " .. tostring(reason))
    assert(#lines == 1, "exactly one chat line must explain an empty ring, got " .. #lines)

    lines, release = capturePrint()
    local ok, why = fj.Backup.repair(nil)
    release()
    assert(ok == false, "repair must refuse when there is no character data")
    assert(why == "unavailable", "expected reason 'unavailable', got " .. tostring(why))
    assert(#lines == 1, "exactly one chat line must explain a missing database, got " .. #lines)
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
    test_repair_restores_a_collection_lost_since_the_snapshot = test_repair_restores_a_collection_lost_since_the_snapshot,
    test_repair_is_idempotent = test_repair_is_idempotent,
    test_repair_reports_no_repair_needed_when_nothing_is_missing = test_repair_reports_no_repair_needed_when_nothing_is_missing,
    test_repair_does_not_alias_live_records_to_the_snapshot = test_repair_does_not_alias_live_records_to_the_snapshot,
    test_repair_drops_placeholders_the_player_has_already_replaced = test_repair_drops_placeholders_the_player_has_already_replaced,
    test_repair_raises_next_order_above_every_restored_record = test_repair_raises_next_order_above_every_restored_record,
    test_repair_is_safe_with_an_empty_ring_and_a_missing_database = test_repair_is_safe_with_an_empty_ring_and_a_missing_database,
    test_capture_refuses_when_entries_alone_is_wiped_to_zero = test_capture_refuses_when_entries_alone_is_wiped_to_zero,
    test_capture_is_safe_when_a_live_collection_field_is_malformed = test_capture_is_safe_when_a_live_collection_field_is_malformed,
    test_describe_is_safe_when_a_snapshot_is_malformed = test_describe_is_safe_when_a_snapshot_is_malformed,
    test_capture_falls_back_to_the_first_readable_snapshot_when_the_newest_is_garbage = test_capture_falls_back_to_the_first_readable_snapshot_when_the_newest_is_garbage,
}
