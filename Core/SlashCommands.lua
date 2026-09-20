-- Field Journal: the /fj and /fieldjournal command handler.

local FieldJournal = select(2, ...)

local clean = FieldJournal.clean

SLASH_FIELDJOURNAL1 = "/fieldjournal"
SLASH_FIELDJOURNAL2 = "/fj"
SlashCmdList.FIELDJOURNAL = function(message)
    local command, remainder = (message or ""):match("^(%S+)%s*(.-)%s*$")
    if command == "repair" then
        FieldJournal.loadedCharacterKey = nil
        FieldJournal.initializeCharacter()
        FieldJournal.UI.RefreshIfShown()
        print("Field Journal: restored the bestiary index from saved encounters where needed.")
        return
    end
    if command == "status" then
        FieldJournal.initializeCharacter()
        local function listens(eventName)
            return FieldJournal.frame.IsEventRegistered and FieldJournal.frame:IsEventRegistered(eventName) and "on" or "off"
        end
        local species = 0
        for _ in pairs(FieldJournal.bestiary or {}) do species = species + 1 end
        local recoveries = (FieldJournalRecoveryDB and 1 or 0)
            + (FieldJournalRecoveryDB2 and 1 or 0) + (FieldJournalRecoveryDB3 and 1 or 0)
        local charData = FieldJournal.charData
        local schema = charData and charData.schemaVersion or 0
        local migrated = (charData and charData.legacyMigrated) and "yes" or "no"
        print("Field Journal: PARTY_KILL " .. listens("PARTY_KILL")
            .. ", UNIT_DIED " .. listens("UNIT_DIED")
            .. ", encounters " .. tostring(FieldJournal.encounters and #FieldJournal.encounters or 0)
            .. ", bestiary species " .. species
            .. ", craft events " .. tostring(FieldJournal.craftEvents and #FieldJournal.craftEvents or 0)
            .. ", recovery snapshots " .. recoveries
            .. ", character " .. tostring(FieldJournal.loadedCharacterKey or "not loaded")
            .. ", schema v" .. tostring(schema)
            .. ", legacy migration " .. migrated .. ".")
        if FieldJournal.databaseError then
            print("Field Journal: database error - " .. tostring(FieldJournal.databaseError))
            if FieldJournal.logError then FieldJournal.logError(tostring(FieldJournal.databaseError)) end
        end
        if FieldJournal.migrationError then
            print("Field Journal: migration error - " .. tostring(FieldJournal.migrationError))
            if FieldJournal.logError then FieldJournal.logError(tostring(FieldJournal.migrationError)) end
        end
        return
    end
    if command == "remember" or command == "note" then
        local title, body = (remainder or ""):match("^(.-)%s*|%s*(.+)$")
        if not title or clean(title) == "" or clean(body) == "" then
            print("Field Journal: use /fj " .. command .. " Name | Text")
            return
        end
        if command == "remember" then
            FieldJournal.QuestLog.addEntry("speech", nil, "Remembered", title, body, "", FieldJournal.QuestLog.findUniqueQuestMention(title))
        else
            FieldJournal.QuestLog.addEntry("note", nil, "Note", title, body, "", FieldJournal.QuestLog.findUniqueQuestMention(title))
        end
        print("Field Journal: recorded " .. clean(title) .. ".")
        return
    end
    if not FieldJournal.UI.window then FieldJournal.UI.createWindow() end
    if FieldJournal.UI.window:IsShown() then FieldJournal.UI.window:Hide() else FieldJournal.UI.window:Show() end
end
