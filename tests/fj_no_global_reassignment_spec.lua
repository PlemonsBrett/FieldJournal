-- Permanent regression guard: no file FieldJournal.toc actually loads may ever
-- reassign the five WoW API globals that Libs/AceDB-3.0/AceDB-3.0.lua's inline
-- patch (see the "FIELD JOURNAL PATCH" comment there) depends on being the
-- real, untouched Blizzard functions. Earlier in this project's history,
-- temporarily wrapping these globals to work around a load-time AceDB-3.0
-- crash (then restoring them afterwards) permanently broke Blizzard's own
-- protected UI (unit-frame health bars) under WoW's Patch 12.1 secret-value
-- taint system, because restoring a wrapped global's value does not clear the
-- taint mark the client places on it. This test makes "nothing ever
-- reassigns these globals" a permanent, source-level, automatically enforced
-- property instead of something a reviewer has to re-verify by hand every
-- time this project's files change.

local GUARDED_GLOBALS = {
    "GetCurrentRegion", "GetRealmName", "UnitName", "UnitFactionGroup", "GetLocale",
}

-- Returns the list of file paths FieldJournal.toc actually loads, in order
-- (skipping blank lines and "##" metadata lines). This is deliberately read
-- from the real .toc rather than hard-coded, so this test always checks
-- exactly what the client loads.
local function tocFiles()
    local files = {}
    for line in io.lines("FieldJournal.toc") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^##") then
            files[#files + 1] = trimmed
        end
    end
    assert(#files > 0, "FieldJournal.toc listed no files -- something is wrong with this test's parsing")
    return files
end

-- True if `line` contains a statement that assigns directly to the global
-- `name`, either as a bare global ("NAME = ...") or through _G ("_G.NAME = ..."
-- or "_G[\"NAME\"] = ..."). Deliberately does NOT flag "someTable.NAME = ..."
-- (a table field that happens to share the name is not a global reassignment),
-- "NAME == ..." (comparison, not assignment), "NAME(...)" (a call), or NAME
-- appearing inside a longer identifier.
local function reassignsGlobal(line, name)
    local code = line:gsub("%-%-.*$", "") -- strip trailing line comments

    if code:find("_G%s*%.%s*" .. name .. "%s*=[^=]")
        or code:find("_G%s*%[%s*[\"']" .. name .. "[\"']%s*%]%s*=[^=]") then
        return true
    end

    local searchFrom = 1
    while true do
        local s, e = code:find("%f[%w_]" .. name .. "%f[^%w_]", searchFrom)
        if not s then return false end
        searchFrom = e + 1
        local before = code:sub(1, s - 1)
        if not before:match("%.%s*$") then
            local afterTrimmed = code:sub(e + 1):match("^%s*(.*)$")
            if afterTrimmed:sub(1, 1) == "=" and afterTrimmed:sub(2, 2) ~= "=" then
                return true
            end
        end
    end
end

local function test_no_shipped_file_ever_reassigns_a_guarded_wow_global()
    for _, path in ipairs(tocFiles()) do
        local file = assert(io.open(path, "r"), "could not open " .. path .. " listed in FieldJournal.toc")
        local lineNumber = 0
        for line in file:lines() do
            lineNumber = lineNumber + 1
            for _, name in ipairs(GUARDED_GLOBALS) do
                assert(not reassignsGlobal(line, name),
                    path .. ":" .. lineNumber .. " appears to reassign the global '" .. name
                        .. "' -- this must never happen (see the comment at the top of this file)")
            end
        end
        file:close()
    end
end

return {
    test_no_shipped_file_ever_reassigns_a_guarded_wow_global = test_no_shipped_file_ever_reassigns_a_guarded_wow_global,
}
