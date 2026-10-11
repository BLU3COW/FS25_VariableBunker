VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local SETTINGS_ROOT = "VariableBunkerSettings"
local SETTINGS_KEY = SETTINGS_ROOT .. ".construction"
local HEIGHT_CONFIG_NAME = "VariableBunkerHeight"

Bunker.settings = Bunker.settings or {
    allowWallHeightsAboveFourMeters = true,
}

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

    setXMLInt(xmlFile, SETTINGS_ROOT .. "#version", 1)
    setXMLBool(
        xmlFile,
        SETTINGS_KEY .. "#allowWallHeightsAboveFourMeters",
        Bunker.settings.allowWallHeightsAboveFourMeters == true
    )
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

function Bunker.applySettings(settings)
    Bunker.settings.allowWallHeightsAboveFourMeters = settings ~= nil
        and settings.allowWallHeightsAboveFourMeters == true
    Bunker.applyHeightSettingToStoreItems()
end

function Bunker.loadSettings()
    local filename = getSettingsFilename()
    if filename == nil then
        return false
    end

    Bunker.applySettings({ allowWallHeightsAboveFourMeters = true })
    if fileExists == nil or not fileExists(filename) then
        return writeSettingsFile(filename)
    end

    local xmlFile = loadXMLFile("VariableBunkerSettingsRead", filename)
    if xmlFile == nil or xmlFile == 0 then
        Logging.warning("[VariableBunker] Could not load modSettings file '%s'", filename)
        return false
    end

    local allowHigherWalls = getXMLBool(xmlFile, SETTINGS_KEY .. "#allowWallHeightsAboveFourMeters")
    delete(xmlFile)
    Bunker.applySettings({
        allowWallHeightsAboveFourMeters = allowHigherWalls == nil or allowHigherWalls == true,
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
    return self
end

function VariableBunkerSettingsEvent:readStream(streamId, connection)
    self.allowWallHeightsAboveFourMeters = streamReadBool(streamId)
    self:run(connection)
end

function VariableBunkerSettingsEvent:writeStream(streamId, _connection)
    streamWriteBool(streamId, self.allowWallHeightsAboveFourMeters)
end

function VariableBunkerSettingsEvent:run(connection)
    if connection ~= nil and connection.getIsServer ~= nil and connection:getIsServer() then
        Bunker.applySettings({
            allowWallHeightsAboveFourMeters = self.allowWallHeightsAboveFourMeters,
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
            Utils.prependedFunction(FSBaseMission.onConnectionFinishedLoading, sendSettingsToClient)
    end
end

init()
