VariableBunker = VariableBunker or {}

local Bunker = VariableBunker

local SETTINGS_ROOT = "VariableBunkerSettings"
local SETTINGS_KEY = SETTINGS_ROOT .. ".construction"
local DISPLAY_KEY = SETTINGS_ROOT .. ".display"
local DEBUG_KEY = SETTINGS_ROOT .. ".debug"
local SETTINGS_VERSION = 6

local DEBUG_SETTINGS = {
    { key = "enabled", attribute = "enabled", default = false },
    { key = "extraction", attribute = "logExtraction", default = true },
    { key = "filling", attribute = "logFilling", default = true },
    { key = "stations", attribute = "logStations", default = true },
    { key = "compaction", attribute = "logCompaction", default = true },
    { key = "dump", attribute = "heightDumps", default = true },
    { key = "overlay", attribute = "showOverlay", default = true },
}

local function getDefaultDebugSettings()
    local debugOutput = {}
    for _, entry in ipairs(DEBUG_SETTINGS) do
        debugOutput[entry.key] = entry.default
    end
    return debugOutput
end

Bunker.settings = Bunker.settings
    or {
        allowWallHeightsAboveFourMeters = true,
        allowInputStation = true,
        allowOutputStation = true,
        allowCompactionService = true,
        compactionPriceFactor = 1,
        showInfoBox = true,
        debugOutput = getDefaultDebugSettings(),
    }

function Bunker.getIsDebugActive(category)
    local debugOutput = Bunker.settings.debugOutput
    return debugOutput ~= nil and debugOutput.enabled == true and (category == nil or debugOutput[category] ~= false)
end

function Bunker.debugLog(category, text, ...)
    Logging.info("[VariableBunker][Debug][%s] " .. text, category, ...)
end

local MIN_COMPACTION_PRICE_FACTOR = 0
local MAX_COMPACTION_PRICE_FACTOR = 10

local function getCompactionPriceFactor(value)
    return math.clamp(tonumber(value) or 1, MIN_COMPACTION_PRICE_FACTOR, MAX_COMPACTION_PRICE_FACTOR)
end

local function getSettingsFilename()
    if getUserProfileAppPath == nil then
        return nil
    end

    local settingsDirectory = getUserProfileAppPath() .. "modSettings"
    if createFolder ~= nil then
        createFolder(settingsDirectory)
    end
    return settingsDirectory .. "/FS25_VariableBunker.xml"
end

local function writeSettingsFile(filename)
    if filename == nil then
        return false
    end

    local xmlFile = createXMLFile("VariableBunkerSettingsWrite", filename, SETTINGS_ROOT)
    if xmlFile == nil or xmlFile == 0 then
        return false
    end

    setXMLInt(xmlFile, SETTINGS_ROOT .. "#version", SETTINGS_VERSION)
    setXMLBool(
        xmlFile,
        SETTINGS_KEY .. "#allowWallHeightsAboveFourMeters",
        Bunker.settings.allowWallHeightsAboveFourMeters == true
    )
    setXMLBool(xmlFile, SETTINGS_KEY .. "#allowInputStation", Bunker.settings.allowInputStation == true)
    setXMLBool(xmlFile, SETTINGS_KEY .. "#allowOutputStation", Bunker.settings.allowOutputStation == true)
    setXMLBool(xmlFile, SETTINGS_KEY .. "#allowCompactionService", Bunker.settings.allowCompactionService == true)
    setXMLInt(
        xmlFile,
        SETTINGS_KEY .. "#compactionPricePercent",
        math.floor(Bunker.settings.compactionPriceFactor * 100 + 0.5)
    )
    setXMLBool(xmlFile, DISPLAY_KEY .. "#showInfoBox", Bunker.settings.showInfoBox == true)
    for _, entry in ipairs(DEBUG_SETTINGS) do
        setXMLBool(xmlFile, DEBUG_KEY .. "#" .. entry.attribute, Bunker.settings.debugOutput[entry.key] == true)
    end
    saveXMLFile(xmlFile)
    delete(xmlFile)
    return true
end

function Bunker.applyHeightSettingToStoreItems()
    if g_storeManager == nil or g_storeManager.getItems == nil then
        return
    end

    for _, storeItem in ipairs(g_storeManager:getItems()) do
        local configurations = storeItem.configurations
        local heightItems = configurations ~= nil and configurations[Bunker.CONFIG_HEIGHT] or nil
        if heightItems ~= nil then
            for _, item in ipairs(heightItems) do
                local baseSelectable = item.variableBunkerBaseSelectable
                if baseSelectable == nil then
                    baseSelectable = item.isSelectable ~= false
                    item.variableBunkerBaseSelectable = baseSelectable
                end
                item.isSelectable = baseSelectable
                    and (Bunker.settings.allowWallHeightsAboveFourMeters or (tonumber(item.meters) or 0) <= 4)
            end
        end
    end
end

function Bunker.applyStationSettingsToStoreItems()
    if g_storeManager == nil or g_storeManager.getItems == nil then
        return
    end
    for _, storeItem in ipairs(g_storeManager:getItems()) do
        local configurations = storeItem.configurations
        for configName, enabled in pairs({
            [Bunker.CONFIG_INPUT] = Bunker.settings.allowInputStation,
            [Bunker.CONFIG_OUTPUT] = Bunker.settings.allowOutputStation,
        }) do
            local items = configurations ~= nil and configurations[configName] or nil
            if items ~= nil then
                for _, item in ipairs(items) do
                    local baseSelectable = item.variableBunkerBaseSelectable
                    if baseSelectable == nil then
                        baseSelectable = item.isSelectable ~= false
                        item.variableBunkerBaseSelectable = baseSelectable
                    end
                    item.isSelectable = baseSelectable and (enabled or item.side == "off")
                end
            end
        end
        local compactionItems = configurations ~= nil and configurations[Bunker.CONFIG_COMPACTION] or nil
        if compactionItems ~= nil then
            for _, item in ipairs(compactionItems) do
                local baseSelectable = item.variableBunkerBaseSelectable
                if baseSelectable == nil then
                    baseSelectable = item.isSelectable ~= false
                    item.variableBunkerBaseSelectable = baseSelectable
                end
                item.isSelectable = baseSelectable and (Bunker.settings.allowCompactionService or item.saveId == "off")
            end
        end
    end
end

function Bunker.applySettings(settings)
    Bunker.settings.allowWallHeightsAboveFourMeters = settings ~= nil
        and settings.allowWallHeightsAboveFourMeters == true
    Bunker.settings.allowInputStation = settings == nil or settings.allowInputStation ~= false
    Bunker.settings.allowOutputStation = settings == nil or settings.allowOutputStation ~= false
    Bunker.settings.allowCompactionService = settings == nil or settings.allowCompactionService ~= false
    Bunker.settings.compactionPriceFactor = getCompactionPriceFactor(settings ~= nil and settings.compactionPriceFactor)
    if settings ~= nil and settings.showInfoBox ~= nil then
        Bunker.settings.showInfoBox = settings.showInfoBox == true
    end
    if settings ~= nil and settings.debugOutput ~= nil then
        Bunker.settings.debugOutput = getDefaultDebugSettings()
        for _, entry in ipairs(DEBUG_SETTINGS) do
            if settings.debugOutput[entry.key] ~= nil then
                Bunker.settings.debugOutput[entry.key] = settings.debugOutput[entry.key] == true
            end
        end
    end
    Bunker.applyHeightSettingToStoreItems()
    Bunker.applyStationSettingsToStoreItems()
    if Bunker.activeSilos ~= nil then
        for placeable in pairs(Bunker.activeSilos) do
            if placeable.VariableBunkerRefreshStationState ~= nil then
                placeable:VariableBunkerRefreshStationState()
            end
        end
    end
end

function Bunker.loadSettings()
    local filename = getSettingsFilename()
    if filename == nil then
        return false
    end

    Bunker.applySettings({
        allowWallHeightsAboveFourMeters = true,
        allowInputStation = true,
        allowOutputStation = true,
        allowCompactionService = true,
        compactionPriceFactor = 1,
        showInfoBox = true,
        debugOutput = getDefaultDebugSettings(),
    })
    if fileExists == nil or not fileExists(filename) then
        return writeSettingsFile(filename)
    end

    local xmlFile = loadXMLFile("VariableBunkerSettingsRead", filename)
    if xmlFile == nil or xmlFile == 0 then
        Logging.warning("[VariableBunker] Could not load modSettings file '%s'", filename)
        return false
    end

    local allowHigherWalls = getXMLBool(xmlFile, SETTINGS_KEY .. "#allowWallHeightsAboveFourMeters")
    local allowInputStation = getXMLBool(xmlFile, SETTINGS_KEY .. "#allowInputStation")
    local allowOutputStation = getXMLBool(xmlFile, SETTINGS_KEY .. "#allowOutputStation")
    local allowCompactionService = getXMLBool(xmlFile, SETTINGS_KEY .. "#allowCompactionService")
    local compactionPricePercent = getXMLInt(xmlFile, SETTINGS_KEY .. "#compactionPricePercent")
    local compactionPriceFactor = getXMLFloat(xmlFile, SETTINGS_KEY .. "#compactionPriceFactor")
    if compactionPricePercent ~= nil then
        compactionPriceFactor = compactionPricePercent / 100
    end
    local showInfoBox = getXMLBool(xmlFile, DISPLAY_KEY .. "#showInfoBox")
    local debugOutput = {}
    for _, entry in ipairs(DEBUG_SETTINGS) do
        debugOutput[entry.key] = getXMLBool(xmlFile, DEBUG_KEY .. "#" .. entry.attribute)
    end
    delete(xmlFile)
    Bunker.applySettings({
        allowWallHeightsAboveFourMeters = allowHigherWalls == nil or allowHigherWalls == true,
        allowInputStation = allowInputStation == nil or allowInputStation == true,
        allowOutputStation = allowOutputStation == nil or allowOutputStation == true,
        allowCompactionService = allowCompactionService == nil or allowCompactionService == true,
        compactionPriceFactor = compactionPriceFactor,
        showInfoBox = showInfoBox == nil or showInfoBox == true,
        debugOutput = debugOutput,
    })
    if Bunker.getIsDebugActive() then
        local categories = {}
        for _, entry in ipairs(DEBUG_SETTINGS) do
            if entry.key ~= "enabled" and Bunker.settings.debugOutput[entry.key] then
                table.insert(categories, entry.key)
            end
        end
        Bunker.debugLog("settings", "debug output enabled: %s", table.concat(categories, ", "))
    end
    if not writeSettingsFile(filename) then
        Logging.warning("[VariableBunker] Could not update modSettings file '%s'", filename)
        return false
    end
    return true
end

local VariableBunkerSettingsEvent = {}
local VariableBunkerSettingsEvent_mt = Class(VariableBunkerSettingsEvent, Event)
InitEventClass(VariableBunkerSettingsEvent, "VariableBunkerSettingsEvent")

function VariableBunkerSettingsEvent.emptyNew()
    return Event.new(VariableBunkerSettingsEvent_mt)
end

function VariableBunkerSettingsEvent.new(settings)
    local self = VariableBunkerSettingsEvent.emptyNew()
    self.allowWallHeightsAboveFourMeters = settings.allowWallHeightsAboveFourMeters == true
    self.allowInputStation = settings.allowInputStation == true
    self.allowOutputStation = settings.allowOutputStation == true
    self.allowCompactionService = settings.allowCompactionService == true
    self.compactionPriceFactor = settings.compactionPriceFactor or 1
    return self
end

function VariableBunkerSettingsEvent:readStream(streamId, connection)
    self.allowWallHeightsAboveFourMeters = streamReadBool(streamId)
    self.allowInputStation = streamReadBool(streamId)
    self.allowOutputStation = streamReadBool(streamId)
    self.allowCompactionService = streamReadBool(streamId)
    self.compactionPriceFactor = streamReadFloat32(streamId)
    self:run(connection)
end

function VariableBunkerSettingsEvent:writeStream(streamId, _connection)
    streamWriteBool(streamId, self.allowWallHeightsAboveFourMeters)
    streamWriteBool(streamId, self.allowInputStation)
    streamWriteBool(streamId, self.allowOutputStation)
    streamWriteBool(streamId, self.allowCompactionService)
    streamWriteFloat32(streamId, self.compactionPriceFactor)
end

function VariableBunkerSettingsEvent:run(connection)
    if connection ~= nil and connection.getIsServer ~= nil and connection:getIsServer() then
        Bunker.applySettings({
            allowWallHeightsAboveFourMeters = self.allowWallHeightsAboveFourMeters,
            allowInputStation = self.allowInputStation,
            allowOutputStation = self.allowOutputStation,
            allowCompactionService = self.allowCompactionService,
            compactionPriceFactor = self.compactionPriceFactor,
        })
    end
end

local function sendSettingsToClient(_mission, connection, _x, _y, _z, _viewDistanceCoeff)
    if g_server ~= nil and connection ~= nil then
        connection:sendEvent(VariableBunkerSettingsEvent.new(Bunker.settings))
    end
end

local function initSettings()
    Bunker.loadSettings()
    if FSBaseMission ~= nil and FSBaseMission.onConnectionFinishedLoading ~= nil then
        FSBaseMission.onConnectionFinishedLoading =
            Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, sendSettingsToClient)
    end
end

initSettings()

local CONFIG_LOADING_RATE = "ADRP"
local DRIVE_THROUGH_CONFIGURATION = 2

local function isVariableBunkerStoreItem(storeItem)
    local configurations = storeItem ~= nil and storeItem.configurations or nil
    return configurations ~= nil
        and configurations[Bunker.CONFIG_WIDTH] ~= nil
        and configurations[Bunker.CONFIG_LENGTH] ~= nil
        and configurations[Bunker.CONFIG_HEIGHT] ~= nil
        and configurations[Bunker.CONFIG_TYPE] ~= nil
end

local function getConfigurationItem(screen, storeItem, configName)
    local configId = screen.configurations ~= nil and screen.configurations[configName] or nil
    local items = storeItem.configurations[configName]
    if items == nil then
        return nil
    end
    for _, item in ipairs(items) do
        if item.index == configId then
            return item
        end
    end
    return items[configId]
end

local function getCapacityText(screen, storeItem)
    local widthItem = getConfigurationItem(screen, storeItem, Bunker.CONFIG_WIDTH)
    local lengthItem = getConfigurationItem(screen, storeItem, Bunker.CONFIG_LENGTH)
    local heightItem = getConfigurationItem(screen, storeItem, Bunker.CONFIG_HEIGHT)
    local width = tonumber(widthItem ~= nil and widthItem.meters) or 40
    local length = tonumber(lengthItem ~= nil and lengthItem.meters) or 60
    local selectedHeight = tonumber(heightItem ~= nil and heightItem.meters) or 4
    local mapHeightLimit = VariableBunkerStorage.getMapHeightLimit()
    local typeId = screen.configurations ~= nil and screen.configurations[Bunker.CONFIG_TYPE] or 1
    local openEnds = typeId == DRIVE_THROUGH_CONFIGURATION and 2 or 1
    local capacity = VariableBunkerStorage.getCapacityForDimensions(width, length, selectedHeight, openEnds)
    local liters = math.floor(capacity / 10000 + 0.5) * 10000
    local text = "~ " .. g_i18n:formatNumber(liters, 0, true) .. " l"
    if mapHeightLimit ~= nil and selectedHeight > mapHeightLimit + 0.01 then
        text = text
            .. ", "
            .. string.format(
                g_i18n:getText("capacity_VariableBunkerMapLimit"),
                g_i18n:formatNumber(mapHeightLimit, 1, true)
            )
    end
    return text
end

local function addCapacityDisplay(screen, storeItem)
    screen.variableBunkerCapacityElement = nil
    if not isVariableBunkerStoreItem(storeItem) then
        return
    end

    local current = FocusManager.currentGui
    FocusManager:setGui("ConstructionScreen")
    local item = screen:getOrCreateConfigItem("option")
    item:getDescendantByName("option"):setVisible(false)
    item:getDescendantByName("title"):setText(g_i18n:getText("configuration_VariableBunkerEstimatedCapacity"))
    item:getDescendantByName("price"):setText(getCapacityText(screen, storeItem))
    FocusManager:removeElement(item)
    screen.variableBunkerCapacityElement = item
    screen.configurationLayout:invalidateLayout()
    FocusManager:setGui(current)
end

local function updateCapacityDisplay(screen, storeItem)
    local item = screen.variableBunkerCapacityElement
    if item ~= nil and isVariableBunkerStoreItem(storeItem) then
        item:getDescendantByName("price"):setText(getCapacityText(screen, storeItem))
    end
end

local function getIsLoadingRateHidden(screen, storeItem)
    if not isVariableBunkerStoreItem(storeItem) or storeItem.configurations[CONFIG_LOADING_RATE] == nil then
        return false
    end
    local outputItem = getConfigurationItem(screen, storeItem, Bunker.CONFIG_OUTPUT)
    return outputItem == nil or outputItem.side == nil or outputItem.side == "off"
end

local function resetHiddenLoadingRate(screen, storeItem)
    if screen.configurations == nil or not getIsLoadingRateHidden(screen, storeItem) then
        return
    end
    local defaultIds = storeItem.defaultConfigurationIds
    local defaultId = defaultIds ~= nil and defaultIds[CONFIG_LOADING_RATE] or nil
    if defaultId ~= nil and screen.configurations[CONFIG_LOADING_RATE] ~= nil then
        screen.configurations[CONFIG_LOADING_RATE] = defaultId
    end
end

local function updateConfigOptionsDataWithoutHiddenRows(screen, superFunc, storeItem)
    local selection = screen.configSelection
    local optionSets = selection ~= nil and selection.options or nil
    local options = optionSets ~= nil and optionSets[screen.currentConfigSet] or nil
    if options == nil or not getIsLoadingRateHidden(screen, storeItem) then
        return superFunc(screen, storeItem)
    end
    local visibleOptions = {}
    for _, option in ipairs(options) do
        if option.name ~= CONFIG_LOADING_RATE then
            table.insert(visibleOptions, option)
        end
    end
    optionSets[screen.currentConfigSet] = visibleOptions
    local result = superFunc(screen, storeItem)
    optionSets[screen.currentConfigSet] = options
    return result
end

local function refreshConfigurationDisplay(screen, storeItem)
    if screen.configSelection ~= nil and isVariableBunkerStoreItem(storeItem) then
        screen:updateConfigOptionsDisplay(storeItem)
    else
        updateCapacityDisplay(screen, storeItem)
    end
end

local function drawAutoDrivePreview(screen)
    if ConstructionScreen.uiHidden or screen.configurations == nil or screen.brush == nil then
        return
    end
    local placeable = screen.brush.placeable
    if
        placeable ~= nil
        and placeable.spec_VariableBunker ~= nil
        and placeable.VariableBunkerDrawAutoDrivePreview ~= nil
    then
        placeable:VariableBunkerDrawAutoDrivePreview()
    end
end

local function installHooks()
    if Bunker.constructionScreenHooksInstalled or ConstructionScreen == nil or Utils == nil then
        return
    end
    ConstructionScreen.updateConfigOptionsDisplay =
        Utils.appendedFunction(ConstructionScreen.updateConfigOptionsDisplay, addCapacityDisplay)
    ConstructionScreen.updateConfigOptionsData =
        Utils.overwrittenFunction(ConstructionScreen.updateConfigOptionsData, updateConfigOptionsDataWithoutHiddenRows)
    ConstructionScreen.loadCurrentConfiguration =
        Utils.prependedFunction(ConstructionScreen.loadCurrentConfiguration, resetHiddenLoadingRate)
    ConstructionScreen.loadCurrentConfiguration =
        Utils.appendedFunction(ConstructionScreen.loadCurrentConfiguration, refreshConfigurationDisplay)
    ConstructionScreen.draw = Utils.appendedFunction(ConstructionScreen.draw, drawAutoDrivePreview)
    Bunker.constructionScreenHooksInstalled = true
end

installHooks()

local HOURS_PER_DAY = 24

local function getInfoBunkerSilo(placeable)
    local spec = placeable ~= nil and placeable.spec_bunkerSilo or nil
    return spec ~= nil and spec.bunkerSilo or nil
end

local function getInfoText(placeable, key)
    return g_i18n:getText(key, placeable.customEnvironment)
end

local function getStatus(bunkerSilo)
    local state = bunkerSilo.state
    if state == BunkerSilo.STATE_FILL then
        if (bunkerSilo.fillLevel or 0) < 1 then
            return "status_VariableBunkerFill", false
        end
        if (bunkerSilo.compactedPercent or 0) < 100 then
            return "status_VariableBunkerCompact", true
        end
        return "status_VariableBunkerCover", true
    end
    if state == BunkerSilo.STATE_CLOSED then
        return "status_VariableBunkerFermenting", false
    end
    if state == BunkerSilo.STATE_FERMENTED then
        return "status_VariableBunkerOpen", true
    end
    return "status_VariableBunkerDrain", false
end

local function getFillLevelText(placeable, bunkerSilo)
    local fillLevel = bunkerSilo.fillLevel or 0
    local capacity = VariableBunkerStorage.getEstimatedCapacity(placeable)
    local text = g_i18n:formatVolume(fillLevel, 0)
    if capacity > 0 then
        text = string.format("%s (%d %%)", text, math.floor(math.min(fillLevel / capacity, 1) * 100 + 0.5))
    end
    return text
end

local function getFermentingText(placeable, bunkerSilo)
    local percent = math.clamp(bunkerSilo.fermentingPercent or 0, 0, 1)
    local environment = g_currentMission.environment
    local daysPerPeriod = environment ~= nil and environment.daysPerPeriod or 1
    local hours = math.ceil((1 - percent) * HOURS_PER_DAY * daysPerPeriod)
    local remaining
    if hours >= HOURS_PER_DAY then
        remaining = string.format(
            getInfoText(placeable, "info_VariableBunkerRemainingDays"),
            math.floor(hours / HOURS_PER_DAY),
            hours % HOURS_PER_DAY
        )
    else
        remaining = string.format(getInfoText(placeable, "info_VariableBunkerRemainingHours"), hours)
    end
    return string.format("%d %% (%s)", math.floor(percent * 100), remaining)
end

local function getInfoPlaceable()
    if
        Bunker.settings.showInfoBox == false
        or g_currentMission == nil
        or g_localPlayer == nil
        or Bunker.activeSilos == nil
    then
        return nil
    end
    for placeable in pairs(Bunker.activeSilos) do
        local bunkerSilo = getInfoBunkerSilo(placeable)
        if
            bunkerSilo ~= nil
            and not placeable.isDeleted
            and bunkerSilo:getCanInteract(true)
            and g_currentMission.accessHandler:canPlayerAccess(placeable)
        then
            return placeable, bunkerSilo
        end
    end
    return nil
end

local function addDebugInfoLines(box, placeable, bunkerSilo)
    local spec = placeable.spec_VariableBunker
    box:addLine(
        "Debug state",
        string.format("%s, compacted %.0f l", tostring(bunkerSilo.state), bunkerSilo.compactedFillLevel or 0)
    )
    local inputStorage = spec ~= nil and spec.inputStorage or nil
    if inputStorage ~= nil then
        local layer = inputStorage.layerHeight ~= nil and string.format("%.1f m", inputStorage.layerHeight) or "-"
        box:addLine(
            "Debug input",
            string.format(
                "band %s, layer %s, credit %.0f l",
                tostring(inputStorage.inputBandIndex),
                layer,
                inputStorage.pendingLiters or 0
            )
        )
        box:addLine("Debug grid", tostring(inputStorage.debugFreeCapacityReason or "-"))
    end
    local outputStorage = spec ~= nil and spec.outputStorage or nil
    if outputStorage ~= nil then
        box:addLine(
            "Debug output",
            string.format(
                "face %s, buffer %.0f l",
                outputStorage.faceZ ~= nil and string.format("%.1f m", outputStorage.faceZ) or "-",
                outputStorage.outputBuffers[FillType.SILAGE] or 0
            )
        )
    end
end

local infoListener = {}

function infoListener:getBox()
    if self.box == nil then
        local hud = g_currentMission.hud
        if hud == nil or hud.infoDisplay == nil then
            return nil
        end
        self.box = hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
    end
    return self.box
end

function infoListener:update(_dt)
    local placeable, bunkerSilo = getInfoPlaceable()
    if placeable == nil then
        return
    end
    local box = self:getBox()
    if box == nil then
        return
    end
    box:clear()
    box:setTitle(placeable:getName())
    box:addLine(getInfoText(placeable, "info_VariableBunkerFillLevel"), getFillLevelText(placeable, bunkerSilo))
    if bunkerSilo.state == BunkerSilo.STATE_FILL and (bunkerSilo.fillLevel or 0) >= 1 then
        box:addLine(
            getInfoText(placeable, "info_VariableBunkerCompaction"),
            string.format("%d %%", bunkerSilo.compactedPercent or 0)
        )
    elseif bunkerSilo.state == BunkerSilo.STATE_CLOSED then
        box:addLine(getInfoText(placeable, "info_VariableBunkerFermentation"), getFermentingText(placeable, bunkerSilo))
    end
    local statusKey, needsAction = getStatus(bunkerSilo)
    box:addLine(getInfoText(placeable, "info_VariableBunkerStatus"), getInfoText(placeable, statusKey), needsAction)
    if Bunker.getIsDebugActive("overlay") then
        addDebugInfoLines(box, placeable, bunkerSilo)
    end
    box:showNextFrame()
end

function infoListener:deleteMap()
    if self.box ~= nil and g_currentMission ~= nil and g_currentMission.hud ~= nil then
        g_currentMission.hud.infoDisplay:destroyBox(self.box)
    end
    self.box = nil
end

addModEventListener(infoListener)

local DEBUG_SETTLE_TIME = 3000
local DEBUG_DUMP_MIN_CHANGE = 1000
local DEBUG_PROGRESS_SHARE = 0.1
local DEBUG_OVERLAY_DISTANCE = 150

local function dumpSilo(placeable, reason)
    if Bunker.getIsDebugActive("dump") then
        VariableBunkerStorage.debugDump(placeable, reason)
    end
end

local debugListener = { silos = {} }

function debugListener:trackSilo(placeable, bunkerSilo, time)
    local fillLevel = bunkerSilo.fillLevel or 0
    local data = self.silos[placeable]
    if data == nil then
        self.silos[placeable] = {
            state = bunkerSilo.state,
            fillLevel = fillLevel,
            dumpedFillLevel = fillLevel,
        }
        Bunker.debugLog(
            "silo",
            "tracking '%s', state %s, fill level %.0f l",
            tostring(placeable:getName()),
            tostring(bunkerSilo.state),
            fillLevel
        )
        if fillLevel >= 1 then
            dumpSilo(placeable, "silo loaded")
        end
        return
    end
    if bunkerSilo.state ~= data.state then
        Bunker.debugLog(
            "silo",
            "'%s' state %s -> %s at %.0f l",
            tostring(placeable:getName()),
            tostring(data.state),
            tostring(bunkerSilo.state),
            fillLevel
        )
        dumpSilo(placeable, string.format("state %s -> %s", tostring(data.state), tostring(bunkerSilo.state)))
        data.state = bunkerSilo.state
        data.dumpedFillLevel = fillLevel
        data.changeTime = nil
    end
    if math.abs(fillLevel - data.fillLevel) >= 1 then
        data.fillLevel = fillLevel
        data.changeTime = time
        local capacity = VariableBunkerStorage.getEstimatedCapacity(placeable)
        local change = fillLevel - data.dumpedFillLevel
        if capacity > 0 and math.abs(change) >= capacity * DEBUG_PROGRESS_SHARE then
            dumpSilo(placeable, string.format("progress, %+.0f l", change))
            data.dumpedFillLevel = fillLevel
        end
    elseif data.changeTime ~= nil and time - data.changeTime >= DEBUG_SETTLE_TIME then
        data.changeTime = nil
        local change = fillLevel - data.dumpedFillLevel
        if math.abs(change) >= DEBUG_DUMP_MIN_CHANGE then
            Bunker.debugLog(
                "silo",
                "'%s' fill level settled at %.0f l (%+.0f l since the last dump)",
                tostring(placeable:getName()),
                fillLevel,
                change
            )
            dumpSilo(placeable, string.format("fill level settled, %+.0f l", change))
            data.dumpedFillLevel = fillLevel
        end
    end
end

function debugListener:update(_dt)
    if not Bunker.getIsDebugActive() or g_currentMission == nil or Bunker.activeSilos == nil then
        return
    end
    for placeable in pairs(self.silos) do
        if Bunker.activeSilos[placeable] == nil then
            self.silos[placeable] = nil
        end
    end
    local time = g_currentMission.time or 0
    for placeable in pairs(Bunker.activeSilos) do
        local bunkerSilo = getInfoBunkerSilo(placeable)
        if bunkerSilo ~= nil and not placeable.isDeleted and placeable.isServer then
            self:trackSilo(placeable, bunkerSilo, time)
        end
    end
end

function debugListener:draw()
    if not Bunker.getIsDebugActive("overlay") or Bunker.activeSilos == nil or getCamera == nil then
        return
    end
    local camera = getCamera()
    if camera == nil or camera == 0 then
        return
    end
    local cameraX, _, cameraZ = getWorldTranslation(camera)
    for placeable in pairs(Bunker.activeSilos) do
        local spec = placeable.spec_VariableBunker
        if spec ~= nil and not placeable.isDeleted and placeable.rootNode ~= nil then
            local x, _, z = getWorldTranslation(placeable.rootNode)
            local reach = DEBUG_OVERLAY_DISTANCE + math.max(spec.widthMeters or 0, spec.lengthMeters or 0) * 0.5
            if MathUtil.vector2Length(x - cameraX, z - cameraZ) <= reach then
                VariableBunkerStorage.debugDraw(placeable)
            end
        end
    end
end

function debugListener:deleteMap()
    self.silos = {}
end

addModEventListener(debugListener)

local modDirectory = g_currentModDirectory or ""
local AUTODRIVE_MOD_NAME = "FS25_AutoDrive"

local VariableBunkerDimensionConfigurationItem = {}
local VariableBunkerDimensionConfigurationItem_mt =
    Class(VariableBunkerDimensionConfigurationItem, PlaceableConfigurationItem)

function VariableBunkerDimensionConfigurationItem.new(configName, customMt)
    local self = VariableBunkerDimensionConfigurationItem:superClass()
        .new(configName, customMt or VariableBunkerDimensionConfigurationItem_mt)
    self.meters = 0
    return self
end

function VariableBunkerDimensionConfigurationItem:loadFromXML(
    xmlFile,
    baseKey,
    configKey,
    baseDirectory,
    customEnvironment
)
    if
        not VariableBunkerDimensionConfigurationItem:superClass()
            .loadFromXML(self, xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    then
        return false
    end

    self.meters = math.max(xmlFile:getValue(configKey .. "#meters", self.meters), 0)
    self.variableBunkerBaseSelectable = self.isSelectable ~= false
    if
        self.configName == Bunker.CONFIG_HEIGHT
        and Bunker.settings ~= nil
        and not Bunker.settings.allowWallHeightsAboveFourMeters
        and self.meters > 4
    then
        self.isSelectable = false
    end
    local decimals = math.abs(self.meters - math.floor(self.meters)) > 0.001 and 1 or 0
    self.name = string.format("%s %s", g_i18n:formatNumber(self.meters, decimals, true), g_i18n:getText("unit_mShort"))
    return true
end

function VariableBunkerDimensionConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    VariableBunkerDimensionConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)
    schema:register(XMLValueType.FLOAT, configPath .. "#meters", "Configured bunker dimension in meters", 0)
end

local function getIsAutoDriveLoaded()
    return g_modIsLoaded ~= nil and g_modIsLoaded[AUTODRIVE_MOD_NAME] == true
end

local VariableBunkerAutoDriveConfigurationItem = {}
local VariableBunkerAutoDriveConfigurationItem_mt =
    Class(VariableBunkerAutoDriveConfigurationItem, PlaceableConfigurationItem)

function VariableBunkerAutoDriveConfigurationItem.new(configName, customMt)
    return VariableBunkerAutoDriveConfigurationItem:superClass()
        .new(configName, customMt or VariableBunkerAutoDriveConfigurationItem_mt)
end

function VariableBunkerAutoDriveConfigurationItem:loadFromXML(
    xmlFile,
    baseKey,
    configKey,
    baseDirectory,
    customEnvironment
)
    if
        not VariableBunkerAutoDriveConfigurationItem:superClass()
            .loadFromXML(self, xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    then
        return false
    end

    if not getIsAutoDriveLoaded() then
        self.isSelectable = false
    end
    return true
end

function VariableBunkerAutoDriveConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    VariableBunkerAutoDriveConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)
end

local VariableBunkerStationConfigurationItem = {}
local VariableBunkerStationConfigurationItem_mt =
    Class(VariableBunkerStationConfigurationItem, PlaceableConfigurationItem)

function VariableBunkerStationConfigurationItem.new(configName, customMt)
    local self = VariableBunkerStationConfigurationItem:superClass()
        .new(configName, customMt or VariableBunkerStationConfigurationItem_mt)
    self.side = "off"
    return self
end

function VariableBunkerStationConfigurationItem:loadFromXML(
    xmlFile,
    baseKey,
    configKey,
    baseDirectory,
    customEnvironment
)
    if
        not VariableBunkerStationConfigurationItem:superClass()
            .loadFromXML(self, xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    then
        return false
    end
    self.side = xmlFile:getValue(configKey .. "#side", "off")
    self.variableBunkerBaseSelectable = self.isSelectable ~= false
    local settings = Bunker.settings or {}
    local enabled = self.configName == Bunker.CONFIG_INPUT and settings.allowInputStation ~= false
        or self.configName == Bunker.CONFIG_OUTPUT and settings.allowOutputStation ~= false
    self.isSelectable = self.variableBunkerBaseSelectable and (enabled or self.side == "off")
    return true
end

function VariableBunkerStationConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    VariableBunkerStationConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)
    schema:register(XMLValueType.STRING, configPath .. "#side", "Configured station side", "off")
end

local VariableBunkerServiceConfigurationItem = {}
local VariableBunkerServiceConfigurationItem_mt =
    Class(VariableBunkerServiceConfigurationItem, PlaceableConfigurationItem)

function VariableBunkerServiceConfigurationItem.new(configName, customMt)
    return VariableBunkerServiceConfigurationItem:superClass()
        .new(configName, customMt or VariableBunkerServiceConfigurationItem_mt)
end

function VariableBunkerServiceConfigurationItem:loadFromXML(
    xmlFile,
    baseKey,
    configKey,
    baseDirectory,
    customEnvironment
)
    if
        not VariableBunkerServiceConfigurationItem:superClass()
            .loadFromXML(self, xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    then
        return false
    end
    self.variableBunkerBaseSelectable = self.isSelectable ~= false
    self.isSelectable = self.variableBunkerBaseSelectable
        and (Bunker.settings.allowCompactionService ~= false or self.saveId == "off")
    return true
end

function VariableBunkerServiceConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    VariableBunkerServiceConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)
end

local function registerConfigurationTypes()
    if g_placeableConfigurationManager == nil then
        return
    end

    local function addConfigType(configName, titleKey, itemClass)
        if g_placeableConfigurationManager:getConfigurationDescByName(configName) == nil then
            g_placeableConfigurationManager:addConfigurationType(
                configName,
                g_i18n:getText(titleKey),
                "VariableBunker",
                itemClass
            )
        end
    end

    addConfigType(Bunker.CONFIG_WIDTH, "configuration_VariableBunkerWidth", VariableBunkerDimensionConfigurationItem)
    addConfigType(Bunker.CONFIG_LENGTH, "configuration_VariableBunkerLength", VariableBunkerDimensionConfigurationItem)
    addConfigType(Bunker.CONFIG_HEIGHT, "configuration_VariableBunkerHeight", VariableBunkerDimensionConfigurationItem)
    addConfigType(Bunker.CONFIG_TYPE, "configuration_VariableBunkerType", PlaceableConfigurationItem)
    addConfigType(Bunker.CONFIG_FLOOR, "configuration_VariableBunkerFloor", PlaceableConfigurationItem)
    addConfigType(Bunker.CONFIG_INPUT, "configuration_VariableBunkerInput", VariableBunkerStationConfigurationItem)
    addConfigType(Bunker.CONFIG_OUTPUT, "configuration_VariableBunkerOutput", VariableBunkerStationConfigurationItem)
    addConfigType(
        Bunker.CONFIG_COMPACTION,
        "configuration_VariableBunkerCompaction",
        VariableBunkerServiceConfigurationItem
    )
    addConfigType(
        Bunker.CONFIG_AUTODRIVE,
        "configuration_VariableBunkerAutoDrive",
        VariableBunkerAutoDriveConfigurationItem
    )
end

local function initRegistration()
    if g_placeableSpecializationManager ~= nil then
        g_placeableSpecializationManager:addSpecialization(
            "FS25_VariableBunker",
            "VariableBunker",
            modDirectory .. "lua/VariableBunker.lua",
            nil
        )

        if Placeable ~= nil and Placeable.xmlSchema ~= nil and Bunker.registerXMLPaths ~= nil then
            Bunker.registerXMLPaths(Placeable.xmlSchema, "placeable")
        end
    end

    registerConfigurationTypes()
end

initRegistration()
