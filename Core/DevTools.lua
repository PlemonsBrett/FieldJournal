-- Field Journal: optional soft integration with Lib's - Addon Tools (LibAT),
-- a separate, standalone addon (github.com/spartanui-wow/Libs-AddonTools)
-- providing structured logging, an error viewer, a profile manager, and a
-- setup wizard. LibAT is never vendored into Libs/ -- it is its own addon,
-- reached only through the global _G.LibAT when the player has it installed.
-- Every call into it is pcall-guarded so a LibAT version mismatch can never
-- break Field Journal itself, matching Core/Database.lua's "never throws"
-- philosophy. Without LibAT installed, this file is a complete no-op.

local FieldJournal = select(2, ...)

local DevTools = {}
FieldJournal.DevTools = DevTools

-- Field Journal has no square icon asset of its own (art/parchment.tga is a
-- background texture, not an icon) -- a built-in icon stands in until one exists.
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- Nil-safe helper other modules call alongside their existing print() lines,
-- without themselves branching on whether LibAT is installed.
function FieldJournal.logError(message)
    if FieldJournal.log and FieldJournal.log.error then pcall(FieldJournal.log.error, message) end
end

-- Called once from Core/Bootstrap.lua's ADDON_LOADED handler, before
-- FieldJournal.Database.initialize() -- so that if database initialization
-- itself fails, FieldJournal.logError can still reach LibAT's logger.
function DevTools.registerLogger()
    local LibAT = _G.LibAT
    if not LibAT or not LibAT.Logger or not LibAT.Logger.RegisterAddon then return end
    local ok, logger = pcall(LibAT.Logger.RegisterAddon, "FieldJournal")
    if ok then FieldJournal.log = logger end
end

-- Called once from Core/Bootstrap.lua's ADDON_LOADED handler, right after
-- FieldJournal.Database.initialize() so FieldJournal.db already exists.
function DevTools.initialize()
    local LibAT = _G.LibAT
    if not LibAT then return end

    if LibAT.ProfileManager and LibAT.ProfileManager.RegisterAddon then
        pcall(function()
            LibAT.ProfileManager:RegisterAddon({name = "FieldJournal", db = FieldJournal.db, icon = ICON})
        end)
    end

    if LibAT.SetupWizard and LibAT.SetupWizard.RegisterAddon then
        pcall(function()
            LibAT.SetupWizard:RegisterAddon("fieldjournal", {
                name = "Field Journal",
                icon = ICON,
                pages = {
                    {
                        title = "Welcome to Field Journal",
                        text = "Field Journal records your quests, encounters, and travels automatically.\n\n"
                            .. "This client's SavedVariables are known to fail to reload on their own -- "
                            .. "install ForeverSVFix (github.com/nobewayo/ForeverSVFix) alongside Field Journal "
                            .. "or your journal entries may not survive a reload.",
                    },
                },
                onComplete = function() end,
            })
        end)
    end

    -- Error Handler: no registration call exists. LibAT's BugGrabber-based
    -- error viewer captures every addon's Lua errors globally once LibAT is
    -- installed -- there is nothing for Field Journal to opt into.
end
