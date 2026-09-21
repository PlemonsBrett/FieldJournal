local env = dofile("tests/wow_env.lua")

-- Core/Export.lua reads snapshotData, dropSupersededPlaceholders, deepCopy,
-- counts, countText, mergeIntoCharacter and highestOrder off the shared
-- namespace at call time, and both libraries through LibStub, so all four
-- modules and all three library files are loaded here. The libraries are the
-- real vendored ones: this spec exercises the actual compression and
-- serialisation, never a stand-in for them.
local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
    "Core/Backup.lua",
    "Core/Export.lua",
}

local function load()
    env.install()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")
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

-- One record in every collection, so a round trip that silently drops one is
-- always visible. past:11 is a recovered-description placeholder, which the
-- import tests use to prove it is not resurrected.
local function populated()
    local charData = freshChar()
    charData.nextOrder = 7
    charData.entries["quest:10"] = {key = "quest:10", kind = "quest", questID = 10,
        title = "The Lost Satchel", body = "I found it.", order = 3}
    charData.entries["past:11"] = {key = "past:11", kind = "pastQuest", questID = 11,
        title = "An Older Errand", body = "Recovered description", order = 1}
    charData.encounters[1] = {guid = "Creature-0-0-0-0-99-0001", name = "Wolf",
        place = "Glade", zone = "Glade", seenAt = 5, order = 4}
    charData.diaryEvents[1] = {key = "diary:1", seenAt = 6, order = 5, text = "Learned Frostbolt"}
    charData.craftEvents[1] = {key = "craft:1", seenAt = 7, order = 6, text = "Made a Linen Bandage"}
    charData.bestiary["creature:99"] = {key = "creature:99", name = "Wolf", kills = 1,
        places = {Glade = {count = 1}}, drops = {}, order = 7}
    charData.objectiveState["10:1"] = "done"
    charData.questBookmarks[10] = true
    return charData
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

-- Runs fn with print captured, asserts it did not throw, and returns the chat
-- lines plus fn's first two return values.
local function quietly(fn, ...)
    local lines, release = capturePrint()
    local results = {pcall(fn, ...)}
    release()
    assert(results[1], "the export module threw: " .. tostring(results[2]))
    return lines, results[2], results[3]
end

local function test_payload_carries_the_envelope_and_excludes_the_backup_ring()
    local fj = load()
    local charData = populated()
    charData.backups[1] = {at = 1, counts = {}, data = {entries = {}}}

    _G.time = function() return 1700000000 end
    local payload = fj.Export.buildPayload(charData)
    _G.time = os.time

    assert(type(payload) == "table", "buildPayload must return a table")
    assert(payload.addon == "FieldJournal", "the envelope must carry the addon tag")
    assert(payload.payloadVersion == 1, "the envelope must carry the payload format version")
    assert(payload.schemaVersion == 2, "the envelope must carry the journal schema version")
    assert(payload.character == "Ashenvale:Wren", "the envelope must record who exported it")
    assert(payload.at == 1700000000, "the envelope must record when it was exported")
    assert(payload.counts.entries == 2, "the envelope must carry the record counts")

    assert(payload.data.backups == nil,
        "an export must never carry the backup ring -- that multiplies the string for no benefit")
    assert(payload.data.entries["quest:10"].body == "I found it.", "the export must carry the entries")
    assert(payload.data.encounters[1].guid == "Creature-0-0-0-0-99-0001", "the export must carry encounters")
    assert(payload.data.diaryEvents[1].key == "diary:1", "the export must carry diary events")
    assert(payload.data.craftEvents[1].key == "craft:1", "the export must carry craft events")
    assert(payload.data.bestiary["creature:99"].kills == 1, "the export must carry the bestiary")
    assert(payload.data.objectiveState["10:1"] == "done", "the export must carry objectiveState")
    assert(payload.data.questBookmarks[10] == true, "the export must carry questBookmarks")
    assert(payload.data.nextOrder == 7, "the export must carry nextOrder")

    assert(payload.data.entries ~= charData.entries, "the export must not alias live collections")
    charData.entries["quest:10"].body = "changed later"
    assert(payload.data.entries["quest:10"].body == "I found it.",
        "mutating live data must never reach an already-built payload")
end

local function test_encode_refuses_an_empty_journal()
    local fj = load()
    local text, reason = fj.Export.encode(freshChar())
    assert(text == nil, "an empty journal must not produce an export string")
    assert(reason == "empty", "expected reason 'empty', got " .. tostring(reason))
end

local function test_export_string_is_printable_and_round_trips()
    local fj = load()
    local text, reason = fj.Export.encode(populated())
    assert(type(text) == "string" and #text > 0, "encode must return a non-empty string")
    assert(reason == "exported", "expected reason 'exported', got " .. tostring(reason))
    assert(not text:find("[^%w%(%)]"),
        "every byte must be one of EncodeForPrint's 64 printable characters")

    local payload, decodeReason = fj.Export.decode(text)
    assert(type(payload) == "table", "decode must return the payload, got " .. tostring(decodeReason))
    assert(fj.Export.validate(payload), "a freshly produced export must validate")
    assert(payload.data.entries["quest:10"].title == "The Lost Satchel", "the entry must survive the round trip")
    assert(payload.data.encounters[1].guid == "Creature-0-0-0-0-99-0001", "the encounter must survive")
    assert(payload.data.bestiary["creature:99"].places.Glade.count == 1, "a nested table must survive")
    assert(payload.data.questBookmarks[10] == true, "a numeric table key must survive")
    assert(payload.data.nextOrder == 7, "a plain number must survive")
end

local function test_decode_rejects_junk_at_every_stage()
    local fj = load()
    local _, notString = fj.Export.decode(nil)
    assert(notString == "notstring", "a non-string must be refused, got " .. tostring(notString))
    local _, blank = fj.Export.decode("   ")
    assert(blank == "blank", "a blank string must be refused, got " .. tostring(blank))
    local _, badChars = fj.Export.decode("not a valid export!!!")
    assert(badChars == "decode", "unencodable characters must be refused, got " .. tostring(badChars))
    local _, badStream = fj.Export.decode("aaaaaaaaaaaaaaaa")
    assert(badStream == "decompress" or badStream == "deserialize",
        "a printable but meaningless string must be refused, got " .. tostring(badStream))
end

local function test_validate_rejects_a_foreign_or_incompatible_payload()
    local fj = load()
    local payload = fj.Export.buildPayload(populated())

    local ok, reason = fj.Export.validate({some = "other addon"})
    assert(not ok and reason == "foreign", "a foreign table must be refused, got " .. tostring(reason))

    payload.payloadVersion = 99
    ok, reason = fj.Export.validate(payload)
    assert(not ok and reason == "payloadversion", "a future format must be refused, got " .. tostring(reason))
    payload.payloadVersion = 1

    payload.schemaVersion = 1
    ok, reason = fj.Export.validate(payload)
    assert(not ok and reason == "schema", "a foreign schema must be refused, got " .. tostring(reason))
    payload.schemaVersion = 2

    local goodData = payload.data
    payload.data = "not a table"
    ok, reason = fj.Export.validate(payload)
    assert(not ok and reason == "shape", "a non-table data field must be refused, got " .. tostring(reason))

    payload.data = {}
    ok, reason = fj.Export.validate(payload)
    assert(not ok and reason == "shape", "a payload with no collections must be refused, got " .. tostring(reason))

    payload.data = {entries = "not a table"}
    ok, reason = fj.Export.validate(payload)
    assert(not ok and reason == "shape", "a malformed collection must be refused, got " .. tostring(reason))

    payload.data = goodData
    assert(fj.Export.validate(payload), "the untouched payload must still validate")
end

local function test_describe_payload_names_the_character_the_date_and_the_counts()
    local fj = load()
    _G.time = function() return 1700000000 end
    local payload = fj.Export.buildPayload(populated())
    _G.time = os.time
    local described = fj.Export.describePayload(payload)
    assert(described:find("Ashenvale:Wren", 1, true), "the description must name the character: " .. described)
    assert(described:find("2 entries, 1 encounters", 1, true), "the description must carry the counts: " .. described)
    assert(described:find(date("%Y-%m-%d %H:%M", 1700000000), 1, true),
        "the description must carry the export date: " .. described)
    assert(fj.Export.describePayload("not a payload") == "an unreadable export",
        "describePayload must degrade rather than throw")
end

local function test_export_is_safe_without_a_database()
    local fj = load()
    local text, reason = fj.Export.encode(nil)
    assert(text == nil and reason == "unavailable",
        "encode must degrade when there is no character data, got " .. tostring(reason))
    assert(fj.Export.message("unavailable"):find("not available", 1, true),
        "the unavailable message must say so plainly")
end

-- Permanent ownership guard, in the same spirit as
-- tests/fj_no_global_reassignment_spec.lua: the serialisation/compression
-- pipeline belongs to Core/Export.lua and to no other shipped file. Reading the
-- real .toc means a file added by a later plan is checked automatically.
local PIPELINE = {
    "Serialize", "Deserialize",
    "CompressDeflate", "DecompressDeflate",
    "EncodeForPrint", "DecodeForPrint",
}

local function test_only_core_export_lua_touches_the_serialisation_pipeline()
    for line in io.lines("FieldJournal.toc") do
        local path = line:match("^%s*(.-)%s*$")
        if path ~= "" and not path:match("^##") and not path:match("^Libs/")
            and path ~= "Core/Export.lua" then
            local file = assert(io.open(path, "r"), "could not open " .. path)
            local source = file:read("*a")
            file:close()
            for _, name in ipairs(PIPELINE) do
                assert(not source:find(name .. "%s*%("),
                    path .. " calls " .. name
                        .. "() -- the export/import pipeline is owned exclusively by Core/Export.lua;"
                        .. " go through FieldJournal.Export instead")
            end
        end
    end
end

return {
    test_payload_carries_the_envelope_and_excludes_the_backup_ring = test_payload_carries_the_envelope_and_excludes_the_backup_ring,
    test_encode_refuses_an_empty_journal = test_encode_refuses_an_empty_journal,
    test_export_string_is_printable_and_round_trips = test_export_string_is_printable_and_round_trips,
    test_decode_rejects_junk_at_every_stage = test_decode_rejects_junk_at_every_stage,
    test_validate_rejects_a_foreign_or_incompatible_payload = test_validate_rejects_a_foreign_or_incompatible_payload,
    test_describe_payload_names_the_character_the_date_and_the_counts = test_describe_payload_names_the_character_the_date_and_the_counts,
    test_export_is_safe_without_a_database = test_export_is_safe_without_a_database,
    test_only_core_export_lua_touches_the_serialisation_pipeline = test_only_core_export_lua_touches_the_serialisation_pipeline,
}
