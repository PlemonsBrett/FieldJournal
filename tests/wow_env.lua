-- Shared loader for FieldJournal's own module files under plain Lua 5.1.
-- WoW calls every addon file as a chunk with (addonName, addonTable) as its
-- vararg; loadModules does exactly the same so module files run unmodified.
-- Only globals the files touch at LOAD time need stubbing here.

-- Frames record the scripts and events addon code registers on them, so a spec
-- can drive Core/Bootstrap.lua's real OnEvent dispatcher:
--     fj.frame:GetScript("OnEvent")(fj.frame, "PLAYER_LOGIN")
-- Everything else is still a no-op via the __index fallback. The five real
-- methods are rawset on the frame, so __index never shadows them.
local function noopFrame()
    local frame = {fjScripts = {}, fjEvents = {}}
    function frame:SetScript(name, handler) self.fjScripts[name] = handler end
    function frame:GetScript(name) return self.fjScripts[name] end
    function frame:RegisterEvent(event) self.fjEvents[event] = true end
    function frame:UnregisterEvent(event) self.fjEvents[event] = nil end
    function frame:IsEventRegistered(event) return self.fjEvents[event] == true end
    return setmetatable(frame, {__index = function() return function() end end})
end

local function install()
    _G.CreateFrame = function() return noopFrame() end
    _G.SlashCmdList = _G.SlashCmdList or {}
    _G.time = os.time
    _G.date = os.date
    _G.tinsert = table.insert
    _G.wipe = function(t)
        for key in pairs(t) do t[key] = nil end
        return t
    end
end

-- Loads the given files in order into one fresh namespace table and returns it.
local function loadModules(paths)
    install()
    local ns = {}
    for _, path in ipairs(paths) do
        local chunk, err = loadfile(path)
        assert(chunk, "could not load " .. path .. ": " .. tostring(err))
        chunk("FieldJournal", ns)
    end
    return ns
end

return {install = install, loadModules = loadModules}
