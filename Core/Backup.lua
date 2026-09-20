-- Field Journal: the rotating self-heal backup ring, and (from Task 3) the
-- restore half of /fj repair.
--
-- WHY THIS EXISTS. Releases 0.7.1 through 0.8.0 were spent recovering from
-- SavedVariables loss, patched up afterwards by hand-adding
-- FieldJournalRecoveryDB / DB2 / DB3 globals holding the maintainer's personal
-- snapshots and merging them in at every load. That does not scale and cannot
-- ship to other players -- nobody else's install has those globals. This file
-- replaces the pattern with a ring of five snapshots that every install
-- maintains for itself, and a /fj repair that merges anything the live data has
-- lost back in. No developer-authored recovery global, ever again.
--
-- WHAT IS SNAPSHOTTED, AND HOW BIG IT IS. Exactly one thing: db.char -- which
-- AceDB has already scoped to the logged-in character -- minus its own
-- `backups` field. This is NOT an account-wide copy of every character; that
-- distinction is the whole sizing argument. One beta character's journal is
-- hundreds of records, and the ring is five copies of that. The `backups` field
-- is excluded because including it would nest each snapshot inside the next and
-- grow the saved file exponentially; test_snapshot_data_is_a_deep_copy_without_
-- the_backups_field enforces that. SNAPSHOT_LIMIT below is the single knob:
-- lowering it needs no schema change and no migration, exactly as the design
-- spec allows.
--
-- WHEN A SNAPSHOT IS *NOT* TAKEN. The spec asks only for "skip if the most
-- recent snapshot has identical record counts". That alone is not safe. If a
-- login ever sees a damaged or unloaded db.char, a naive ring would dutifully
-- back up the damage, and after five such logins would have rotated every good
-- snapshot out -- destroying the only copy at exactly the moment it is needed.
-- shouldCapture below therefore also refuses when the live data has LOST
-- records relative to the newest snapshot, and says so in chat. That is the
-- same class of bug as the "backup mirror wiped on a failed migration" defect
-- caught in Plan 3a review, and it is guarded here for the same reason.
--
-- WHAT THE RING DOES NOT PROTECT AGAINST. It lives inside FieldJournalDB --
-- the same account saved-variables file whose loss motivated this whole phase.
-- So it protects against in-file damage (a collection emptied, a bad merge, a
-- half-written table) and not against the whole file disappearing. The
-- independent second copy for that case is still the per-character
-- FieldJournalCharacterDB mirror written by Core/Bootstrap.lua, which this
-- release deliberately keeps, and later Plan 3c's /fj export.
--
-- Nothing in this file may throw. capture() runs inside the addon's PLAYER_LOGIN
-- event dispatch and repair() runs from a slash command; both catch their own
-- errors, print, and degrade.

local FieldJournal = select(2, ...)

local Backup = {}
FieldJournal.Backup = Backup

-- Five rotating snapshots, exactly as the Phase 1 design spec specifies. One
-- knob, one place -- see the sizing note at the top of this file.
Backup.SNAPSHOT_LIMIT = 5

-- The five collections FieldJournal.Migrations.counts() tallies, paired with
-- the wording /fj repair uses when it reports what it restored.
local COUNTED = {
    {field = "entries", label = "entries"},
    {field = "encounters", label = "encounters"},
    {field = "diaryEvents", label = "diary events"},
    {field = "craftEvents", label = "craft events"},
    {field = "bestiary", label = "bestiary species"},
}

-- Four of those five are append-only in normal play. Grepping Data/ for every
-- write to them, the ONLY removals are two fixed-size caps --
-- Data/Bestiary.lua's  `if #encounters > 2500 then table.remove(encounters, 1) end`
-- and Data/Diary.lua's `if #collection > 3000 then table.remove(collection, 1) end`
-- -- and each fires immediately after an append, so the net count never falls.
-- The bestiary is a keyed map that is only added to or max-reconciled. A drop in
-- any of these four therefore means records were lost, which is a reason to
-- protect the ring rather than rotate it.
--
-- `entries` is deliberately NOT in this list. Data/QuestLog.lua's addEntry does
--     if kind == "quest" and id then entries["past:" .. id] = nil end
-- so when the player captures a real quest's text, the recovered-description
-- placeholder for that quest is deleted. A one- or two-entry drop between
-- logins is therefore normal, and treating it as data loss would freeze the
-- ring for a player who is simply re-walking quests they had only completed
-- before. Wholesale entry loss is still caught, by the "emptied" rule below.
local MONOTONIC = {"encounters", "diaryEvents", "craftEvents", "bestiary"}

local REASON_TEXT = {
    shrunk = "this character has FEWER records than its most recent backup snapshot, "
        .. "so no new snapshot was taken and the existing ones are preserved. Run /fj repair.",
    emptied = "this character's journal is empty but its most recent backup snapshot is not, "
        .. "so no new snapshot was taken and the existing ones are preserved. Run /fj repair.",
}

-- Everything this file borrows lives on the shared namespace and is read at
-- call time rather than captured at load time, so Core/Backup.lua stays
-- loadable -- and every entry point stays non-throwing -- even if
-- Core/Database.lua or Core/Migrations.lua failed to initialise.
local function helpers()
    local Database, Migrations = FieldJournal.Database, FieldJournal.Migrations
    if type(Database) ~= "table" or type(Migrations) ~= "table" then return nil end
    if type(Database.deepCopy) ~= "function" then return nil end
    if type(Migrations.counts) ~= "function" then return nil end
    if type(Migrations.countText) ~= "function" then return nil end
    if type(Migrations.mergeIntoCharacter) ~= "function" then return nil end
    if type(Migrations.highestOrder) ~= "function" then return nil end
    return {
        deepCopy = Database.deepCopy,
        counts = Migrations.counts,
        countText = Migrations.countText,
        mergeIntoCharacter = Migrations.mergeIntoCharacter,
        highestOrder = Migrations.highestOrder,
    }
end

-- Prefer the counts stored on the snapshot (cheap, and what /fj backup lists),
-- but recompute from the snapshot's own data if they are missing or malformed,
-- which is what a hand-edited saved-variables file looks like.
local function snapshotCounts(snapshot, h)
    if type(snapshot) ~= "table" then return nil end
    local stored = snapshot.counts
    if type(stored) == "table" then
        local usable = true
        for _, counted in ipairs(COUNTED) do
            if type(stored[counted.field]) ~= "number" then usable = false end
        end
        if usable then return stored end
    end
    if type(snapshot.data) == "table" then return h.counts(snapshot.data) end
    return nil
end

--- A deep copy of every db.char field except the ring itself. This is exactly
--  the flat shape FieldJournal.Migrations.mergeIntoCharacter consumes --
--  entries / encounters / diaryEvents / craftEvents / bestiary / objectiveState
--  / questBookmarks -- so a snapshot can be merged straight back in with no
--  reshaping, and it additionally carries nextOrder and schemaVersion, which
--  the restore path uses. Every other field of db.char is copied too, so a
--  later plan adding a field gets it in the snapshot for free.
function Backup.snapshotData(charData)
    local h = helpers()
    if not h or type(charData) ~= "table" then return nil end
    local data = {}
    for key, value in pairs(charData) do
        if key ~= "backups" then data[key] = h.deepCopy(value) end
    end
    return data
end

--- Decides whether to add a snapshot to the ring. Returns ok, reason, where
--  reason is one of "unavailable", "first", "identical", "shrunk", "emptied",
--  "changed". Only the newest snapshot is compared against: if it is garbage,
--  the answer is "first" and a fresh good snapshot gets prepended in front of
--  it, which is the right recovery.
function Backup.shouldCapture(charData)
    local h = helpers()
    if not h or type(charData) ~= "table" then return false, "unavailable" end

    local ring = charData.backups
    if type(ring) ~= "table" then return true, "first" end
    local previous = snapshotCounts(ring[1], h)
    if not previous then return true, "first" end

    local live = h.counts(charData)

    for _, field in ipairs(MONOTONIC) do
        if live[field] < previous[field] then return false, "shrunk" end
    end

    local liveTotal, previousTotal, identical = 0, 0, true
    for _, counted in ipairs(COUNTED) do
        local field = counted.field
        liveTotal = liveTotal + live[field]
        previousTotal = previousTotal + previous[field]
        if live[field] ~= previous[field] then identical = false end
    end

    if liveTotal == 0 and previousTotal > 0 then return false, "emptied" end
    if identical then return false, "identical" end
    return true, "changed"
end

local function performCapture(charData, h)
    local ring = charData.backups
    if type(ring) ~= "table" then
        ring = {}
        charData.backups = ring
    end
    table.insert(ring, 1, {
        at = time(),
        counts = h.counts(charData),
        data = Backup.snapshotData(charData),
    })
    while #ring > Backup.SNAPSHOT_LIMIT do table.remove(ring) end
end

--- Takes one rotating snapshot if shouldCapture agrees. Returns taken, reason.
--  Never throws: called from Core/Bootstrap.lua's PLAYER_LOGIN dispatch.
function Backup.capture(charData)
    local ok, reason = Backup.shouldCapture(charData)
    if not ok then
        if REASON_TEXT[reason] then print("Field Journal: " .. REASON_TEXT[reason]) end
        return false, reason
    end

    local done, err = pcall(performCapture, charData, helpers())
    if not done then
        FieldJournal.backupError = tostring(err)
        print("Field Journal: could not take a backup snapshot (" .. tostring(err)
            .. "). Your journal was not changed.")
        return false, "error"
    end

    FieldJournal.backupError = nil
    return true, reason
end

--- Chat-ready lines describing the ring, newest first. Returned as a table
--  rather than printed so /fj backup, /fj status and the test suite can all
--  read the same description without capturing print.
function Backup.describe(charData)
    local lines = {}
    local h = helpers()
    if not h or type(charData) ~= "table" then
        lines[1] = "Field Journal: the database is not available, so there are no backup snapshots."
        return lines
    end

    local ring = type(charData.backups) == "table" and charData.backups or {}
    if #ring == 0 then
        lines[1] = "Field Journal: no backup snapshots yet. One is taken automatically at each login."
        return lines
    end

    lines[1] = "Field Journal: " .. #ring .. " of " .. Backup.SNAPSHOT_LIMIT
        .. " backup snapshots, newest first."
    for index = 1, #ring do
        local snapshot = ring[index]
        local tally = snapshotCounts(snapshot, h)
        local at = type(snapshot) == "table" and tonumber(snapshot.at) or nil
        lines[#lines + 1] = "  " .. index .. ". "
            .. (at and date("%Y-%m-%d %H:%M", at) or "unknown time")
            .. " - " .. (tally and h.countText(tally) or "unreadable snapshot")
    end
    return lines
end
