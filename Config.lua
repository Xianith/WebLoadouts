----------------------------------------------------------------------
-- WebLoadouts — Config.lua
-- Slash commands, help, and settings
----------------------------------------------------------------------

local ADDON_NAME, WL = ...

----------------------------------------------------------------------
-- Slash Commands
----------------------------------------------------------------------

SLASH_WEBLOADOUTS1 = "/webloadouts"
SLASH_WEBLOADOUTS2 = "/wl"

SlashCmdList["WEBLOADOUTS"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "help" then
        WL:PrintHelp()

    elseif cmd == "toggle" or cmd == "show" then
        local parentFrame = PlayerSpellsFrame or ClassTalentFrame
        if parentFrame and parentFrame:IsShown() then
            WL:ToggleMenu()
        else
            WL:Print("Open the talent window first (default: N key).")
        end

    elseif cmd == "add" or cmd == "import" then
        WL:ShowAddImportDialog()

    elseif cmd == "list" then
        WL:ListSavedBuilds()

    elseif cmd == "export" then
        local str = WL:ExportCurrentBuild()
        if str then
            WL:CopyToClipboard(str)
            WL:Print("Current build exported to clipboard.")
            WL:Print("|cff888888" .. str:sub(1, 40) .. "...|r")
        end

    elseif cmd == "delete" or cmd == "remove" then
        rest = strtrim(rest)
        if rest == "" then
            WL:Print("Usage: /wl delete <build name>")
            return
        end
        WL:DeleteBuildByName(rest)

    elseif cmd == "clear" then
        StaticPopup_Show("WEBLOADOUTS_CONFIRM_CLEAR")

    elseif cmd == "debug" then
        local current = WL:GetSetting("debug")
        WL:SetSetting("debug", not current)
        WL:Print("Debug mode: " .. (not current and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        WL:OpenSettings()

    else
        WL:Print("Unknown command: " .. cmd .. ". Type |cff00ccff/wl help|r for a list.")
    end
end

----------------------------------------------------------------------
-- Help
----------------------------------------------------------------------

function WL:PrintHelp()
    local lines = {
        "|cff00ccffWebLoadouts|r v" .. self.version .. " — Commands:",
        "  |cff00ccff/wl|r or |cff00ccff/wl help|r — Show this help",
        "  |cff00ccff/wl show|r — Toggle the builds menu (talent window must be open)",
        "  |cff00ccff/wl add|r — Open the Add Import dialog",
        "  |cff00ccff/wl list|r — List all saved builds for current spec",
        "  |cff00ccff/wl export|r — Export current build to clipboard",
        "  |cff00ccff/wl delete <name>|r — Delete a saved build by name",
        "  |cff00ccff/wl clear|r — Delete all saved builds (with confirmation)",
        "  |cff00ccff/wl settings|r — Open settings",
        "  |cff00ccff/wl debug|r — Toggle debug messages",
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

----------------------------------------------------------------------
-- List builds
----------------------------------------------------------------------

function WL:ListSavedBuilds()
    local specID = self:GetPlayerSpecID()
    if not specID then
        WL:Print("Could not determine your current spec.")
        return
    end

    local specName = self.playerSpecName or "Unknown"
    WL:Print("Saved builds for |cff00ccff" .. specName .. "|r:")

    local builds = self:GetBuilds(specID)
    if #builds == 0 then
        WL:Print("  (none)")
        return
    end

    for i, entry in ipairs(builds) do
        local b = entry.build
        local srcInfo = self.SourceInfo[b.source]
        local srcName = srcInfo and (srcInfo.color .. srcInfo.name .. "|r") or b.source
        local ctInfo = self.ContentTypeInfo[b.contentType]
        local ctName = ctInfo and ctInfo.shortName or ""

        WL:Print(string.format("  %d. %s [%s] (%s)", i, b.name, srcName, ctName))
    end
end

----------------------------------------------------------------------
-- Delete build by name
----------------------------------------------------------------------

function WL:DeleteBuildByName(name)
    local nameLower = name:lower()
    local found = nil

    for id, build in pairs(self.db.userBuilds) do
        if build.name and build.name:lower() == nameLower then
            found = id
            break
        end
    end

    if not found then
        for id, build in pairs(self.db.userBuilds) do
            if build.name and build.name:lower():find(nameLower, 1, true) then
                found = id
                break
            end
        end
    end

    if found then
        local buildName = self.db.userBuilds[found].name
        self:DeleteBuild(found)
        WL:Print("Deleted: " .. buildName)
    else
        WL:Print("No build found matching: " .. name)
    end
end

----------------------------------------------------------------------
-- Confirm clear dialog
----------------------------------------------------------------------

StaticPopupDialogs["WEBLOADOUTS_CONFIRM_CLEAR"] = {
    text         = "Delete ALL saved WebLoadouts builds?\nThis cannot be undone.",
    button1      = "Delete All",
    button2      = "Cancel",
    OnAccept     = function()
        if WL.db then
            wipe(WL.db.userBuilds)
            WL:Print("All saved builds deleted.")
        end
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

----------------------------------------------------------------------
-- Confirm clear in-game loadouts dialog
----------------------------------------------------------------------

StaticPopupDialogs["WEBLOADOUTS_CONFIRM_CLEAR_LOADOUTS"] = {
    text         = "Delete ALL in-game talent loadouts for your current spec?\n\nYour active loadout will be preserved.\nWebLoadout builds and settings are not affected.\n\nThis cannot be undone.",
    button1      = "Delete All",
    button2      = "Cancel",
    OnAccept     = function()
        WL:ClearAllIngameLoadouts()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

----------------------------------------------------------------------
-- Settings (placeholder)
----------------------------------------------------------------------

function WL:OpenSettings()
    WL:Print("Settings panel coming soon! Current settings:")
    WL:Print("  autoStage: " .. tostring(self:GetSetting("autoStage")))
    WL:Print("  showButton: " .. tostring(self:GetSetting("showButton")))
    WL:Print("  showTooltips: " .. tostring(self:GetSetting("showTooltips")))
    WL:Print("  debug: " .. tostring(self:GetSetting("debug")))
end
