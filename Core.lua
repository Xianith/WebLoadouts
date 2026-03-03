----------------------------------------------------------------------
-- WebLoadouts — Core.lua
-- Addon bootstrap, event handling, talent frame hook
-- Follows the same pattern as QuickBuilds (known-working in 12.0)
----------------------------------------------------------------------

local ADDON_NAME, WL = ...

-- Public namespace
WL.name    = ADDON_NAME
WL.version = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.1.0"

-- Internal state
WL.playerClass    = nil
WL.playerClassID  = nil
WL.playerSpec     = nil
WL.playerSpecName = nil
WL.talentFrameReady = false

----------------------------------------------------------------------
-- Debug / Print helpers
----------------------------------------------------------------------

function WL:Print(...)
    -- Use print() like QuickBuilds does — proven reliable in WoW 12.0
    print("|cff00ccffWebLoadouts|r:", ...)
end

function WL:Debug(...)
    if WL.db and WL.db.settings and WL.db.settings.debug then
        print("|cff888888WL Debug|r:", ...)
    end
end

----------------------------------------------------------------------
-- Player info helpers
----------------------------------------------------------------------

function WL:UpdatePlayerInfo()
    local _, classFile, classID = UnitClass("player")
    self.playerClass   = classFile
    self.playerClassID = classID

    local specIndex = GetSpecialization()
    if specIndex then
        local specID, specName = GetSpecializationInfo(specIndex)
        self.playerSpec     = specID
        self.playerSpecName = specName
    end
end

function WL:GetPlayerSpecID()
    if not self.playerSpec then
        self:UpdatePlayerInfo()
    end
    return self.playerSpec
end

----------------------------------------------------------------------
-- Talent Frame Detection
----------------------------------------------------------------------

function WL:GetTalentFrame()
    if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then
        return PlayerSpellsFrame.TalentsFrame, PlayerSpellsFrame
    end
    if ClassTalentFrame then
        local tab = ClassTalentFrame.TalentsTab or ClassTalentFrame.TalentsFrame
        if tab then return tab, ClassTalentFrame end
    end
    return nil, nil
end

local function SetupTalentUI()
    if WL.talentFrameReady then return end
    if not PlayerSpellsFrame or not PlayerSpellsFrame.TalentsFrame then return end

    WL.talentFrameReady = true
    WL:UpdatePlayerInfo()
    WL:Debug("Talent frame detected — initializing UI")

    if WL.InitUI then
        WL:InitUI()
    end
end

----------------------------------------------------------------------
-- Event Frame — mirrors QuickBuilds' proven approach
----------------------------------------------------------------------

local f = CreateFrame("Frame")

-- Set the event handler FIRST, before RegisterEvent calls.
-- If RegisterEvent throws an error for an unknown event name,
-- we still need the handler to be in place for the other events.
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        WL:UpdatePlayerInfo()
        WL:InitStorage()
        WL:Print("v" .. WL.version .. " loaded. Type |cff00ccff/wl|r for help.")

    elseif event == "ADDON_LOADED" then
        if name == "Blizzard_PlayerSpells" then
            -- Same approach as QuickBuilds: wait 1s for the frame
            C_Timer.After(1, SetupTalentUI)
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        WL:UpdatePlayerInfo()
        if WL.talentFrameReady and WL.RefreshMenu then
            WL:RefreshMenu()
        end
    end
end)

-- Register events (these are guaranteed to exist)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

-- Spec change event — use pcall in case the name differs across WoW versions
if not pcall(f.RegisterEvent, f, "PLAYER_SPECIALIZATION_CHANGED") then
    pcall(f.RegisterEvent, f, "ACTIVE_PLAYER_CHANGED_SPECIALIZATION")
end
