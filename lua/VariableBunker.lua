VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local BASE_KEY = "placeable.VariableBunker"
local ROOT_KEY_WIDTH = Bunker.CONFIG_WIDTH or "VariableBunkerWidth"
local ROOT_KEY_LENGTH = Bunker.CONFIG_LENGTH or "VariableBunkerLength"
local ROOT_KEY_HEIGHT = Bunker.CONFIG_HEIGHT or "VariableBunkerHeight"
local ROOT_KEY_FLOOR = Bunker.CONFIG_FLOOR or "VariableBunkerFloor"
local DEFAULT_WIDTH = 10
local DEFAULT_LENGTH = 40
local DEFAULT_HEIGHT = 4
local WALL_THICKNESS = 0.4
local WALL_BASE_HEIGHT = 0.5
local WALL_SLOPE_PER_METER = 0.25
local INNER_MARGIN = 0.25
local LEVEL_MARGIN = 1
local TRIGGER_MARGIN = 1
local FLOOR_FRONT_EXTENSION = 30
local FLOOR_THICKNESS = 0.2
local FLOOR_TOP_OFFSET = 0.02
local FLOOR_CONFIGURATION_NONE = 1
local FLOOR_CONFIGURATION_FLUSH = 2
local FLOOR_CONFIGURATION_EXTENDED = 3
local SCALE_EPSILON = 0.0001

local NODE_ATTRIBUTES = {
    "leftWallNode",
    "rightWallNode",
    "rearWallNode",
    "floorPlateNode",
    "leftWallBaseNode",
    "rightWallBaseNode",
    "rearWallBaseNode",
    "leftWallSlopeNode",
    "rightWallSlopeNode",
    "rearWallSlopeNode",
    "leftCollisionNode",
    "rightCollisionNode",
    "rearCollisionNode",
    "floorCollisionNode",
    "leftBaseCollisionNode",
    "rightBaseCollisionNode",
    "rearBaseCollisionNode",
    "leftSlopeCollisionNode",
    "rightSlopeCollisionNode",
    "rearSlopeCollisionNode",
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

local function setPhysicsNodeEnabled(node, enabled)
    if node == nil then
        return
    end

    local isAddedToPhysics = getIsAddedToPhysics(node)
    if enabled and not isAddedToPhysics then
        addToPhysics(node)
    elseif not enabled and isAddedToPhysics then
        removeFromPhysics(node)
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
        "VariableBunkerHasFloorPlate",
        Bunker.VariableBunkerHasFloorPlate
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerGetFloorPlateConfiguration",
        Bunker.VariableBunkerGetFloorPlateConfiguration
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

function Bunker:VariableBunkerGetFloorPlateConfiguration()
    local configName = Bunker.CONFIG_FLOOR or ROOT_KEY_FLOOR
    local configId = self.configurations ~= nil and self.configurations[configName] or nil
    if configId == nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
        if storeItem ~= nil and storeItem.defaultConfigurationIds ~= nil then
            configId = storeItem.defaultConfigurationIds[configName]
        end
    end
    return configId or FLOOR_CONFIGURATION_NONE
end

function Bunker:VariableBunkerHasFloorPlate()
    local configuration = self:VariableBunkerGetFloorPlateConfiguration()
    return configuration == FLOOR_CONFIGURATION_FLUSH or configuration == FLOOR_CONFIGURATION_EXTENDED
end

function Bunker:VariableBunkerApplyDimensions()
    local spec = self.spec_VariableBunker
    local widthItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_WIDTH)
    local lengthItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_LENGTH)
    local heightItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_HEIGHT)
    local width = math.clamp(tonumber(widthItem ~= nil and widthItem.meters) or DEFAULT_WIDTH, 6, 100)
    local length = math.clamp(tonumber(lengthItem ~= nil and lengthItem.meters) or DEFAULT_LENGTH, 20, 200)
    local height = math.clamp(tonumber(heightItem ~= nil and heightItem.meters) or DEFAULT_HEIGHT, 2, 8)
    local floorConfiguration = self:VariableBunkerGetFloorPlateConfiguration()
    local hasFloorPlate = floorConfiguration == FLOOR_CONFIGURATION_FLUSH
        or floorConfiguration == FLOOR_CONFIGURATION_EXTENDED
    local floorFrontExtension = floorConfiguration == FLOOR_CONFIGURATION_EXTENDED and FLOOR_FRONT_EXTENSION or 0
    local slopeHeight = height - WALL_BASE_HEIGHT
    local slopeRun = slopeHeight * WALL_SLOPE_PER_METER
    local outerWidth = width + WALL_THICKNESS * 2
    local baseOuterWidth = outerWidth + slopeRun * 2
    local rearOuterExtension = WALL_THICKNESS + slopeRun
    local sideOuterLength = length + WALL_THICKNESS
    local sideOuterCenter = WALL_THICKNESS * 0.5
    local footprintStart = -length * 0.5 - floorFrontExtension
    local footprintLength = length + rearOuterExtension + floorFrontExtension
    local innerWidth = math.max(width - INNER_MARGIN * 2, 0.5)
    local wallOffset = width * 0.5 + WALL_THICKNESS * 0.5
    local rearWallOffset = length * 0.5 + WALL_THICKNESS * 0.5
    local sideBaseOffset = width * 0.5 + WALL_THICKNESS + slopeRun * 0.5
    local sideSlopeOffset = width * 0.5 + WALL_THICKNESS
    local rearBaseOffset = length * 0.5 + WALL_THICKNESS + slopeRun * 0.5
    local rearSlopeOffset = length * 0.5 + WALL_THICKNESS
    local floorCenterY = FLOOR_TOP_OFFSET - FLOOR_THICKNESS * 0.5
    local triggerHeight = height + 2

    spec.widthMeters = width
    spec.lengthMeters = length
    spec.heightMeters = height
    spec.floorPlateEnabled = hasFloorPlate
    spec.floorPlateFrontExtension = floorFrontExtension
    spec.wallSlopeRun = slopeRun

    setTranslation(spec.leftWallNode, -wallOffset, height * 0.5, 0)
    setScale(spec.leftWallNode, WALL_THICKNESS, height, length)
    setTranslation(spec.rightWallNode, wallOffset, height * 0.5, 0)
    setScale(spec.rightWallNode, WALL_THICKNESS, height, length)
    setTranslation(spec.rearWallNode, 0, height * 0.5, rearWallOffset)
    setScale(spec.rearWallNode, outerWidth, height, WALL_THICKNESS)
    setTranslation(spec.floorPlateNode, 0, floorCenterY, -floorFrontExtension * 0.5)
    setScale(spec.floorPlateNode, width, FLOOR_THICKNESS, length + floorFrontExtension)
    setVisibility(spec.floorPlateNode, hasFloorPlate)
    setTranslation(spec.leftWallBaseNode, -sideBaseOffset, WALL_BASE_HEIGHT * 0.5, sideOuterCenter)
    setScale(spec.leftWallBaseNode, slopeRun, WALL_BASE_HEIGHT, sideOuterLength)
    setTranslation(spec.rightWallBaseNode, sideBaseOffset, WALL_BASE_HEIGHT * 0.5, sideOuterCenter)
    setScale(spec.rightWallBaseNode, slopeRun, WALL_BASE_HEIGHT, sideOuterLength)
    setTranslation(spec.rearWallBaseNode, 0, WALL_BASE_HEIGHT * 0.5, rearBaseOffset)
    setScale(spec.rearWallBaseNode, baseOuterWidth, WALL_BASE_HEIGHT, slopeRun)
    setTranslation(spec.leftWallSlopeNode, -sideSlopeOffset, WALL_BASE_HEIGHT, sideOuterCenter)
    setScale(spec.leftWallSlopeNode, slopeRun, slopeHeight, sideOuterLength)
    setTranslation(spec.rightWallSlopeNode, sideSlopeOffset, WALL_BASE_HEIGHT, sideOuterCenter)
    setScale(spec.rightWallSlopeNode, slopeRun, slopeHeight, sideOuterLength)
    setTranslation(spec.rearWallSlopeNode, 0, WALL_BASE_HEIGHT, rearSlopeOffset)
    setScale(spec.rearWallSlopeNode, slopeRun, slopeHeight, baseOuterWidth)
    setPhysicsNodeTransform(spec.leftCollisionNode, -wallOffset, height * 0.5, 0, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(spec.rightCollisionNode, wallOffset, height * 0.5, 0, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(spec.rearCollisionNode, 0, height * 0.5, rearWallOffset, outerWidth, height, WALL_THICKNESS)
    setPhysicsNodeTransform(
        spec.floorCollisionNode,
        0,
        floorCenterY,
        -floorFrontExtension * 0.5,
        width,
        FLOOR_THICKNESS,
        length + floorFrontExtension
    )
    setPhysicsNodeEnabled(spec.floorCollisionNode, hasFloorPlate)
    setPhysicsNodeTransform(
        spec.leftBaseCollisionNode,
        -sideBaseOffset,
        WALL_BASE_HEIGHT * 0.5,
        sideOuterCenter,
        slopeRun,
        WALL_BASE_HEIGHT,
        sideOuterLength
    )
    setPhysicsNodeTransform(
        spec.rightBaseCollisionNode,
        sideBaseOffset,
        WALL_BASE_HEIGHT * 0.5,
        sideOuterCenter,
        slopeRun,
        WALL_BASE_HEIGHT,
        sideOuterLength
    )
    setPhysicsNodeTransform(
        spec.rearBaseCollisionNode,
        0,
        WALL_BASE_HEIGHT * 0.5,
        rearBaseOffset,
        baseOuterWidth,
        WALL_BASE_HEIGHT,
        slopeRun
    )
    setPhysicsNodeTransform(
        spec.leftSlopeCollisionNode,
        -sideSlopeOffset,
        WALL_BASE_HEIGHT,
        sideOuterCenter,
        slopeRun,
        slopeHeight,
        sideOuterLength
    )
    setPhysicsNodeTransform(
        spec.rightSlopeCollisionNode,
        sideSlopeOffset,
        WALL_BASE_HEIGHT,
        sideOuterCenter,
        slopeRun,
        slopeHeight,
        sideOuterLength
    )
    setPhysicsNodeTransform(
        spec.rearSlopeCollisionNode,
        0,
        WALL_BASE_HEIGHT,
        rearSlopeOffset,
        slopeRun,
        slopeHeight,
        baseOuterWidth
    )
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

    setNodeTranslation(spec.clearAreaStartNode, -baseOuterWidth * 0.5, 0, footprintStart)
    setNodeTranslation(spec.clearAreaWidthNode, 0, 0, footprintLength)
    setNodeTranslation(spec.clearAreaHeightNode, baseOuterWidth, 0, 0)
    setNodeTranslation(spec.levelAreaStartNode, -baseOuterWidth * 0.5 - LEVEL_MARGIN, 0, footprintStart - LEVEL_MARGIN)
    setNodeTranslation(spec.levelAreaWidthNode, 0, 0, footprintLength + LEVEL_MARGIN * 2)
    setNodeTranslation(spec.levelAreaHeightNode, baseOuterWidth + LEVEL_MARGIN * 2, 0, 0)
    setNodeTranslation(spec.testAreaStartNode, -baseOuterWidth * 0.5, 0, footprintStart)
    setNodeTranslation(spec.testAreaEndNode, baseOuterWidth, height, footprintLength)
    setNodeTranslation(spec.tipOcclusionStartNode, -baseOuterWidth * 0.5, 0, footprintStart)
    setNodeTranslation(spec.tipOcclusionEndNode, baseOuterWidth, 0, footprintLength)

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
