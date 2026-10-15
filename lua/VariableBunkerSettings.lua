VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local SETTINGS_ROOT = "VariableBunkerSettings"
local SETTINGS_KEY = SETTINGS_ROOT .. ".construction"
local HEIGHT_CONFIG_NAME = "VariableBunkerHeight"
local INPUT_CONFIG_NAME = "VariableBunkerInput"
local OUTPUT_CONFIG_NAME = "VariableBunkerOutput"

Bunker.settings = Bunker.settings
    or {
        allowWallHeightsAboveFourMeters = true,
        allowInputStation = true,
        allowOutputStation = true,
        compactionPriceFactor = 1,
    }

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

    setXMLInt(xmlFile, SETTINGS_ROOT .. "#version", 3)
    setXMLBool(
        xmlFile,
        SETTINGS_KEY .. "#allowWallHeightsAboveFourMeters",
        Bunker.settings.allowWallHeightsAboveFourMeters == true
    )
    setXMLBool(xmlFile, SETTINGS_KEY .. "#allowInputStation", Bunker.settings.allowInputStation == true)
    setXMLBool(xmlFile, SETTINGS_KEY .. "#allowOutputStation", Bunker.settings.allowOutputStation == true)
    setXMLFloat(xmlFile, SETTINGS_KEY .. "#compactionPriceFactor", Bunker.settings.compactionPriceFactor)
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
        local heightItems = configurations ~= nil and configurations[HEIGHT_CONFIG_NAME] or nil
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
            [INPUT_CONFIG_NAME] = Bunker.settings.allowInputStation,
            [OUTPUT_CONFIG_NAME] = Bunker.settings.allowOutputStation,
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
    end
end

function Bunker.applySettings(settings)
    Bunker.settings.allowWallHeightsAboveFourMeters = settings ~= nil
        and settings.allowWallHeightsAboveFourMeters == true
    Bunker.settings.allowInputStation = settings == nil or settings.allowInputStation ~= false
    Bunker.settings.allowOutputStation = settings == nil or settings.allowOutputStation ~= false
    Bunker.settings.compactionPriceFactor = getCompactionPriceFactor(settings ~= nil and settings.compactionPriceFactor)
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
        compactionPriceFactor = 1,
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
    local compactionPriceFactor = getXMLFloat(xmlFile, SETTINGS_KEY .. "#compactionPriceFactor")
    delete(xmlFile)
    Bunker.applySettings({
        allowWallHeightsAboveFourMeters = allowHigherWalls == nil or allowHigherWalls == true,
        allowInputStation = allowInputStation == nil or allowInputStation == true,
        allowOutputStation = allowOutputStation == nil or allowOutputStation == true,
        compactionPriceFactor = compactionPriceFactor,
    })
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
    self.compactionPriceFactor = settings.compactionPriceFactor or 1
    return self
end

function VariableBunkerSettingsEvent:readStream(streamId, connection)
    self.allowWallHeightsAboveFourMeters = streamReadBool(streamId)
    self.allowInputStation = streamReadBool(streamId)
    self.allowOutputStation = streamReadBool(streamId)
    self.compactionPriceFactor = streamReadFloat32(streamId)
    self:run(connection)
end

function VariableBunkerSettingsEvent:writeStream(streamId, _connection)
    streamWriteBool(streamId, self.allowWallHeightsAboveFourMeters)
    streamWriteBool(streamId, self.allowInputStation)
    streamWriteBool(streamId, self.allowOutputStation)
    streamWriteFloat32(streamId, self.compactionPriceFactor)
end

function VariableBunkerSettingsEvent:run(connection)
    if connection ~= nil and connection.getIsServer ~= nil and connection:getIsServer() then
        Bunker.applySettings({
            allowWallHeightsAboveFourMeters = self.allowWallHeightsAboveFourMeters,
            allowInputStation = self.allowInputStation,
            allowOutputStation = self.allowOutputStation,
            compactionPriceFactor = self.compactionPriceFactor,
        })
    end
end

local function sendSettingsToClient(_mission, connection, _x, _y, _z, _viewDistanceCoeff)
    if g_server ~= nil and connection ~= nil then
        connection:sendEvent(VariableBunkerSettingsEvent.new(Bunker.settings))
    end
end

local function init()
    Bunker.loadSettings()
    if FSBaseMission ~= nil and FSBaseMission.onConnectionFinishedLoading ~= nil then
        FSBaseMission.onConnectionFinishedLoading =
            Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, sendSettingsToClient)
    end
end

init()
