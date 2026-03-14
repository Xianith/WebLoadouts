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
            murlok   = true,
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

    -- Ensure SourceInfo has all required entries (manual, etc.)
    self:EnsureSourceInfo()
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

    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local deleted = 0
    local skipped = 0

    -- Only delete loadouts whose name starts with "WL - " (WebLoadouts imports).
    -- Delete one config per frame to let the game process each deletion.
    -- Re-fetch the config list each iteration to avoid stale references.
    local function DeleteNext()
        local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)
        if not configIDs then return end

        for _, configID in ipairs(configIDs) do
            if configID == activeConfigID then
                -- Never delete the active loadout
                skipped = skipped + 1
            else
                -- Check if the loadout name starts with "WL - "
                local configInfo = C_Traits.GetConfigInfo(configID)
                local configName = configInfo and configInfo.name or ""
                if configName:sub(1, 5) == "WL - " then
                    local ok, err = pcall(C_ClassTalents.DeleteConfig, configID)
                    if ok then
                        deleted = deleted + 1
                        C_Timer.After(0, DeleteNext)
                        return
                    else
                        WL:Debug("Failed to delete config " .. configID .. ": " .. tostring(err))
                    end
                else
                    skipped = skipped + 1
                end
            end
        end

        -- No more deletable WL configs — report results
        if deleted > 0 then
            WL:Print("Deleted " .. deleted .. " WL loadout(s).")
        else
            WL:Print("No WL loadouts found to delete.")
        end
    end

    DeleteNext()
end

----------------------------------------------------------------------
-- Ensure SourceInfo always has a "manual" entry
-- (Data.lua is auto-synced and may not include it)
----------------------------------------------------------------------

function WL:EnsureSourceInfo()
    if not self.SourceInfo then self.SourceInfo = {} end
    if not self.SourceInfo["manual"] then
        self.SourceInfo["manual"] = {
            name  = "Manual",
            color = "|cffcccccc",
            icon  = "Interface\\Icons\\INV_Misc_Note_01",
            url   = "",
        }
    end
end

----------------------------------------------------------------------
-- Bundled + user build accessors
-- (live here so Data.lua can be replaced without losing these)
----------------------------------------------------------------------

function WL:GetBundledBuilds(specID, source)
    local builds = self.BundledBuilds and self.BundledBuilds[specID]
    if not builds then return {} end
    if not source then return builds end
    local filtered = {}
    for _, build in ipairs(builds) do
        if build.source == source then
            table.insert(filtered, build)
        end
    end
    return filtered
end

function WL:GetAllBuildsForCurrentSpec()
    local specID = self:GetPlayerSpecID()
    local result = {}
    if not specID then return result end

    -- Bundled builds from Data.lua
    local bundled = self.BundledBuilds and self.BundledBuilds[specID] or {}
    for _, build in ipairs(bundled) do
        local src = build.source or "manual"
        if not result[src] then result[src] = {} end
        table.insert(result[src], {
            name          = build.name,
            talentString  = build.talentString,
            contentType   = build.contentType or "general",
            heroSpec      = build.heroSpec or "",
            sourceUrl     = build.sourceUrl or "",
            notes         = build.notes or "",
        })
    end

    -- User-saved builds from SavedVariables
    if self.db and self.db.userBuilds then
        for _, entry in pairs(self.db.userBuilds) do
            if entry.specID == specID then
                local src = entry.source or "manual"
                if not result[src] then result[src] = {} end
                table.insert(result[src], {
                    name          = entry.name or "Unnamed",
                    talentString  = entry.talentString,
                    contentType   = entry.contentType or "general",
                    heroSpec      = entry.heroSpec or "",
                    sourceUrl     = entry.sourceUrl or "",
                    notes         = entry.notes or "",
                })
            end
        end
    end

    return result
end
