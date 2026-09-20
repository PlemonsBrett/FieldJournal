-- Minimal Lua 5.1 test runner for FieldJournal's pure-logic modules.
-- Run from the repo root (PowerShell): & "C:\Program Files (x86)\Lua\5.1\lua.exe" tests/run_tests.lua
-- Each file listed in `specs` must `return` a table of { name = function() ... end }.
-- A test passes if its function runs without raising an error (use `assert`).

-- Provide WoW API globals that vendored libraries call but plain Lua 5.1 doesn't have.
_G.strmatch = string.match

local specs = {
    "tests/libstub_spec.lua",
    "tests/callbackhandler_spec.lua",
    "tests/acedb_spec.lua",
    "tests/aceserializer_spec.lua",
    "tests/libdeflate_spec.lua",
    "tests/fj_core_spec.lua",
    "tests/fj_load_spec.lua",
    "tests/fj_merge_spec.lua",
    "tests/fj_questlog_spec.lua",
    "tests/fj_diary_spec.lua",
    "tests/fj_database_spec.lua",
    "tests/fj_migration_spec.lua",
    "tests/fj_no_global_reassignment_spec.lua",
}

local passed, failed = 0, 0
local failures = {}

for _, path in ipairs(specs) do
    local chunk, loadErr = loadfile(path)
    if not chunk then
        failed = failed + 1
        failures[#failures + 1] = path .. ": " .. tostring(loadErr)
    else
        local ranOk, tests = pcall(chunk)
        if not ranOk or type(tests) ~= "table" then
            failed = failed + 1
            failures[#failures + 1] = path .. ": did not return a table of test functions (" .. tostring(tests) .. ")"
        else
            for name, testFn in pairs(tests) do
                local testOk, err = pcall(testFn)
                if testOk then
                    passed = passed + 1
                else
                    failed = failed + 1
                    failures[#failures + 1] = path .. " > " .. name .. ": " .. tostring(err)
                end
            end
        end
    end
end

print(passed .. " passed, " .. failed .. " failed")
for _, failure in ipairs(failures) do
    print("  FAIL " .. failure)
end
os.exit(failed == 0 and 0 or 1)
