-- Field Journal: compatibility shim for this client's non-standard globals.
--
-- LOAD ORDER IS LOAD-BEARING. FieldJournal.toc lists this file FIRST, ahead of
-- the whole Libs/ block, because Libs/AceDB-3.0/AceDB-3.0.lua computes its
-- realm/char/class/race/faction/locale/region keys in its FILE BODY (lines
-- 258-268), not inside :New(), and immediately concatenates three of them into
-- strings. On this client (a WoW Forever beta build, Interface 16001)
-- GetCurrentRegion() answers with a value outside AceDB's five-element
-- {US,KR,EU,TW,CN} table, so
--     local regionKey = regionTable[GetCurrentRegion()]
--     local factionrealmregionKey = factionrealmKey .. " - " .. regionKey
-- raised "attempt to concatenate local 'regionKey' (a nil value)" and killed
-- addon loading for the entire client. Plan 1 forbids editing vendored files,
-- so we make the globals safe for the duration of the Libs/ block instead, and
-- Core/Database.lua -- the first file that loads after Libs/ -- calls restore()
-- to hand the client its own functions back untouched.

local FieldJournal = select(2, ...)

local Compat = {}
FieldJournal.ClientCompat = Compat

-- These five are wrapped, each because a nil or out-of-range answer from it
-- crashes AceDB-3.0.lua while it is still loading:
--   GetCurrentRegion  -> lines 267-268 (the confirmed crash on this client)
--   GetRealmName      -> line 259      (nil realm -> concat error)
--   UnitName          -> line 260      (nil character -> concat error)
--   UnitFactionGroup  -> lines 262-263 (nil faction -> concat error)
--   GetLocale         -> line 264      (nil locale  -> :lower() on a nil value)
-- Fallbacks for GetRealmName and UnitName match Core/Bootstrap.lua's own
-- characterKey() fallbacks, so no new behavior is introduced if the client's
-- raw call actually does return nil — AceDB just gets the same fallback string
-- characterKey() already uses elsewhere.
-- UnitClass and UnitRace are deliberately NOT wrapped: a nil class or race key
-- does not crash AceDB, it just leaves keyTbl.class / keyTbl.race absent, and
-- this addon never reads db.class or db.race.
local NAMES = {"GetCurrentRegion", "GetRealmName", "UnitName", "UnitFactionGroup", "GetLocale"}

local originals = {}
local installed = false

-- AceDB indexes a five-element array with this value, so only the integers
-- 1 through 5 are safe. Everything else becomes 1 ("US"), which is an
-- arbitrary but valid choice: this addon stores nothing under db.region or
-- db.factionrealmregion, so the value only has to be non-nil.
function Compat.safeRegion(value)
    if type(value) ~= "number" then return 1 end
    if value ~= math.floor(value) then return 1 end
    if value < 1 or value > 5 then return 1 end
    return value
end

function Compat.install()
    if installed then return end
    for _, name in ipairs(NAMES) do originals[name] = _G[name] end
    installed = true

    local getCurrentRegion = originals.GetCurrentRegion
    _G.GetCurrentRegion = function(...)
        if type(getCurrentRegion) ~= "function" then return 1 end
        local ok, value = pcall(getCurrentRegion, ...)
        if not ok then return 1 end
        return Compat.safeRegion(value)
    end

    local getRealmName = originals.GetRealmName
    _G.GetRealmName = function(...)
        if type(getRealmName) ~= "function" then return "Unknown realm" end
        local ok, value = pcall(getRealmName, ...)
        if not ok or type(value) ~= "string" or value == "" then return "Unknown realm" end
        return value
    end

    local unitName = originals.UnitName
    _G.UnitName = function(...)
        if type(unitName) ~= "function" then return "Unknown character" end
        local ok, value = pcall(unitName, ...)
        if not ok or type(value) ~= "string" or value == "" then return "Unknown character" end
        return value
    end

    local unitFactionGroup = originals.UnitFactionGroup
    _G.UnitFactionGroup = function(...)
        if type(unitFactionGroup) ~= "function" then return "Neutral" end
        local ok, english, localized = pcall(unitFactionGroup, ...)
        if not ok then return "Neutral" end
        if type(english) ~= "string" or english == "" then return "Neutral", localized end
        return english, localized
    end

    local getLocale = originals.GetLocale
    _G.GetLocale = function(...)
        if type(getLocale) ~= "function" then return "enUS" end
        local ok, value = pcall(getLocale, ...)
        if not ok or type(value) ~= "string" or value == "" then return "enUS" end
        return value
    end
end

-- Puts every wrapped global back exactly as the client had it, including
-- setting it back to nil if the client never defined it. Safe to call more
-- than once, and safe to never call at all (the wrappers are transparent).
function Compat.restore()
    if not installed then return end
    installed = false
    for _, name in ipairs(NAMES) do _G[name] = originals[name] end
end

Compat.install()
