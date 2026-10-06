VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local BASE_KEY = "placeable.VariableBunker"
local ROOT_KEY_WIDTH = Bunker.CONFIG_WIDTH or "VariableBunkerWidth"
local ROOT_KEY_LENGTH = Bunker.CONFIG_LENGTH or "VariableBunkerLength"
local ROOT_KEY_HEIGHT = Bunker.CONFIG_HEIGHT or "VariableBunkerHeight"
local ROOT_KEY_TYPE = Bunker.CONFIG_TYPE or "VariableBunkerType"
local ROOT_KEY_FLOOR = Bunker.CONFIG_FLOOR or "VariableBunkerFloor"
local DEFAULT_WIDTH = 10
local DEFAULT_LENGTH = 40
local DEFAULT_HEIGHT = 4
local WALL_THICKNESS = 0.4
local WALL_BASE_HEIGHT = 1.5
local WALL_SLOPE_PER_METER = 0.25
local INNER_MARGIN = 0.25
local LEVEL_MARGIN = 1
local TRIGGER_MARGIN = 1
local FLOOR_FRONT_EXTENSION = 30
local DRIVE_THROUGH_FLOOR_BACK_EXTENSION = 30
local DRIVE_THROUGH_FLOOR_FRONT_EXTENSION = 15
local FLOOR_THICKNESS = 0.2
local FLOOR_TOP_OFFSET = 0.02
local FLOOR_CONFIGURATION_NONE = 1
local FLOOR_CONFIGURATION_FLUSH = 2
local FLOOR_CONFIGURATION_EXTENDED = 3
local TYPE_CONFIGURATION_BUNKER = 1
local TYPE_CONFIGURATION_DRIVE_THROUGH = 2
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
    "leftCornerBaseNode",
    "rightCornerBaseNode",
    "leftCornerSlopeNode",
    "rightCornerSlopeNode",
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
    "leftCornerBaseCollisionNode",
    "rightCornerBaseCollisionNode",
    "leftCornerSlopeCollisionNode",
    "rightCornerSlopeCollisionNode",
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

    setTranslation(node, tx, ty, tz)
    setScale(node, sx, sy, sz)
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

    setRigidBodyType(node, enabled and RigidBodyType.STATIC or RigidBodyType.NONE)
end

function Bunker.prerequisitesPresent(_specializations)
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
        "VariableBunkerUpdateCollisionStates",
        Bunker.VariableBunkerUpdateCollisionStates
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
        "VariableBunkerGetTypeConfiguration",
        Bunker.VariableBunkerGetTypeConfiguration
    )
    SpecializationUtil.registerFunction(placeableType, "VariableBunkerHasRearWall", Bunker.VariableBunkerHasRearWall)
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
    spec.loadedFromSavegame = savegame ~= nil

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

function Bunker:VariableBunkerGetTypeConfiguration()
    local configId = self.configurations ~= nil and self.configurations[ROOT_KEY_TYPE] or nil
    if configId == nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
        if storeItem ~= nil and storeItem.defaultConfigurationIds ~= nil then
            configId = storeItem.defaultConfigurationIds[ROOT_KEY_TYPE]
        end
    end
    return configId or TYPE_CONFIGURATION_BUNKER
end

function Bunker:VariableBunkerHasRearWall()
    return self:VariableBunkerGetTypeConfiguration() ~= TYPE_CONFIGURATION_DRIVE_THROUGH
end

function Bunker:VariableBunkerUpdateCollisionStates()
    local spec = self.spec_VariableBunker
    if spec == nil then
        return
    end

    for _, node in ipairs({
        spec.leftCollisionNode,
        spec.rightCollisionNode,
        spec.leftBaseCollisionNode,
        spec.rightBaseCollisionNode,
        spec.leftSlopeCollisionNode,
        spec.rightSlopeCollisionNode,
    }) do
        setPhysicsNodeEnabled(node, true)
    end

    for _, node in ipairs({
        spec.rearCollisionNode,
        spec.rearBaseCollisionNode,
        spec.rearSlopeCollisionNode,
        spec.leftCornerBaseCollisionNode,
        spec.rightCornerBaseCollisionNode,
        spec.leftCornerSlopeCollisionNode,
        spec.rightCornerSlopeCollisionNode,
    }) do
        setPhysicsNodeEnabled(node, spec.hasRearWall == true)
    end

    setPhysicsNodeEnabled(spec.floorCollisionNode, spec.floorPlateEnabled == true)
    setPhysicsNodeEnabled(spec.interactionTriggerNode, true)
end

function Bunker:VariableBunkerHasFloorPlate()
    local configuration = self:VariableBunkerGetFloorPlateConfiguration()
    return configuration == FLOOR_CONFIGURATION_FLUSH or configuration == FLOOR_CONFIGURATION_EXTENDED
end

function Bunker:VariableBunkerApplyDimensions()
    local spec = self.spec_VariableBunker
    self:removeFromPhysics()
    local widthItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_WIDTH)
    local lengthItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_LENGTH)
    local heightItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_HEIGHT)
    local width = math.clamp(tonumber(widthItem ~= nil and widthItem.meters) or DEFAULT_WIDTH, 6, 100)
    local length = math.clamp(tonumber(lengthItem ~= nil and lengthItem.meters) or DEFAULT_LENGTH, 20, 200)
    local height = math.clamp(tonumber(heightItem ~= nil and heightItem.meters) or DEFAULT_HEIGHT, 2, 8)
    local floorConfiguration = self:VariableBunkerGetFloorPlateConfiguration()
    local hasRearWall = self:VariableBunkerHasRearWall()
    local hasFloorPlate = floorConfiguration == FLOOR_CONFIGURATION_FLUSH
        or floorConfiguration == FLOOR_CONFIGURATION_EXTENDED
    local floorFrontExtension = 0
    local floorBackExtension = 0
    if floorConfiguration == FLOOR_CONFIGURATION_EXTENDED then
        if hasRearWall then
            floorFrontExtension = FLOOR_FRONT_EXTENSION
        else
            floorFrontExtension = DRIVE_THROUGH_FLOOR_FRONT_EXTENSION
            floorBackExtension = DRIVE_THROUGH_FLOOR_BACK_EXTENSION
        end
    end
    local slopeHeight = height - WALL_BASE_HEIGHT
    local slopeRun = slopeHeight * WALL_SLOPE_PER_METER
    local outerWidth = width + WALL_THICKNESS * 2
    local baseOuterWidth = outerWidth + slopeRun * 2
    local rearWallExtension = hasRearWall and WALL_THICKNESS or 0
    local rearFootExtension = hasRearWall and WALL_THICKNESS + slopeRun or 0
    local rearOuterExtension = rearFootExtension + floorBackExtension
    local sideOuterCenter = rearWallExtension * 0.5
    local footprintStart = -length * 0.5 - floorFrontExtension
    local footprintLength = length + rearOuterExtension + floorFrontExtension
    local innerWidth = math.max(width - INNER_MARGIN * 2, 0.5)
    local wallOffset = width * 0.5 + WALL_THICKNESS * 0.5
    local rearWallOffset = length * 0.5 + WALL_THICKNESS * 0.5
    local sideBaseOffset = width * 0.5 + WALL_THICKNESS + slopeRun * 0.5
    local sideSlopeOffset = width * 0.5 + WALL_THICKNESS
    local rearBaseOffset = length * 0.5 + WALL_THICKNESS + slopeRun * 0.5
    local rearSlopeOffset = length * 0.5 + WALL_THICKNESS
    local rearCoreOuterEdge = length * 0.5 + WALL_THICKNESS
    local cornerBaseOffset = outerWidth * 0.5 + slopeRun * 0.5
    local floorCenterY = FLOOR_TOP_OFFSET - FLOOR_THICKNESS * 0.5
    local triggerHeight = height + 2

    spec.widthMeters = width
    spec.lengthMeters = length
    spec.heightMeters = height
    spec.floorPlateEnabled = hasFloorPlate
    spec.floorPlateFrontExtension = floorFrontExtension
    spec.wallSlopeRun = slopeRun
    spec.hasRearWall = hasRearWall

    setTranslation(spec.leftWallNode, -wallOffset, height * 0.5, 0)
    setScale(spec.leftWallNode, WALL_THICKNESS, height, length)
    setTranslation(spec.rightWallNode, wallOffset, height * 0.5, 0)
    setScale(spec.rightWallNode, WALL_THICKNESS, height, length)
    setTranslation(spec.rearWallNode, 0, height * 0.5, rearWallOffset)
    setScale(spec.rearWallNode, outerWidth, height, WALL_THICKNESS)
    setVisibility(spec.rearWallNode, hasRearWall)
    setTranslation(spec.floorPlateNode, 0, floorCenterY, (rearOuterExtension - floorFrontExtension) * 0.5)
    setScale(spec.floorPlateNode, baseOuterWidth, FLOOR_THICKNESS, length + rearOuterExtension + floorFrontExtension)
    setVisibility(spec.floorPlateNode, hasFloorPlate)
    setTranslation(spec.leftWallBaseNode, -sideBaseOffset, WALL_BASE_HEIGHT * 0.5, sideOuterCenter)
    setScale(spec.leftWallBaseNode, slopeRun, WALL_BASE_HEIGHT, length + rearWallExtension)
    setTranslation(spec.rightWallBaseNode, sideBaseOffset, WALL_BASE_HEIGHT * 0.5, sideOuterCenter)
    setScale(spec.rightWallBaseNode, slopeRun, WALL_BASE_HEIGHT, length + rearWallExtension)
    setTranslation(spec.rearWallBaseNode, 0, WALL_BASE_HEIGHT * 0.5, rearBaseOffset)
    setScale(spec.rearWallBaseNode, outerWidth, WALL_BASE_HEIGHT, slopeRun)
    setVisibility(spec.rearWallBaseNode, hasRearWall)
    setTranslation(spec.leftWallSlopeNode, -sideSlopeOffset, WALL_BASE_HEIGHT, sideOuterCenter)
    setScale(spec.leftWallSlopeNode, slopeRun, slopeHeight, length + rearWallExtension)
    setTranslation(spec.rightWallSlopeNode, sideSlopeOffset, WALL_BASE_HEIGHT, sideOuterCenter)
    setScale(spec.rightWallSlopeNode, slopeRun, slopeHeight, length + rearWallExtension)
    setTranslation(spec.rearWallSlopeNode, 0, WALL_BASE_HEIGHT, rearSlopeOffset)
    setScale(spec.rearWallSlopeNode, slopeRun, slopeHeight, outerWidth)
    setVisibility(spec.rearWallSlopeNode, hasRearWall)
    setTranslation(spec.leftCornerBaseNode, -cornerBaseOffset, WALL_BASE_HEIGHT * 0.5, rearBaseOffset)
    setScale(spec.leftCornerBaseNode, slopeRun, WALL_BASE_HEIGHT, slopeRun)
    setVisibility(spec.leftCornerBaseNode, hasRearWall)
    setTranslation(spec.rightCornerBaseNode, cornerBaseOffset, WALL_BASE_HEIGHT * 0.5, rearBaseOffset)
    setScale(spec.rightCornerBaseNode, slopeRun, WALL_BASE_HEIGHT, slopeRun)
    setVisibility(spec.rightCornerBaseNode, hasRearWall)
    setTranslation(spec.leftCornerSlopeNode, -outerWidth * 0.5, WALL_BASE_HEIGHT, rearCoreOuterEdge)
    setScale(spec.leftCornerSlopeNode, slopeRun, slopeHeight, slopeRun)
    setVisibility(spec.leftCornerSlopeNode, hasRearWall)
    setTranslation(spec.rightCornerSlopeNode, outerWidth * 0.5, WALL_BASE_HEIGHT, rearCoreOuterEdge)
    setScale(spec.rightCornerSlopeNode, slopeRun, slopeHeight, slopeRun)
    setVisibility(spec.rightCornerSlopeNode, hasRearWall)
    setPhysicsNodeTransform(spec.leftCollisionNode, -wallOffset, height * 0.5, 0, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(spec.rightCollisionNode, wallOffset, height * 0.5, 0, WALL_THICKNESS, height, length)
    setPhysicsNodeTransform(spec.rearCollisionNode, 0, height * 0.5, rearWallOffset, outerWidth, height, WALL_THICKNESS)
    setPhysicsNodeEnabled(spec.rearCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.floorCollisionNode,
        0,
        floorCenterY,
        (rearOuterExtension - floorFrontExtension) * 0.5,
        baseOuterWidth,
        FLOOR_THICKNESS,
        length + rearOuterExtension + floorFrontExtension
    )
    setPhysicsNodeEnabled(spec.floorCollisionNode, hasFloorPlate)
    setPhysicsNodeTransform(
        spec.leftBaseCollisionNode,
        -sideBaseOffset,
        WALL_BASE_HEIGHT * 0.5,
        sideOuterCenter,
        slopeRun,
        WALL_BASE_HEIGHT,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rightBaseCollisionNode,
        sideBaseOffset,
        WALL_BASE_HEIGHT * 0.5,
        sideOuterCenter,
        slopeRun,
        WALL_BASE_HEIGHT,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rearBaseCollisionNode,
        0,
        WALL_BASE_HEIGHT * 0.5,
        rearBaseOffset,
        outerWidth,
        WALL_BASE_HEIGHT,
        slopeRun
    )
    setPhysicsNodeEnabled(spec.rearBaseCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.leftSlopeCollisionNode,
        -sideSlopeOffset,
        WALL_BASE_HEIGHT,
        sideOuterCenter,
        slopeRun,
        slopeHeight,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rightSlopeCollisionNode,
        sideSlopeOffset,
        WALL_BASE_HEIGHT,
        sideOuterCenter,
        slopeRun,
        slopeHeight,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rearSlopeCollisionNode,
        0,
        WALL_BASE_HEIGHT,
        rearSlopeOffset,
        slopeRun,
        slopeHeight,
        outerWidth
    )
    setPhysicsNodeEnabled(spec.rearSlopeCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.leftCornerBaseCollisionNode,
        -cornerBaseOffset,
        WALL_BASE_HEIGHT * 0.5,
        rearBaseOffset,
        slopeRun,
        WALL_BASE_HEIGHT,
        slopeRun
    )
    setPhysicsNodeEnabled(spec.leftCornerBaseCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.rightCornerBaseCollisionNode,
        cornerBaseOffset,
        WALL_BASE_HEIGHT * 0.5,
        rearBaseOffset,
        slopeRun,
        WALL_BASE_HEIGHT,
        slopeRun
    )
    setPhysicsNodeEnabled(spec.rightCornerBaseCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.leftCornerSlopeCollisionNode,
        -outerWidth * 0.5,
        WALL_BASE_HEIGHT,
        rearCoreOuterEdge,
        slopeRun,
        slopeHeight,
        slopeRun
    )
    setPhysicsNodeEnabled(spec.leftCornerSlopeCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.rightCornerSlopeCollisionNode,
        outerWidth * 0.5,
        WALL_BASE_HEIGHT,
        rearCoreOuterEdge,
        slopeRun,
        slopeHeight,
        slopeRun
    )
    setPhysicsNodeEnabled(spec.rightCornerSlopeCollisionNode, hasRearWall)
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

    self:VariableBunkerUpdateCollisionStates()
    if self.isPreplaced then
        self:addToPhysics()
    end
end
