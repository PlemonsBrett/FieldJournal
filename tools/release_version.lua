-- Pure version and changelog helpers for the main-merge release pipeline.
-- Kept free of git/gh so the existing Lua 5.1 test runner can exercise every
-- decision: first release keeps the TOC version, an already-bumped TOC wins,
-- otherwise the patch number increments and any prerelease suffix is preserved.

local function parse_version(raw)
    assert(type(raw) == "string" and raw ~= "", "version must be a non-empty string, got: " .. tostring(raw))
    local major, minor, patch, suffix = raw:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major then
        error("version is not major.minor.patch[suffix]: " .. raw)
    end
    return {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
        suffix = suffix or "",
    }
end

local function format_version(parsed)
    return string.format("%d.%d.%d%s", parsed.major, parsed.minor, parsed.patch, parsed.suffix)
end

-- 0.8.0-beta -> 0.8.1-beta; 1.2.3 -> 1.2.4. Suffix is never invented or dropped.
local function increment_patch(raw)
    local parsed = parse_version(raw)
    parsed.patch = parsed.patch + 1
    return format_version(parsed)
end

-- last_tag_version is the previous GitHub release tag without the leading v,
-- or nil/"" when this repository has never published a v* tag.
local function next_release_version(toc_version, last_tag_version)
    parse_version(toc_version)
    if last_tag_version == nil or last_tag_version == "" then
        return toc_version
    end
    parse_version(last_tag_version)
    if toc_version ~= last_tag_version then
        return toc_version
    end
    return increment_patch(toc_version)
end

local function strip_cr(text)
    return (text:gsub("\r", ""))
end

local function replace_toc_version(toc_text, version)
    parse_version(version)
    local normalized = strip_cr(toc_text)
    local updated, count = normalized:gsub("^(.-## Version:%s*)(%S+)", function(prefix)
        return prefix .. version
    end, 1)
    if count ~= 1 then
        error("could not find exactly one ## Version line in TOC")
    end
    return updated
end

-- Inserts `## <version>\n\n<notes>` immediately after the `# Changelog` title.
-- Fails if that version heading is already the first section so a retried
-- prepare job cannot silently duplicate a release.
local function prepend_changelog(changelog_text, version, notes)
    parse_version(version)
    assert(type(notes) == "string" and notes:match("%S"), "changelog notes must be non-empty")
    local normalized = strip_cr(changelog_text)
    if not normalized:match("^# Changelog\n") then
        error("CHANGELOG.md must start with '# Changelog'")
    end
    -- Headings in this file are ATX H2 (`## 0.8.0 daily pages`). The first
    -- capture is the heading text after `## `.
    local first_heading = normalized:match("^# Changelog\n+## ([^\n]+)")
    if first_heading == version or (first_heading and first_heading:match("^" .. version:gsub("(%W)", "%%%1") .. "%f[%s]") ) then
        error("CHANGELOG.md already starts with version " .. version)
    end
    local trimmed_notes = notes:gsub("^%s+", ""):gsub("%s+$", "")
    local section = "## " .. version .. "\n\n" .. trimmed_notes .. "\n"
    local updated, count = normalized:gsub("^# Changelog\n+", "# Changelog\n\n" .. section .. "\n", 1)
    if count ~= 1 then
        error("could not insert changelog section after the title")
    end
    return updated
end

local function read_file(path)
    local handle = assert(io.open(path, "rb"), "could not open " .. path)
    local contents = handle:read("*a")
    handle:close()
    return contents
end

local function write_file(path, contents)
    local handle = assert(io.open(path, "wb"), "could not write " .. path)
    handle:write(contents)
    if contents:sub(-1) ~= "\n" then
        handle:write("\n")
    end
    handle:close()
end

local function apply_release_files(toc_path, changelog_path, version, notes)
    write_file(toc_path, replace_toc_version(read_file(toc_path), version))
    write_file(changelog_path, prepend_changelog(read_file(changelog_path), version, notes))
end

local function print_usage()
    io.stderr:write("Usage:\n")
    io.stderr:write("  lua tools/release_version.lua next-version <toc-version> [last-tag-version]\n")
    io.stderr:write("  lua tools/release_version.lua apply <toc-path> <changelog-path> <version> <notes-path>\n")
end

local function run_cli(argv)
    local command = argv[1]
    if command == "next-version" then
        assert(argv[2], "missing toc-version")
        io.stdout:write(next_release_version(argv[2], argv[3] or "") .. "\n")
        return
    end
    if command == "apply" then
        assert(argv[2] and argv[3] and argv[4] and argv[5], "apply requires toc, changelog, version, notes-path")
        apply_release_files(argv[2], argv[3], argv[4], read_file(argv[5]))
        return
    end
    print_usage()
    error("unknown command: " .. tostring(command))
end

local invoked_as_script = arg and type(arg[0]) == "string" and arg[0]:gsub("\\", "/"):match("release_version%.lua$")
if invoked_as_script and arg[1] then
    run_cli(arg)
end

return {
    parse_version = parse_version,
    increment_patch = increment_patch,
    next_release_version = next_release_version,
    replace_toc_version = replace_toc_version,
    prepend_changelog = prepend_changelog,
    apply_release_files = apply_release_files,
}
