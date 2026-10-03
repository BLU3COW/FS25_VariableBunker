VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local BASE_KEY = "placeable.VariableBunker"
local ROOT_KEY_WIDTH = Bunker.CONFIG_WIDTH or "VariableBunkerWidth"
local ROOT_KEY_LENGTH = Bunker.CONFIG_LENGTH or "VariableBunkerLength"
local ROOT_KEY_HEIGHT = Bunker.CONFIG_HEIGHT or "VariableBunkerHeight"
local DEFAULT_WIDTH = 10
local DEFAULT_LENGTH = 40
local DEFAULT_HEIGHT = 4
local WALL_THICKNESS = 0.4
local INNER_MARGIN = 0.25
local LEVEL_MARGIN = 1
local TRIGGER_MARGIN = 1
local SCALE_EPSILON = 0.0001

local NODE_ATTRIBUTES = {
    "leftWallNode",
    "rightWallNode",
    "leftCollisionNode",
    "rightCollisionNode",
    "interactionTriggerNode",
    "siloAreaStartNode",
    "siloAreaWidthNode",
    "siloAreaHeightNode",
    "innerAreaStartNode",
    "innerAreaWidthNode",
    "innerAreaHeightNode",
    "clearAreaStartNode",
    "clearAreaWidthNode",
    "clearAreaHeightNode",
    "levelAreaStartNode",
    "levelAreaWidthNode",
    "levelAreaHeightNode",
    "testAreaStartNode",
    "testAreaEndNode",
    "tipOcclusionStartNode",
    "tipOcclusionEndNode",
}

local function setPhysicsNodeTransform(node, tx, ty, tz, sx, sy, sz)
    if node == nil then
        return
    end

    local currentTx, currentTy, currentTz = getTranslation(node)
    local currentSx, currentSy, currentSz = getScale(node)
    if
        math.abs(currentTx - tx) <= SCALE_EPSILON
        and math.abs(currentTy - ty) <= SCALE_EPSILON
        and math.abs(currentTz - tz) <= SCALE_EPSILON
        and math.abs(currentSx - sx) <= SCALE_EPSILON
        and math.abs(currentSy - sy) <= SCALE_EPSILON
        and math.abs(currentSz - sz) <= SCALE_EPSILON
    then
        return
    end

    local wasAddedToPhysics = getIsAddedToPhysics(node)
    if wasAddedToPhysics then
        removeFromPhysics(node)
    end

    setTranslation(node, tx, ty, tz)
    setScale(node, sx, sy, sz)

    if wasAddedToPhysics then
        addToPhysics(node)
    end
end

local function setNodeTranslation(node, x, y, z)
    if node ~= nil then
        setTranslation(node, x, y, z)
    end
end

function Bunker.prerequisitesPresent(specializations)
    return true
end

function Bunker.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("VariableBunker")
    for _, attributeName in ipairs(NODE_ATTRIBUTES) do
        schema:register(XMLValueType.NODE_INDEX, basePath .. ".VariableBunker#" .. attributeName, attributeName)
    end
    schema:setXMLSpecializationType()
end

function Bunker.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", Bunker)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", Bunker)
end

function Bunker.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerGetConfigurationItem",
        Bunker.VariableBunkerGetConfigurationItem
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerApplyDimensions",
        Bunker.VariableBunkerApplyDimensions
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerHasAutoDriveCourse",
        Bunker.VariableBunkerHasAutoDriveCourse
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerCreateAutoDriveCourse",
        Bunker.VariableBunkerCreateAutoDriveCourse
    )
end

function Bunker:onLoad(savegame)
    self.spec_VariableBunker = {}
    local spec = self.spec_VariableBunker

    for _, attributeName in ipairs(NODE_ATTRIBUTES) do
        spec[attributeName] =
            self.xmlFile:getValue(BASE_KEY .. "#" .. attributeName, nil, self.components, self.i3dMappings)
    end

    self:VariableBunkerApplyDimensions()
end

function Bunker:VariableBunkerGetConfigurationItem(configName)
    local configId = self.configurations ~= nil and self.configurations[configName] or nil
    if configId == nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
        if storeItem ~= nil and storeItem.defaultConfigurationIds ~= nil then
            configId = storeItem.defaultConfigurationIds[configName]
        end
    end
    return ConfigurationUtil.getConfigItemByConfigId(self.configFileName, configName, configId)
end

function Bunker:VariableBunkerApplyDimensions()
    local spec = self.spec_VariableBunker
    local widthItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_WIDTH)
    local lengthItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_LENGTH)
    local heightItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_HEIGHT)
    local width = math.clamp(tonumber(widthItem ~= nil and widthItem.meters) or DEFAULT_WIDTH, 6, 20)
    local length = math.clamp(tonumber(lengthItem ~= nil and lengthItem.meters) or DEFAULT_LENGTH, 20, 80)
    local height = math.clamp(tonumber(heightItem ~= nil and heightItem.meters) or DEFAULT_HEIGHT, 2, 6)
    local outerWidth = width + WALL_THICKNESS * 2
    local innerWidth = math.max(width - INNER_MARGIN * 2, 0.5)
    local wallOffset = width * 0.5 + WALL_THICKNESS * 0.5
    local triggerHeight = height + 2

    spec.widthMeters = width
    spec.lengthMeters = length
    spec.heightMeters = height

    setTranslation(spec.leftWallNode, -wallOffset, height * 0.5, 0)
    setScale(spec.leftWallNode, WALL_THICKNESS, height, length)
    setTranslation(spec.rightWallNode, wallOffset, height * 0.5, 0)
    setScale(spec.rightWallNode, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(spec.leftCollisionNode, -wallOffset, height * 0.5, 0, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(spec.rightCollisionNode, wallOffset, height * 0.5, 0, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(
        spec.interactionTriggerNode,
        0,
        triggerHeight * 0.5,
        0,
        width + TRIGGER_MARGIN * 2,
        triggerHeight,
        length + TRIGGER_MARGIN * 2
    )

    setNodeTranslation(spec.siloAreaStartNode, width * 0.5, 0, length * 0.5)
    setNodeTranslation(spec.siloAreaWidthNode, -width * 0.5, 0, length * 0.5)
    setNodeTranslation(spec.siloAreaHeightNode, width * 0.5, 0, -length * 0.5)
    setNodeTranslation(spec.innerAreaStartNode, innerWidth * 0.5, 0, length * 0.5 - INNER_MARGIN)
    setNodeTranslation(spec.innerAreaWidthNode, -innerWidth * 0.5, 0, length * 0.5 - INNER_MARGIN)
    setNodeTranslation(spec.innerAreaHeightNode, innerWidth * 0.5, 0, -length * 0.5 + INNER_MARGIN)

    setNodeTranslation(spec.clearAreaStartNode, -outerWidth * 0.5, 0, -length * 0.5)
    setNodeTranslation(spec.clearAreaWidthNode, 0, 0, length)
    setNodeTranslation(spec.clearAreaHeightNode, outerWidth, 0, 0)
    setNodeTranslation(spec.levelAreaStartNode, -outerWidth * 0.5 - LEVEL_MARGIN, 0, -length * 0.5 - LEVEL_MARGIN)
    setNodeTranslation(spec.levelAreaWidthNode, 0, 0, length + LEVEL_MARGIN * 2)
    setNodeTranslation(spec.levelAreaHeightNode, outerWidth + LEVEL_MARGIN * 2, 0, 0)
    setNodeTranslation(spec.testAreaStartNode, -outerWidth * 0.5, 0, -length * 0.5)
    setNodeTranslation(spec.testAreaEndNode, outerWidth, height, length)
    setNodeTranslation(spec.tipOcclusionStartNode, -outerWidth * 0.5, 0, -length * 0.5)
    setNodeTranslation(spec.tipOcclusionEndNode, outerWidth, 0, length)

    local placementSpec = self.spec_placement
    if placementSpec ~= nil and self.loadTestArea ~= nil then
        placementSpec.testAreas = {}
        self.xmlFile:iterate("placeable.placement.testAreas.testArea", function(_, key)
            local testArea = {}
            if self:loadTestArea(self.xmlFile, key, testArea) then
                table.insert(placementSpec.testAreas, testArea)
            end
        end)
    end
end
