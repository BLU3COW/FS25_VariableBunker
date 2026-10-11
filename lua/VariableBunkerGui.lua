VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local CONFIG_WIDTH = "VariableBunkerWidth"
local CONFIG_LENGTH = "VariableBunkerLength"
local CONFIG_HEIGHT = "VariableBunkerHeight"
local CONFIG_TYPE = "VariableBunkerType"
local DRIVE_THROUGH_CONFIGURATION = 2
local SURFACE_ANGLE = math.rad(40)

local function isVariableBunkerStoreItem(storeItem)
    local configurations = storeItem ~= nil and storeItem.configurations or nil
    return configurations ~= nil
        and configurations[CONFIG_WIDTH] ~= nil
        and configurations[CONFIG_LENGTH] ~= nil
        and configurations[CONFIG_HEIGHT] ~= nil
        and configurations[CONFIG_TYPE] ~= nil
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

local function getMapHeightLimit()
    local densityMapMaxHeight = getfenv(0).getDensityMapMaxHeight
    if
        densityMapMaxHeight ~= nil
        and DensityMapHeightUtil ~= nil
        and DensityMapHeightUtil.terrainDetailHeightId ~= nil
    then
        return densityMapMaxHeight(DensityMapHeightUtil.terrainDetailHeightId)
    end
    return nil
end

local function getCapacityText(screen, storeItem)
    local widthItem = getConfigurationItem(screen, storeItem, CONFIG_WIDTH)
    local lengthItem = getConfigurationItem(screen, storeItem, CONFIG_LENGTH)
    local heightItem = getConfigurationItem(screen, storeItem, CONFIG_HEIGHT)
    local width = tonumber(widthItem ~= nil and widthItem.meters) or 40
    local length = tonumber(lengthItem ~= nil and lengthItem.meters) or 60
    local selectedHeight = tonumber(heightItem ~= nil and heightItem.meters) or 4
    local mapHeightLimit = getMapHeightLimit()
    local fillHeight = mapHeightLimit ~= nil and math.min(selectedHeight, mapHeightLimit) or selectedHeight
    local typeId = screen.configurations ~= nil and screen.configurations[CONFIG_TYPE] or 1
    local openEnds = typeId == DRIVE_THROUGH_CONFIGURATION and 2 or 1
    local volume = width
        * math.max(0, length * fillHeight - openEnds * fillHeight * fillHeight / (2 * math.tan(SURFACE_ANGLE)))
    local liters = math.floor(volume * 0.1 + 0.5) * 10000
    local text = "≈ " .. g_i18n:formatNumber(liters, 0, true) .. " l"
    if mapHeightLimit ~= nil and selectedHeight > mapHeightLimit + 0.01 then
        text = text
            .. " · "
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
    ConstructionScreen.loadCurrentConfiguration =
        Utils.appendedFunction(ConstructionScreen.loadCurrentConfiguration, updateCapacityDisplay)
    ConstructionScreen.draw = Utils.appendedFunction(ConstructionScreen.draw, drawAutoDrivePreview)
    Bunker.constructionScreenHooksInstalled = true
end

installHooks()
