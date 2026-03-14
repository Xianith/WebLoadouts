----------------------------------------------------------------------
-- WebLoadouts - ImportExport.lua
-- Talent string validation, spec detection, and import orchestration.
-- Import approach copied from QuickBuilds (confirmed working in 12.0).
----------------------------------------------------------------------

local ADDON_NAME, WL = ...

----------------------------------------------------------------------
-- Talent string validation
----------------------------------------------------------------------

function WL:IsValidTalentString(talentString)
    if not talentString or type(talentString) ~= "string" then
        return false, "No string provided"
    end

    talentString = strtrim(talentString)

    if #talentString < 10 then
        return false, "String too short"
    end

    if #talentString > 500 then
        return false, "String too long"
    end

    -- Icy Veins HB hash format starts with #
    if talentString:sub(1, 1) == "#" then
        -- HB hash: alphanumeric plus # - : + ( )
        if talentString:match("[^A-Za-z0-9#%-:+/=_()%|]") then
            return false, "Invalid characters in HB hash string"
        end
        return true, nil
    end

    -- Blizzard base64 variant: A-Z, a-z, 0-9, +, /
    if talentString:match("[^A-Za-z0-9%+/=]") then
        return false, "Invalid characters detected"
    end

    return true, nil
end

----------------------------------------------------------------------
-- Import via Blizzard's Import Dialog
-- Mirrors QuickBuilds' InjectIntoBlizzard() exactly.
----------------------------------------------------------------------

function WL:ImportViaBuildDialog(talentString, buildName)
    if not talentString or talentString == "" then
        WL:Print("No talent string to import.")
        return false
    end

    if InCombatLockdown() then
        WL:Print("Cannot import while in combat.")
        return false
    end

    -- Force-load the talent UI if needed (same as QuickBuilds)
    if not PlayerSpellsFrame then
        pcall(UIParentLoadAddOn, "Blizzard_PlayerSpells")
    end

    local dialog = ClassTalentLoadoutImportDialog
    if not dialog then
        WL:Print("Import dialog not available. Open talents (N) first.")
        return false
    end

    -- Open the dialog
    dialog:ShowDialog()

    -- Set the talent string immediately (no timer - matches QuickBuilds)
    local importBox = dialog.ImportControl
                  and dialog.ImportControl.InputContainer
                  and dialog.ImportControl.InputContainer.EditBox
    local nameBox = dialog.NameControl
                and dialog.NameControl.EditBox

    if importBox then
        importBox:SetText(talentString)
    else
        WL:Debug("Could not find import editbox")
        return false
    end

    if nameBox and buildName then
        -- Prefix with "WL - " so we can identify WebLoadout imports later
        local prefixedName = "WL - " .. buildName
        nameBox:SetText(prefixedName)
    end

    WL:Debug("Import dialog opened with pre-filled string")
    return true
end

----------------------------------------------------------------------
-- Direct staging — stages the build in the talent tree without the
-- import dialog.  The user sees the changes and clicks Apply Changes.
-- Falls back to the Blizzard dialog if staging fails.
----------------------------------------------------------------------

function WL:StageBuild(talentString)
    if InCombatLockdown() then return false end

    -- Try multiple known talent frame references
    local talentsTab = (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame)
                    or (ClassTalentFrame and (ClassTalentFrame.TalentsTab or ClassTalentFrame.TalentsFrame))
    if not talentsTab then
        WL:Debug("StageBuild: no talent frame found")
        return false
    end

    -- Try ImportLoadout (stages the build in the tree, user clicks Apply)
    if talentsTab.ImportLoadout then
        local success, err = pcall(function()
            talentsTab:ImportLoadout(talentString)
        end)
        if success then
            WL:Debug("Build staged successfully via ImportLoadout")
            return true
        else
            WL:Debug("ImportLoadout error: " .. tostring(err))
        end
    else
        WL:Debug("StageBuild: ImportLoadout not found on talent frame")
    end

    return false
end

----------------------------------------------------------------------
-- StageImport — one-click import from the dropdown menu.
-- Tries direct staging first, falls back to the Blizzard import dialog.
----------------------------------------------------------------------

function WL:StageImport(talentString, buildName, source)
    if not talentString or talentString == "" then
        WL:Print("No talent string to import.")
        return false
    end

    if InCombatLockdown() then
        WL:Print("Cannot import while in combat.")
        return false
    end

    -- Force-load the talent UI if it hasn't been loaded yet
    if not PlayerSpellsFrame then
        pcall(UIParentLoadAddOn, "Blizzard_PlayerSpells")
    end

    -- Try direct staging first (the talent frame should already be open
    -- since the user clicked the dropdown from within it)
    local staged = self:StageBuild(talentString)
    if staged then
        local srcInfo = source and WL.SourceInfo[source]
        local srcLabel = srcInfo and (" (" .. srcInfo.name .. ")") or ""
        WL:Print("Staged: " .. (buildName or "WebBuild") .. srcLabel .. " — click |cff00ff00Apply Changes|r")
        return true
    end

    -- Fallback: open the Blizzard import dialog with pre-filled data
    WL:Debug("StageImport: staging failed, falling back to Blizzard dialog")
    local success = self:ImportViaBuildDialog(talentString, buildName)
    if success then
        local srcInfo = source and WL.SourceInfo[source]
        local srcLabel = srcInfo and (" (" .. srcInfo.name .. ")") or ""
        WL:Print("Importing: " .. (buildName or "WebBuild") .. srcLabel)
    else
        WL:Print("|cffff4444Import failed.|r Try opening talents (N) first, then use the dropdown.")
    end
    return success
end

----------------------------------------------------------------------
-- Clipboard helper
----------------------------------------------------------------------

function WL:CopyToClipboard(text)
    if not text then return end

    if not self.clipboardFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(1, 1)
        f:SetPoint("TOPLEFT", -9999, 9999)

        local editBox = CreateFrame("EditBox", nil, f)
        editBox:SetSize(1, 1)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
        editBox:SetFontObject(ChatFontNormal)

        self.clipboardFrame = editBox
    end

    self.clipboardFrame:SetText(text)
    self.clipboardFrame:HighlightText()
    self.clipboardFrame:SetFocus()

    C_Timer.After(0.1, function()
        if self.clipboardFrame:HasFocus() then
            self.clipboardFrame:ClearFocus()
        end
    end)
end

----------------------------------------------------------------------
-- Export current build
----------------------------------------------------------------------

function WL:ExportCurrentBuild()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        WL:Print("No active talent configuration found.")
        return nil
    end

    local exportString = C_Traits.GenerateImportString(configID)
    if not exportString or exportString == "" then
        WL:Print("Failed to generate export string.")
        return nil
    end

    return exportString
end
