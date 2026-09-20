local env = dofile("tests/wow_env.lua")

local MODULES = {
    "Core/Bootstrap.lua",
    "Core/Database.lua",
    "Core/Migrations.lua",
}

local KEY = "Ashenvale:Wren"

local function load()
    env.install()
    _G.GetRealmName = function() return "Ashenvale" end
    _G.UnitName = function() return "Wren" end
    return env.loadModules(MODULES)
end

-- Exactly the shape Core/Database.lua's defaults.char produces.
local function freshChar()
    return {
        schemaVersion = 0, legacyMigrated = false, nextOrder = 0,
        entries = {}, encounters = {}, diaryEvents = {}, craftEvents = {},
        bestiary = {}, objectiveState = {}, questBookmarks = {}, backups = {},
    }
end

local function legacyAccount()
    return {
        version = 1,
        nextOrder = 41,
        characters = {[KEY] = {["quest:1"] = {key = "quest:1", body = "one", order = 12}}},
        encounters = {[KEY] = {{guid = "g1", name = "Wolf", seenAt = 5}}},
        diaryEvents = {[KEY] = {{key = "diary:1", seenAt = 7, order = 7}}},
        craftEvents = {[KEY] = {{key = "craft:1", seenAt = 8, order = 8}}},
        bestiary = {[KEY] = {["creature:1"] = {key = "creature:1", name = "Wolf", kills = 3,
            places = {Glade = {count = 2}}, drops = {["5"] = {name = "Pelt", count = 1}}, order = 9}}},
        objectiveStates = {[KEY] = {[101] = "1/5"}},
        questBookmarks = {[KEY] = {[101] = true}},
        bestiaryMigrated = {},
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
    assert(ok, "migration threw: " .. tostring(err))
    return lines
end

local function test_migrates_the_old_account_shape_for_the_current_character()
    local fj = load()
    local charData = freshChar()
    quietly(fj.Migrations.run, charData, {account = legacyAccount(), recovery = {}})

    assert(charData.entries["quest:1"].body == "one", "the legacy entry was not migrated")
    assert(#charData.encounters == 1, "the legacy encounter was not migrated")
    assert(#charData.diaryEvents == 1, "the legacy diary event was not migrated")
    assert(#charData.craftEvents == 1, "the legacy craft event was not migrated")
    assert(charData.bestiary["creature:1"].kills == 3, "the legacy bestiary record was not migrated")
    assert(charData.objectiveState[101] == "1/5", "objective state was dropped by the migration")
    assert(charData.questBookmarks[101] == true, "quest bookmarks were dropped by the migration")
    assert(charData.legacyMigrated == true, "the one-time guard was not set")
    assert(charData.schemaVersion == 2, "schemaVersion was not written, got "
        .. tostring(charData.schemaVersion))
end

local function test_is_idempotent_and_runs_only_once()
    local fj = load()
    local charData = freshChar()
    local legacy = {account = legacyAccount(), recovery = {}}
    quietly(fj.Migrations.run, charData, legacy)
    quietly(fj.Migrations.run, charData, legacy)
    quietly(fj.Migrations.run, charData, legacy)
    assert(#charData.encounters == 1, "re-running the migration duplicated encounters")
    assert(#charData.diaryEvents == 1, "re-running the migration duplicated diary events")
    assert(#charData.craftEvents == 1, "re-running the migration duplicated craft events")

    -- Even with the guard forced off, the identity merge must stay idempotent.
    charData.legacyMigrated = false
    quietly(fj.Migrations.run, charData, legacy)
    assert(#charData.encounters == 1, "the identity merge is not idempotent for encounters")
    assert(charData.bestiary["creature:1"].kills == 3, "kills drifted on a repeat merge")
end

local function test_merges_the_per_character_mirror_and_recovery_snapshots()
    local fj = load()
    local charData = freshChar()
    local mirror = {
        key = KEY,
        entries = {["quest:2"] = {key = "quest:2", body = "two", order = 20}},
        encounters = {{guid = "g2", name = "Bear", seenAt = 21}},
        diaryEvents = {}, craftEvents = {},
        bestiary = {["creature:1"] = {name = "Unidentified creature #1", kills = 9,
            places = {Glade = {count = 30}}, drops = {["5"] = {name = "Pelt", count = 4}}, order = 2}},
    }
    local snapshot = legacyAccount()
    snapshot.nextOrder = 77
    snapshot.characters[KEY] = {["quest:3"] = {key = "quest:3", body = "three", order = 30}}

    quietly(fj.Migrations.run, charData, {
        account = legacyAccount(),
        character = mirror,
        recovery = {{name = "FieldJournalRecoveryDB2", data = snapshot}},
    })

    assert(charData.entries["quest:1"].body == "one", "account entry missing")
    assert(charData.entries["quest:2"].body == "two", "mirror entry missing")
    assert(charData.entries["quest:3"].body == "three", "recovery entry missing")
    assert(#charData.encounters == 2, "expected two distinct encounters, got " .. #charData.encounters)
    local beast = charData.bestiary["creature:1"]
    assert(beast.kills == 9, "kills must take the maximum across every source")
    assert(beast.name == "Wolf", "a real name must never lose to an Unidentified placeholder")
    assert(beast.places.Glade.count == 30, "a place must keep the higher encounter count")
    assert(beast.drops["5"].count == 4, "a drop must keep the higher count")
    assert(beast.order == 9, "order must take the maximum across every source")
end

local function test_seeds_next_order_above_every_migrated_record()
    local fj = load()

    local charData = freshChar()
    quietly(fj.Migrations.run, charData, {account = legacyAccount(), recovery = {}})
    assert(charData.nextOrder == 41, "nextOrder must adopt the legacy account counter, got "
        .. tostring(charData.nextOrder))

    -- A legacy counter that was lost must not let new records collide with old.
    local damaged = legacyAccount()
    damaged.nextOrder = 0
    damaged.characters[KEY]["quest:1"].order = 5000
    local second = freshChar()
    quietly(fj.Migrations.run, second, {account = damaged, recovery = {}})
    assert(second.nextOrder == 5000,
        "nextOrder must rise to the highest order actually present, got " .. tostring(second.nextOrder))
end

local function test_survives_malformed_legacy_data()
    local fj = load()
    local charData = freshChar()
    local broken = legacyAccount()
    broken.characters[KEY] = "this is not a table"
    broken.encounters[KEY] = {"neither is this"}
    broken.bestiary[KEY] = {["creature:1"] = 42}

    local lines = quietly(fj.Migrations.run, charData, {account = broken, recovery = {}})

    assert(charData.schemaVersion == 2, "a malformed source must not stop the version bump")
    assert(charData.legacyMigrated == true, "a malformed source must not block the guard")
    assert(type(charData.entries) == "table", "the affected collection must be left empty, not nil")
    assert(#charData.diaryEvents == 1, "a readable collection must still migrate")
    local joined = table.concat(lines, "\n")
    assert(joined:find("malformed legacy.*entries"),
        "expected a specific malformed-entries warning, got:\n" .. joined)
end

local function test_distinguishes_reused_guids_from_true_cross_source_duplicates()
    local fj = load()
    local charData = freshChar()
    local account = legacyAccount()
    -- A creature respawns at the same spawn point: two genuinely distinct
    -- historical encounters that happen to share a guid, weeks apart.
    account.encounters[KEY] = {
        {guid = "g1", name = "Wolf", seenAt = 5},
        {guid = "g1", name = "Wolf", seenAt = 9000},
    }

    quietly(fj.Migrations.run, charData, {
        account = account,
        -- A recovery snapshot re-reporting the exact same first encounter
        -- (same guid AND same seenAt) must still collapse as one record.
        recovery = {{name = "FieldJournalRecoveryDB2", data = {
            characters = {}, nextOrder = 0,
            encounters = {[KEY] = {{guid = "g1", name = "Wolf", seenAt = 5}}},
            diaryEvents = {}, craftEvents = {}, bestiary = {},
            objectiveStates = {}, questBookmarks = {},
        }}},
    })

    assert(#charData.encounters == 2,
        "two distinct encounters at a reused guid must both survive, got " .. #charData.encounters)
end

local function test_logs_counts_before_and_after()
    local fj = load()
    local charData = freshChar()
    local lines = quietly(fj.Migrations.run, charData, {account = legacyAccount(), recovery = {}})
    local joined = table.concat(lines, "\n")
    assert(joined:find("migrating legacy saved data"), "no before-counts line was printed")
    assert(joined:find("migration complete"), "no after-counts line was printed")
    assert(joined:find("1 entries"), "the after line must carry real counts:\n" .. joined)
end

local function test_legacy_character_key_resolves_a_stale_realm_prefix()
    local fj = load()
    assert(fj.Migrations.legacyCharacterKey(nil) == KEY,
        "with no legacy table at all, the current key is the answer")
    assert(fj.Migrations.legacyCharacterKey({characters = {[KEY] = {}}}) == KEY,
        "an exact match must always win")
    assert(fj.Migrations.legacyCharacterKey({characters = {["OldRealm:Wren"] = {}}}) == "OldRealm:Wren",
        "a single stale-realm key for this character must be adopted")
    assert(fj.Migrations.legacyCharacterKey(
        {characters = {["OldRealm:Wren"] = {}, ["OtherRealm:Wren"] = {}}}) == KEY,
        "two candidates is ambiguous, so never guess")
    assert(fj.Migrations.legacyCharacterKey({characters = {["Ashenvale:Someone"] = {}}}) == KEY,
        "another character's key must never be adopted")
end

-- Core/Backup.lua calls this after a restore, to lift nextOrder above every
-- record it just put back so the next new record cannot collide with one of
-- them. It is published rather than re-implemented there.
local function test_highest_order_scans_every_collection()
    local fj = load()
    assert(type(fj.Migrations.highestOrder) == "function",
        "Core/Migrations.lua must publish highestOrder")
    assert(fj.Migrations.highestOrder(freshChar()) == 0, "an empty character has no order at all")

    local charData = freshChar()
    charData.entries["quest:1"] = {key = "quest:1", order = 11}
    assert(fj.Migrations.highestOrder(charData) == 11, "entries must be scanned")

    charData.encounters[1] = {guid = "g1", order = 22}
    assert(fj.Migrations.highestOrder(charData) == 22, "encounters must be scanned")

    charData.diaryEvents[1] = {key = "diary:1", order = 33}
    assert(fj.Migrations.highestOrder(charData) == 33, "diary events must be scanned")

    charData.craftEvents[1] = {key = "craft:1", order = 44}
    assert(fj.Migrations.highestOrder(charData) == 44, "craft events must be scanned")

    charData.bestiary["creature:1"] = {key = "creature:1", order = 55}
    assert(fj.Migrations.highestOrder(charData) == 55, "the bestiary must be scanned")

    charData.entries["quest:2"] = {key = "quest:2", order = "not a number"}
    charData.encounters[2] = "not a table"
    assert(fj.Migrations.highestOrder(charData) == 55, "malformed records must be skipped, not thrown on")
end

-- Core/Backup.lua prints the same count sentence when it lists the ring, so the
-- wording stays identical across migration output, /fj backup and /fj status.
local function test_count_text_formats_all_five_collections()
    local fj = load()
    assert(type(fj.Migrations.countText) == "function",
        "Core/Migrations.lua must publish countText")
    local text = fj.Migrations.countText({entries = 1, encounters = 2, diaryEvents = 3,
        craftEvents = 4, bestiary = 5})
    assert(text == "1 entries, 2 encounters, 3 diary events, 4 craft events, 5 bestiary species",
        "the count sentence changed unexpectedly: " .. text)
end

return {
    test_migrates_the_old_account_shape_for_the_current_character = test_migrates_the_old_account_shape_for_the_current_character,
    test_is_idempotent_and_runs_only_once = test_is_idempotent_and_runs_only_once,
    test_merges_the_per_character_mirror_and_recovery_snapshots = test_merges_the_per_character_mirror_and_recovery_snapshots,
    test_seeds_next_order_above_every_migrated_record = test_seeds_next_order_above_every_migrated_record,
    test_survives_malformed_legacy_data = test_survives_malformed_legacy_data,
    test_distinguishes_reused_guids_from_true_cross_source_duplicates = test_distinguishes_reused_guids_from_true_cross_source_duplicates,
    test_logs_counts_before_and_after = test_logs_counts_before_and_after,
    test_legacy_character_key_resolves_a_stale_realm_prefix = test_legacy_character_key_resolves_a_stale_realm_prefix,
    test_highest_order_scans_every_collection = test_highest_order_scans_every_collection,
    test_count_text_formats_all_five_collections = test_count_text_formats_all_five_collections,
}
