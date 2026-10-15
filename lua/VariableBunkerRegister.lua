VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local modDirectory = g_currentModDirectory or ""
local AUTODRIVE_MOD_NAME = "FS25_AutoDrive"

Bunker.CONFIG_WIDTH = "VariableBunkerWidth"
Bunker.CONFIG_LENGTH = "VariableBunkerLength"
Bunker.CONFIG_HEIGHT = "VariableBunkerHeight"
Bunker.CONFIG_TYPE = "VariableBunkerType"
Bunker.CONFIG_FLOOR = "VariableBunkerFloor"
Bunker.CONFIG_AUTODRIVE = "VariableBunkerAutoDrive"
Bunker.CONFIG_INPUT = "VariableBunkerInput"
Bunker.CONFIG_OUTPUT = "VariableBunkerOutput"
Bunker.CONFIG_COMPACTION = "VariableBunkerCompaction"

VariableBunkerDimensionConfigurationItem = {}
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
    addConfigType(Bunker.CONFIG_COMPACTION, "configuration_VariableBunkerCompaction", PlaceableConfigurationItem)
    addConfigType(
        Bunker.CONFIG_AUTODRIVE,
        "configuration_VariableBunkerAutoDrive",
        VariableBunkerAutoDriveConfigurationItem
    )
end

local function init()
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

init()
