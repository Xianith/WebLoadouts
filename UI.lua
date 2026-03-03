----------------------------------------------------------------------
-- WebLoadouts — UI.lua
-- Hooks into the native talent loadout dropdown to add web builds.
-- Uses Menu.ModifyMenu("MENU_CLASS_TALENT_PROFILE") for clean
-- integration — same method as Talent Tree Tweaks, Talent Loadout Mgr.
----------------------------------------------------------------------

local ADDON_NAME, WL = ...

local addImportFrame
local dropdownHooked = false

----------------------------------------------------------------------
-- Hook into the Talent Loadout Dropdown
----------------------------------------------------------------------

local function SetupDropdownHook()
    -- Menu.ModifyMenu is available in WoW 11.0+ (Blizzard_Menu framework)
    if not Menu or not Menu.ModifyMenu then
        WL:Debug("Menu.ModifyMenu not available — dropdown hook disabled")
        return false
    end

    Menu.ModifyMenu("MENU_CLASS_TALENT_PROFILE", function(owner, rootDescription, contextData)
        WL:OnLoadoutDropdownOpen(rootDescription)
    end)

    dropdownHooked = true
    WL:Debug("Hooked MENU_CLASS_TALENT_PROFILE dropdown")
    return true
end

----------------------------------------------------------------------
-- Tooltip helper (avoids duplication for hero/non-hero builds)
----------------------------------------------------------------------

local function AddBuildTooltip(btn, build, source, heroSpec)
    btn:SetTooltip(function(tooltip, desc)
        GameTooltip_SetTitle(tooltip, build.name)
        local srcInfo = WL.SourceInfo[source]
        if srcInfo then
            GameTooltip_AddNormalLine(tooltip, "Source: " .. srcInfo.name)
        end
        if heroSpec and heroSpec ~= "" then
            GameTooltip_AddNormalLine(tooltip, "Hero Spec: " .. heroSpec)
        end
        local ctInfo = WL.ContentTypeInfo[build.contentType]
        if ctInfo then
            GameTooltip_AddNormalLine(tooltip, "Type: " .. ctInfo.name)
        end
        if build.sourceUrl and build.sourceUrl ~= "" then
            GameTooltip_AddNormalLine(tooltip, "|cff888888" .. build.sourceUrl .. "|r")
        end
        if build.notes and build.notes ~= "" then
            GameTooltip_AddBlankLine(tooltip)
            GameTooltip_AddNormalLine(tooltip, build.notes)
        end
        GameTooltip_AddBlankLine(tooltip)
        GameTooltip_AddInstructionLine(tooltip, "Click to import this build")
    end)
end

----------------------------------------------------------------------
-- Populate the dropdown with web builds (grouped by hero spec)
----------------------------------------------------------------------

function WL:OnLoadoutDropdownOpen(rootDescription)
    self:UpdatePlayerInfo()
    local allBuilds = self:GetAllBuildsForCurrentSpec()
    local sourceOrder = { "wowhead", "archon", "icyveins" }

    -- Separator before web builds section
    rootDescription:CreateDivider()

    -- Add builds grouped by source, then by hero spec
    for _, source in ipairs(sourceOrder) do
        if self:IsSourceEnabled(source) then
            local builds = allBuilds[source]
            if builds and #builds > 0 then
                local srcInfo = WL.SourceInfo[source]
                local srcName = srcInfo and (srcInfo.color .. srcInfo.name .. "|r") or source

                -- Group builds by heroSpec
                local heroGroups = {}   -- heroSpec -> list of builds
                local heroOrder = {}    -- insertion-order of hero spec names
                local noHeroBuilds = {} -- builds without a hero spec

                for _, build in ipairs(builds) do
                    local hero = build.heroSpec or ""
                    if hero ~= "" then
                        if not heroGroups[hero] then
                            heroGroups[hero] = {}
                            table.insert(heroOrder, hero)
                        end
                        table.insert(heroGroups[hero], build)
                    else
                        table.insert(noHeroBuilds, build)
                    end
                end

                -- Create the source submenu
                local submenu = rootDescription:CreateButton(srcName)
                submenu:SetSelectionIgnored()

                -- Add hero spec sub-submenus
                for _, hero in ipairs(heroOrder) do
                    local heroMenu = submenu:CreateButton("|cffe0c050" .. hero .. "|r")
                    heroMenu:SetSelectionIgnored()

                    for _, build in ipairs(heroGroups[hero]) do
                        local btn = heroMenu:CreateButton(build.name, function()
                            WL:ImportBuild(build, source)
                            return MenuResponse and MenuResponse.CloseAll or nil
                        end)
                        AddBuildTooltip(btn, build, source, hero)
                    end
                end

                -- Separator between hero builds and non-hero builds
                if #heroOrder > 0 and #noHeroBuilds > 0 then
                    submenu:CreateDivider()
                end

                -- Add builds without hero spec directly under source
                for _, build in ipairs(noHeroBuilds) do
                    local btn = submenu:CreateButton(build.name, function()
                        WL:ImportBuild(build, source)
                        return MenuResponse and MenuResponse.CloseAll or nil
                    end)
                    AddBuildTooltip(btn, build, source, nil)
                end
            end
        end
    end

    -- WebLoadout Tools button at the bottom — opens standalone panel
    rootDescription:CreateDivider()
    local toolsBtn = rootDescription:CreateButton("|cff00ccffWebLoadout Tools|r", function()
        WL:ShowToolsPanel()
        return MenuResponse and MenuResponse.CloseAll or nil
    end)
    toolsBtn:SetSelectionIgnored()
end

----------------------------------------------------------------------
-- Import Build Handler
----------------------------------------------------------------------

function WL:ImportBuild(build, source)
    if not build or not build.talentString or build.talentString == "" then
        WL:Print("This build has no talent string.")
        return
    end

    local buildName = build.name or "WebBuild"

    -- Always use the Blizzard import dialog — reliable and avoids taint
    local success = self:ImportViaBuildDialog(build.talentString, buildName)
    if success then
        local srcInfo = source and WL.SourceInfo[source]
        local srcLabel = srcInfo and (" (" .. srcInfo.name .. ")") or ""
        WL:Print("Importing: " .. buildName .. srcLabel)
    end
end

----------------------------------------------------------------------
-- Tools Panel
----------------------------------------------------------------------

local toolsFrame

function WL:ShowToolsPanel()
    -- If already created, refresh toggle states and re-show
    if toolsFrame then
        self:RefreshToolsPanel()
        toolsFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "WebLoadoutsTools", UIParent, "BackdropTemplate")
    f:SetSize(420, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cff00ccffWebLoadout Tools|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Divider helper (thin horizontal line)
    local function CreateDivider(parent, anchor, yOffset)
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
        line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, yOffset)
        line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        return line
    end

    local yPos = -40 -- track vertical cursor

    ----------------------------------------------------------------
    -- Section 1: Source Toggles
    ----------------------------------------------------------------
    local toggleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toggleLabel:SetPoint("TOPLEFT", 16, yPos)
    toggleLabel:SetText("|cffe0c050Toggle Sources|r")

    yPos = yPos - 18
    local sourceOrder = { "wowhead", "archon", "icyveins" }
    f.toggleChecks = {} -- store references for refresh

    for _, src in ipairs(sourceOrder) do
        local srcInfo = WL.SourceInfo[src]
        if srcInfo then
            local row = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            row:SetPoint("TOPLEFT", 20, yPos)
            row:SetSize(26, 26)
            row:SetChecked(WL:IsSourceEnabled(src))

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", row, "RIGHT", 4, 0)
            label:SetText(srcInfo.color .. srcInfo.name .. "|r")

            row:SetScript("OnClick", function(self)
                local checked = self:GetChecked()
                if WL.db and WL.db.settings and WL.db.settings.enabledSources then
                    WL.db.settings.enabledSources[src] = checked
                end
                local state = checked and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
                WL:Print(srcInfo.name .. " builds " .. state)
            end)

            f.toggleChecks[src] = row
            yPos = yPos - 28
        end
    end

    local div1 = CreateDivider(f, toggleLabel, yPos - (-40) - 14)
    -- anchor divider relative to toggleLabel
    div1:ClearAllPoints()
    div1:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yPos - 4)
    div1:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    yPos = yPos - 12

    ----------------------------------------------------------------
    -- Section 2: Build Sources (URLs)
    ----------------------------------------------------------------
    local srcLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    srcLabel:SetPoint("TOPLEFT", 16, yPos)
    srcLabel:SetText("|cffe0c050Build Sources|r")

    yPos = yPos - 18
    f.urlBoxes = {} -- store references for refresh

    for _, src in ipairs(sourceOrder) do
        local srcInfo = WL.SourceInfo[src]
        if srcInfo then
            -- Source name label
            local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameLabel:SetPoint("TOPLEFT", 20, yPos)
            nameLabel:SetText(srcInfo.color .. srcInfo.name .. "|r")

            -- Copyable URL EditBox
            local urlBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
            urlBox:SetSize(280, 18)
            urlBox:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
            urlBox:SetFontObject("GameFontHighlightSmall")
            urlBox:SetAutoFocus(false)
            urlBox:SetMaxLetters(200)

            -- Default to generic domain URL
            local displayUrl = srcInfo.url or ""
            urlBox:SetText(displayUrl)

            -- Select-all on focus so user can copy
            urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            -- Prevent editing — re-set the text on any change
            urlBox:SetScript("OnTextChanged", function(self, userInput)
                if userInput then self:SetText(self.displayUrl or "") end
            end)
            urlBox.displayUrl = displayUrl

            f.urlBoxes[src] = urlBox
            yPos = yPos - 24
        end
    end

    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yPos - 4)
    div2:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    div2:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    yPos = yPos - 12

    ----------------------------------------------------------------
    -- Section 3: Last Synced
    ----------------------------------------------------------------
    local syncLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncLabel:SetPoint("TOPLEFT", 16, yPos)
    local syncTime = WL.DataLastSynced or "Never"
    syncLabel:SetText("|cff888888Last Synced:  |r" .. syncTime)
    f.syncLabel = syncLabel

    yPos = yPos - 20

    local div3 = f:CreateTexture(nil, "ARTWORK")
    div3:SetHeight(1)
    div3:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yPos - 4)
    div3:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    div3:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    yPos = yPos - 12

    ----------------------------------------------------------------
    -- Section 4: Clear All Loadouts
    ----------------------------------------------------------------
    local clearDesc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearDesc:SetPoint("TOPLEFT", 16, yPos)
    clearDesc:SetWidth(380)
    clearDesc:SetJustifyH("LEFT")
    clearDesc:SetText("|cffaaaaaaDeletes all in-game talent loadouts for your current spec. " ..
        "Your active loadout will be preserved. WebLoadout builds are NOT affected.|r")
    yPos = yPos - 36

    local clearAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(180, 28)
    clearAllBtn:SetPoint("TOPLEFT", 16, yPos)
    clearAllBtn:SetText("|cffff4444Clear All Loadouts|r")
    clearAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("WEBLOADOUTS_CONFIRM_CLEAR_LOADOUTS")
    end)

    ----------------------------------------------------------------
    -- Close button at bottom-right
    ----------------------------------------------------------------
    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(80, 26)
    doneBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    doneBtn:SetText("Close")
    doneBtn:SetScript("OnClick", function() f:Hide() end)

    toolsFrame = f
    f:Show()

    -- Populate URLs with spec-specific data
    self:RefreshToolsPanel()
end

----------------------------------------------------------------------
-- Refresh Tools Panel (update toggles, URLs for current spec)
----------------------------------------------------------------------

function WL:RefreshToolsPanel()
    if not toolsFrame then return end

    -- Update toggle checkboxes
    if toolsFrame.toggleChecks then
        for src, check in pairs(toolsFrame.toggleChecks) do
            check:SetChecked(WL:IsSourceEnabled(src))
        end
    end

    -- Update source URLs with spec-specific guide URLs
    if toolsFrame.urlBoxes then
        local allBuilds = self:GetAllBuildsForCurrentSpec()
        local sourceOrder = { "wowhead", "archon", "icyveins" }

        for _, src in ipairs(sourceOrder) do
            local urlBox = toolsFrame.urlBoxes[src]
            if urlBox then
                local srcInfo = WL.SourceInfo[src]
                local builds = allBuilds[src]
                local bestUrl = (srcInfo and srcInfo.url) or ""

                -- Pick the first unique sourceUrl from builds for this source
                if builds then
                    for _, build in ipairs(builds) do
                        if build.sourceUrl and build.sourceUrl ~= "" then
                            bestUrl = build.sourceUrl
                            break
                        end
                    end
                end

                urlBox.displayUrl = bestUrl
                urlBox:SetText(bestUrl)
            end
        end
    end

    -- Update last synced
    if toolsFrame.syncLabel then
        local syncTime = WL.DataLastSynced or "Never"
        toolsFrame.syncLabel:SetText("|cff888888Last Synced:  |r" .. syncTime)
    end
end

----------------------------------------------------------------------
-- Add Import Dialog
----------------------------------------------------------------------

function WL:ShowAddImportDialog()
    if addImportFrame then
        addImportFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "WebLoadoutsAddImport", UIParent, "BackdropTemplate")
    f:SetSize(460, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cff00ccffAdd Import|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Name input
    local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 16, -40)
    nameLabel:SetText("Build Name:")

    local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    nameBox:SetSize(420, 22)
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -4)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(60)

    -- Source selector
    local sourceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sourceLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -4, -12)
    sourceLabel:SetText("Source:")

    local sources = { "wowhead", "icyveins", "archon", "manual" }
    local sourceButtons = {}
    local selectedSource = "manual"

    local function UpdateSourceButtons()
        for _, btn in pairs(sourceButtons) do
            if btn.sourceKey == selectedSource then
                btn:SetBackdropBorderColor(0, 0.8, 1, 1)
                btn.text:SetTextColor(1, 1, 1, 1)
            else
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
                btn.text:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    end

    local prevBtn = nil
    for _, src in ipairs(sources) do
        local info = WL.SourceInfo[src]
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(82, 24)
        btn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true, tileSize = 8, edgeSize = 12,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropColor(0.15, 0.15, 0.2, 0.8)
        btn.sourceKey = src

        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", sourceLabel, "BOTTOMLEFT", 4, -4)
        end

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("CENTER")
        t:SetText(info.name)
        btn.text = t

        btn:SetScript("OnClick", function()
            selectedSource = src
            UpdateSourceButtons()
        end)

        sourceButtons[src] = btn
        prevBtn = btn
    end

    -- Content type selector
    local ctLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ctLabel:SetPoint("TOPLEFT", sourceButtons[sources[1]], "BOTTOMLEFT", -4, -12)
    ctLabel:SetText("Content Type:")

    local contentTypes = { "raid", "mythicplus", "pvp", "delves", "general" }
    local ctButtons = {}
    local selectedCT = "general"

    local function UpdateCTButtons()
        for _, btn in pairs(ctButtons) do
            if btn.ctKey == selectedCT then
                btn:SetBackdropBorderColor(0, 0.8, 1, 1)
                btn.text:SetTextColor(1, 1, 1, 1)
            else
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
                btn.text:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    end

    prevBtn = nil
    for _, ct in ipairs(contentTypes) do
        local info = WL.ContentTypeInfo[ct]
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(68, 24)
        btn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true, tileSize = 8, edgeSize = 12,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropColor(0.15, 0.15, 0.2, 0.8)
        btn.ctKey = ct

        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", ctLabel, "BOTTOMLEFT", 4, -4)
        end

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("CENTER")
        t:SetText(info.shortName)
        btn.text = t

        btn:SetScript("OnClick", function()
            selectedCT = ct
            UpdateCTButtons()
        end)

        ctButtons[ct] = btn
        prevBtn = btn
    end

    -- Talent string input
    local strLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    strLabel:SetPoint("TOPLEFT", ctButtons[contentTypes[1]], "BOTTOMLEFT", -4, -12)
    strLabel:SetText("Talent String (paste here):")

    local strScrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate, BackdropTemplate")
    strScrollFrame:SetSize(420, 60)
    strScrollFrame:SetPoint("TOPLEFT", strLabel, "BOTTOMLEFT", 4, -4)
    strScrollFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    strScrollFrame:SetBackdropColor(0, 0, 0, 0.5)
    strScrollFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local strBox = CreateFrame("EditBox", nil, strScrollFrame)
    strBox:SetFontObject("ChatFontNormal")
    strBox:SetWidth(400)
    strBox:SetAutoFocus(false)
    strBox:SetMultiLine(true)
    strBox:SetMaxLetters(500)
    strScrollFrame:SetScrollChild(strBox)
    strBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Last Synced info
    local syncLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncLabel:SetPoint("TOPLEFT", strScrollFrame, "BOTTOMLEFT", 0, -8)
    local syncTime = WL.DataLastSynced or "Never"
    syncLabel:SetText("|cff888888Last synced: " .. syncTime .. "|r")

    -- Save button
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 26)
    saveBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    saveBtn:SetText("Save Build")
    saveBtn:SetScript("OnClick", function()
        local bName = strtrim(nameBox:GetText())
        local bString = strtrim(strBox:GetText())

        if bName == "" then
            WL:Print("Please enter a build name.")
            return
        end
        if bString == "" then
            WL:Print("Please paste a talent string.")
            return
        end

        local valid, err = WL:IsValidTalentString(bString)
        if not valid then
            WL:Print("Invalid talent string: " .. (err or "unknown"))
            return
        end

        WL:SaveBuild(bName, bString, selectedSource, selectedCT)
        WL:Print("Saved: " .. bName)

        nameBox:SetText("")
        strBox:SetText("")
        f:Hide()
    end)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 26)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    UpdateSourceButtons()
    UpdateCTButtons()

    addImportFrame = f
    f:Show()
end

----------------------------------------------------------------------
-- ToggleMenu (for /wl show command — opens the talent dropdown)
----------------------------------------------------------------------

function WL:ToggleMenu()
    if dropdownHooked then
        -- The builds are in the native dropdown — just tell the user
        WL:Print("Web builds are in the talent loadout dropdown. Open talents (N) and click the loadout dropdown.")
    else
        WL:Print("Dropdown hook not active. Try opening talents (N) first.")
    end
end

----------------------------------------------------------------------
-- RefreshMenu (called from Core.lua on spec change)
-- With Menu.ModifyMenu, the dropdown rebuilds automatically
----------------------------------------------------------------------

function WL:RefreshMenu()
    -- No-op: the Menu.ModifyMenu callback fires every time
    -- the dropdown opens, so it always shows current spec data.
end

----------------------------------------------------------------------
-- Initialize UI (called from Core.lua when talent frame loads)
----------------------------------------------------------------------

function WL:InitUI()
    WL:Debug("Initializing UI")

    -- Hook the native talent loadout dropdown
    local hooked = SetupDropdownHook()
    if hooked then
        WL:Debug("Dropdown hook active — web builds in loadout dropdown")
    else
        WL:Debug("Dropdown hook FAILED — Menu.ModifyMenu not available")
        WL:Print("Warning: Could not hook talent dropdown. Use |cff00ccff/wl add|r to import builds manually.")
    end

    WL:Debug("UI initialization complete")
end
