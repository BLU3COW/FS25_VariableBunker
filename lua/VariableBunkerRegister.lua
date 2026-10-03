VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local modDirectory = g_currentModDirectory or ""

Bunker.CONFIG_WIDTH = "VariableBunkerWidth"
Bunker.CONFIG_LENGTH = "VariableBunkerLength"
Bunker.CONFIG_HEIGHT = "VariableBunkerHeight"
Bunker.CONFIG_AUTODRIVE = "VariableBunkerAutoDrive"

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
    local decimals = math.abs(self.meters - math.floor(self.meters)) > 0.001 and 1 or 0
    self.name = string.format("%s %s", g_i18n:formatNumber(self.meters, decimals, true), g_i18n:getText("unit_mShort"))
    return true
end

function VariableBunkerDimensionConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    VariableBunkerDimensionConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)
    schema:register(XMLValueType.FLOAT, configPath .. "#meters", "Configured bunker dimension in meters", 0)
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
    addConfigType(Bunker.CONFIG_AUTODRIVE, "configuration_VariableBunkerAutoDrive", PlaceableConfigurationItem)
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
