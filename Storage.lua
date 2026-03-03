----------------------------------------------------------------------
-- WebLoadouts — Storage.lua
-- SavedVariables management, defaults, and data access
----------------------------------------------------------------------

local ADDON_NAME, WL = ...

----------------------------------------------------------------------
-- Default database structure
----------------------------------------------------------------------

local DB_VERSION = 1

local DB_DEFAULTS = {
    version = DB_VERSION,
    userBuilds = {},
    settings = {
        showButton       = true,
        buttonPosition   = "RIGHT",
        autoStage        = true,
        showSourceIcons  = true,
        showTooltips     = true,
        debug            = false,
        enabledSources   = {
            wowhead  = true,
            icyveins = true,
            archon   = true,
            manual   = true,
        },
    },
}

----------------------------------------------------------------------
-- Initialize / load saved variables
----------------------------------------------------------------------

function WL:InitStorage()
    if not WebLoadoutsDB then
        WebLoadoutsDB = CopyTable(DB_DEFAULTS)
        WL:Debug("Created fresh database")
    end

    self.db = WebLoadoutsDB

    -- Migration: ensure all default keys exist
    if not self.db.version then
        self.db.version = DB_VERSION
    end
    if not self.db.userBuilds then
        self.db.userBuilds = {}
    end
    if not self.db.settings then
        self.db.settings = CopyTable(DB_DEFAULTS.settings)
    else
        for k, v in pairs(DB_DEFAULTS.settings) do
            if self.db.settings[k] == nil then
                self.db.settings[k] = v
            end
        end
        if not self.db.settings.enabledSources then
            self.db.settings.enabledSources = CopyTable(DB_DEFAULTS.settings.enabledSources)
        end
    end

    if self.db.version < DB_VERSION then
        self:MigrateDB(self.db.version, DB_VERSION)
        self.db.version = DB_VERSION
    end
end

----------------------------------------------------------------------
-- Migration
----------------------------------------------------------------------

function WL:MigrateDB(fromVersion, toVersion)
    WL:Debug("Migrating DB from v" .. fromVersion .. " to v" .. toVersion)
end

----------------------------------------------------------------------
-- Build CRUD operations
----------------------------------------------------------------------

local buildIDCounter = 0

local function GenerateBuildID()
    buildIDCounter = buildIDCounter + 1
    return "user-" .. time() .. "-" .. buildIDCounter
end

function WL:SaveBuild(name, talentString, source, contentType, notes)
    local specID = self:GetPlayerSpecID()
    local id = GenerateBuildID()

    self.db.userBuilds[id] = {
        name          = name or "Unnamed Build",
        source        = source or "manual",
        specID        = specID,
        classID       = self.playerClassID,
        talentString  = talentString,
        contentType   = contentType or "general",
        dateAdded     = time(),
        notes         = notes or "",
    }

    WL:Debug("Saved build:", id, name)
    return id
end

function WL:UpdateBuild(id, fields)
    local build = self.db.userBuilds[id]
    if not build then return false end

    for k, v in pairs(fields) do
        build[k] = v
    end
    build.dateModified = time()
    return true
end

function WL:DeleteBuild(id)
    if self.db.userBuilds[id] then
        local name = self.db.userBuilds[id].name
        self.db.userBuilds[id] = nil
        WL:Debug("Deleted build:", id, name)
        return true
    end
    return false
end

function WL:GetBuild(id)
    return self.db.userBuilds[id]
end

function WL:GetBuilds(specID, source)
    local results = {}
    for id, build in pairs(self.db.userBuilds) do
        local matchSpec   = (specID == nil) or (build.specID == specID)
        local matchSource = (source == nil) or (build.source == source)
        if matchSpec and matchSource then
            table.insert(results, { id = id, build = build })
        end
    end
    table.sort(results, function(a, b)
        return (a.build.name or "") < (b.build.name or "")
    end)
    return results
end

function WL:GetBuildCount()
    local count = 0
    for _ in pairs(self.db.userBuilds) do
        count = count + 1
    end
    return count
end

----------------------------------------------------------------------
-- Settings helpers
----------------------------------------------------------------------

function WL:GetSetting(key)
    return self.db and self.db.settings and self.db.settings[key]
end

function WL:SetSetting(key, value)
    if self.db and self.db.settings then
        self.db.settings[key] = value
    end
end

function WL:IsSourceEnabled(source)
    if not self.db or not self.db.settings or not self.db.settings.enabledSources then
        return true
    end
    return self.db.settings.enabledSources[source] ~= false
end

----------------------------------------------------------------------
-- Clear all in-game (Blizzard) talent loadouts for the current spec
----------------------------------------------------------------------

function WL:ClearAllIngameLoadouts()
    if InCombatLockdown() then
        WL:Print("Cannot delete loadouts while in combat.")
        return
    end

    local specID = self:GetPlayerSpecID()
    if not specID then
        WL:Print("Could not determine your current spec.")
        return
    end

    -- Get all config IDs for this spec
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)
    if not configIDs or #configIDs == 0 then
        WL:Print("No loadouts found to delete.")
        return
    end

    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local deleted = 0
    local skippedActive = false

    for _, configID in ipairs(configIDs) do
        if configID == activeConfigID then
            -- Cannot delete the currently active loadout
            skippedActive = true
        else
            local ok, err = pcall(C_ClassTalents.DeleteConfig, configID)
            if ok then
                deleted = deleted + 1
            else
                WL:Debug("Failed to delete config " .. configID .. ": " .. tostring(err))
            end
        end
    end

    if deleted > 0 then
        WL:Print("Deleted " .. deleted .. " loadout(s).")
    else
        WL:Print("No loadouts were deleted.")
    end

    if skippedActive then
        WL:Print("|cffffffYour active loadout was preserved.|r")
    end
end
