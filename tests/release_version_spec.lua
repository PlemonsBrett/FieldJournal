local version = dofile("tools/release_version.lua")

local SAMPLE_TOC = [[
## Interface: 16001
## Title: Field Journal
## Version: 0.8.0-beta
## X-Wago-ID: bGoyor60
]]

local SAMPLE_CHANGELOG = [[
# Changelog

## AceDB-3.0 persistence migration

Existing notes stay below the new section.
]]

return {
    ["parse_version splits core and suffix"] = function()
        local parsed = version.parse_version("0.8.0-beta")
        assert(parsed.major == 0, "major")
        assert(parsed.minor == 8, "minor")
        assert(parsed.patch == 0, "patch")
        assert(parsed.suffix == "-beta", "suffix")
    end,

    ["increment_patch keeps beta suffix"] = function()
        assert(version.increment_patch("0.8.0-beta") == "0.8.1-beta")
        assert(version.increment_patch("1.2.3") == "1.2.4")
        assert(version.increment_patch("0.9.9-alpha") == "0.9.10-alpha")
    end,

    ["parse_version rejects garbage"] = function()
        local ok, err = pcall(version.parse_version, "nightly")
        assert(ok == false, "should reject non-semver")
        assert(tostring(err):find("major.minor.patch", 1, true), "error should name the expected shape: " .. tostring(err))
    end,

    ["first release keeps the TOC version"] = function()
        assert(version.next_release_version("0.8.0-beta", nil) == "0.8.0-beta")
        assert(version.next_release_version("0.8.0-beta", "") == "0.8.0-beta")
    end,

    ["already-bumped TOC wins over the last tag"] = function()
        assert(version.next_release_version("0.9.0-beta", "0.8.1-beta") == "0.9.0-beta")
    end,

    ["matching TOC and last tag increment the patch"] = function()
        assert(version.next_release_version("0.8.0-beta", "0.8.0-beta") == "0.8.1-beta")
    end,

    ["replace_toc_version updates only the Version line"] = function()
        local updated = version.replace_toc_version(SAMPLE_TOC, "0.8.1-beta")
        assert(updated:find("## Version: 0.8.1-beta", 1, true), "version line not updated")
        assert(updated:find("## X-Wago-ID: bGoyor60", 1, true), "unrelated TOC metadata was changed")
        assert(not updated:find("## Version: 0.8.0-beta", 1, true), "old version left in place")
    end,

    ["prepend_changelog inserts the new version above existing notes"] = function()
        local updated = version.prepend_changelog(SAMPLE_CHANGELOG, "0.8.1-beta", "## What's Changed\n\n- feat: add CI (#13)\n")
        assert(updated:find("# Changelog\n\n## 0.8.1-beta\n", 1, true), "new heading should follow the title")
        assert(updated:find("- feat: add CI (#13)", 1, true), "notes should be preserved")
        local new_at = updated:find("## 0.8.1-beta", 1, true)
        local old_at = updated:find("## AceDB-3.0 persistence migration", 1, true)
        assert(new_at < old_at, "new section must be above existing history")
    end,

    ["prepend_changelog refuses a duplicate latest version"] = function()
        local once = version.prepend_changelog(SAMPLE_CHANGELOG, "0.8.1-beta", "notes")
        local ok, err = pcall(version.prepend_changelog, once, "0.8.1-beta", "notes again")
        assert(ok == false, "duplicate latest version should fail")
        assert(tostring(err):find("already starts with version", 1, true), "error should mention the duplicate: " .. tostring(err))
    end,
}
