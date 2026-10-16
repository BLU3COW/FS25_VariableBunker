VariableBunker = VariableBunker or {}

local Bunker = VariableBunker

Bunker.CONFIG_WIDTH = "VariableBunkerWidth"
Bunker.CONFIG_LENGTH = "VariableBunkerLength"
Bunker.CONFIG_HEIGHT = "VariableBunkerHeight"
Bunker.CONFIG_TYPE = "VariableBunkerType"
Bunker.CONFIG_FLOOR = "VariableBunkerFloor"
Bunker.CONFIG_AUTODRIVE = "VariableBunkerAutoDrive"
Bunker.CONFIG_INPUT = "VariableBunkerInput"
Bunker.CONFIG_OUTPUT = "VariableBunkerOutput"
Bunker.CONFIG_COMPACTION = "VariableBunkerCompaction"

local BASE_KEY = "placeable.VariableBunker"
local ROOT_KEY_WIDTH = Bunker.CONFIG_WIDTH
local ROOT_KEY_LENGTH = Bunker.CONFIG_LENGTH
local ROOT_KEY_HEIGHT = Bunker.CONFIG_HEIGHT
local ROOT_KEY_TYPE = Bunker.CONFIG_TYPE
local ROOT_KEY_FLOOR = Bunker.CONFIG_FLOOR
local ROOT_KEY_INPUT = Bunker.CONFIG_INPUT
local ROOT_KEY_OUTPUT = Bunker.CONFIG_OUTPUT
local ROOT_KEY_COMPACTION = Bunker.CONFIG_COMPACTION
local COMPACTION_CONFIGURATION_OFF = 1
local COMPACTION_CONFIGURATION_ON = 2
local DEFAULT_WIDTH = 40
local DEFAULT_LENGTH = 60
local DEFAULT_HEIGHT = 4
local WALL_THICKNESS = 0.4
local WALL_BASE_HEIGHT = 1.5
local WALL_SLOPE_PER_METER = 0.25
local INNER_MARGIN = 0.25
local LEVEL_MARGIN = 1
local TRIGGER_MARGIN = 1
local FLOOR_FRONT_EXTENSION = 30
local DRIVE_THROUGH_FLOOR_BACK_EXTENSION = 20
local DRIVE_THROUGH_FLOOR_FRONT_EXTENSION = 30
local FLOOR_THICKNESS = 0.2
local FLOOR_TOP_OFFSET = 0.02
local FLOOR_CONFIGURATION_NONE = 1
local FLOOR_CONFIGURATION_FLUSH = 2
local FLOOR_CONFIGURATION_EXTENDED = 3
local TYPE_CONFIGURATION_BUNKER = 1
local TYPE_CONFIGURATION_DRIVE_THROUGH = 2
local SCALE_EPSILON = 0.0001
local STATION_HALF_WIDTH = 4.5
local STATION_HALF_DEPTH = 3
local STATION_FRONT_OFFSET = 4
local LOAD_TRIGGER_REACH = 20
local MARKER_HEIGHT = 0.05
local MARKER_SIDE_OFFSET = 1.5
local MARKER_SERVICE_OFFSET = 2.5

Bunker.activeSilos = Bunker.activeSilos or {}

function Bunker.getTipHeightLimit(x, z)
    local limit
    for placeable in pairs(Bunker.activeSilos) do
        local spec = placeable.spec_VariableBunker
        local rootNode = placeable.rootNode
        if
            spec ~= nil
            and rootNode ~= nil
            and spec.heightMeters ~= nil
            and spec.widthMeters ~= nil
            and spec.lengthMeters ~= nil
        then
            local localX, _, localZ = worldToLocal(rootNode, x, 0, z)
            if math.abs(localX) <= spec.widthMeters * 0.5 and math.abs(localZ) <= spec.lengthMeters * 0.5 then
                local _, top, _ = localToWorld(rootNode, 0, spec.heightMeters, 0)
                limit = math.min(limit or top, top)
            end
        end
    end
    return limit
end

function Bunker.capTipLine(sx, sy, sz, ex, ey, ez)
    local limit
    for _, point in ipairs({ { sx, sz }, { ex, ez }, { (sx + ex) * 0.5, (sz + ez) * 0.5 } }) do
        local pointLimit = Bunker.getTipHeightLimit(point[1], point[2])
        if pointLimit ~= nil then
            limit = math.min(limit or pointLimit, pointLimit)
        end
    end
    if limit == nil then
        return sy, ey, false
    end
    return math.min(sy, limit), math.min(ey, limit), true
end

local function tipToGroundWithinWalls(
    vehicle,
    superFunc,
    delta,
    fillTypeIndex,
    sx,
    sy,
    sz,
    ex,
    ey,
    ez,
    innerRadius,
    radius,
    lineOffset,
    limitToLineHeight,
    ...
)
    if delta ~= nil and delta > 0 and sx ~= nil and ex ~= nil then
        local capped
        sy, ey, capped = Bunker.capTipLine(sx, sy, sz, ex, ey, ez)
        if capped then
            limitToLineHeight = true
        end
    end
    return superFunc(
        vehicle,
        delta,
        fillTypeIndex,
        sx,
        sy,
        sz,
        ex,
        ey,
        ez,
        innerRadius,
        radius,
        lineOffset,
        limitToLineHeight,
        ...
    )
end

if not Bunker.tipHeightHookInstalled and DensityMapHeightUtil ~= nil and Utils ~= nil then
    DensityMapHeightUtil.tipToGroundAroundLine =
        Utils.overwrittenFunction(DensityMapHeightUtil.tipToGroundAroundLine, tipToGroundWithinWalls)
    Bunker.tipHeightHookInstalled = true
end

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
    "leftTipCollisionNode",
    "rightTipCollisionNode",
    "rearTipCollisionNode",
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
    "inputStationRootNode",
    "inputExactFillRootNode",
    "inputBaleTriggerNode",
    "inputMarkerNode",
    "inputClearAreaStartNode",
    "inputClearAreaWidthNode",
    "inputClearAreaHeightNode",
    "inputLevelAreaStartNode",
    "inputLevelAreaWidthNode",
    "inputLevelAreaHeightNode",
    "inputTestAreaStartNode",
    "inputTestAreaEndNode",
    "outputStationRootNode",
    "outputLoadTriggerNode",
    "outputMarkerNode",
    "outputClearAreaStartNode",
    "outputClearAreaWidthNode",
    "outputClearAreaHeightNode",
    "outputLevelAreaStartNode",
    "outputLevelAreaWidthNode",
    "outputLevelAreaHeightNode",
    "outputTestAreaStartNode",
    "outputTestAreaEndNode",
    "compactionMarkerNode",
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

local function setTipCollisionHeight(node, height)
    if node ~= nil then
        setUserAttribute(node, "collisionHeight", UserAttributeType.FLOAT, height)
    end
end

local function setPhysicsNodeEnabled(node, enabled)
    if node == nil then
        return
    end

    setRigidBodyType(node, enabled and RigidBodyType.STATIC or RigidBodyType.NONE)
end

local function disableTriggerNode(node, enabled)
    if node ~= nil and not enabled then
        setRigidBodyType(node, RigidBodyType.NONE)
    end
end

local function setStationAreaNodes(spec, prefix, enabled)
    local minX = enabled and -STATION_HALF_WIDTH or 0
    local minZ = enabled and -STATION_HALF_DEPTH or 0
    local width = enabled and STATION_HALF_WIDTH * 2 or 0
    local depth = enabled and STATION_HALF_DEPTH * 2 or 0
    setNodeTranslation(spec[prefix .. "ClearAreaStartNode"], minX, 0, minZ)
    setNodeTranslation(spec[prefix .. "ClearAreaWidthNode"], width, 0, 0)
    setNodeTranslation(spec[prefix .. "ClearAreaHeightNode"], 0, 0, depth)
    setNodeTranslation(spec[prefix .. "LevelAreaStartNode"], minX, 0, minZ)
    setNodeTranslation(spec[prefix .. "LevelAreaWidthNode"], width, 0, 0)
    setNodeTranslation(spec[prefix .. "LevelAreaHeightNode"], 0, 0, depth)
    setNodeTranslation(spec[prefix .. "TestAreaStartNode"], minX, 0, minZ)
    setNodeTranslation(spec[prefix .. "TestAreaEndNode"], width, enabled and 4 or 0, depth)
end

local function setStationRootTransform(rootNode, halfLength)
    if rootNode == nil then
        return
    end
    setTranslation(rootNode, 0, 0, -halfLength - STATION_FRONT_OFFSET)
    setRotation(rootNode, 0, math.pi, 0)
end

local function applyStationLayout(self, halfLength)
    local spec = self.spec_VariableBunker
    setStationRootTransform(spec.inputStationRootNode, halfLength)
    setStationRootTransform(spec.outputStationRootNode, halfLength)
    local combined = spec.hasInputStation and spec.hasOutputStation
    local inputMarkerX, outputMarkerX = 0, 0
    if spec.hasCompactionService then
        inputMarkerX, outputMarkerX = -MARKER_SERVICE_OFFSET, MARKER_SERVICE_OFFSET
    elseif combined then
        inputMarkerX, outputMarkerX = -MARKER_SIDE_OFFSET, MARKER_SIDE_OFFSET
    end
    setNodeTranslation(spec.inputMarkerNode, inputMarkerX, MARKER_HEIGHT, 0)
    setNodeTranslation(spec.outputMarkerNode, outputMarkerX, MARKER_HEIGHT, 0)
    setNodeTranslation(spec.compactionMarkerNode, 0, MARKER_HEIGHT, -halfLength - STATION_FRONT_OFFSET)
    setStationAreaNodes(spec, "input", spec.hasInputStation)
    setStationAreaNodes(spec, "output", spec.hasOutputStation and not combined)
end

local function addFillLevelWithRollback(
    station,
    fillableObject,
    fillUnitIndex,
    fillTypeIndex,
    fillDelta,
    fillInfo,
    toolType
)
    local oldFillLevel = fillableObject:getFillUnitFillLevel(fillUnitIndex)
    local transferred = LoadingStation.addFillLevelToFillableObject(
        station,
        fillableObject,
        fillUnitIndex,
        fillTypeIndex,
        fillDelta,
        fillInfo,
        toolType
    )
    local credited = math.max(fillableObject:getFillUnitFillLevel(fillUnitIndex) - oldFillLevel, 0)
    local excess = credited - transferred
    if excess > 0.0001 then
        local farmId = fillableObject:getOwnerFarmId()
        if fillableObject:isa(Vehicle) then
            farmId = fillableObject:getActiveFarm()
        end
        fillableObject:addFillUnitFillLevel(farmId, fillUnitIndex, -excess, fillTypeIndex, toolType, fillInfo)
    end
    return transferred
end

local function logStationDebug(text, ...)
    if Bunker.getIsDebugActive ~= nil and Bunker.getIsDebugActive("stations") then
        Bunker.debugLog("stations", text, ...)
    end
end

local function releaseDistantFillableObjects(loadTrigger)
    local fillableObjects = loadTrigger.fillableObjects
    if fillableObjects == nil or loadTrigger.triggerNode == nil or next(fillableObjects) == nil then
        return
    end
    local triggerX, _, triggerZ = getWorldTranslation(loadTrigger.triggerNode)
    for otherId, entry in pairs(fillableObjects) do
        local isNear = false
        if entityExists(otherId) then
            local x, _, z = getWorldTranslation(otherId)
            isNear = MathUtil.vector2Length(x - triggerX, z - triggerZ) <= LOAD_TRIGGER_REACH
        end
        if not isNear then
            fillableObjects[otherId] = nil
            local object = entry.object
            if object ~= nil then
                if object.removeDeleteListener ~= nil then
                    object:removeDeleteListener(loadTrigger)
                end
                if object.setFillUnitInTriggerRange ~= nil and entry.fillUnitIndex ~= nil then
                    object:setFillUnitInTriggerRange(entry.fillUnitIndex, false)
                end
                if loadTrigger.isLoading and loadTrigger.currentFillableObject == object then
                    loadTrigger:setIsLoading(false)
                end
                if loadTrigger.validFillableObject == object then
                    loadTrigger.validFillableObject = nil
                    loadTrigger.validFillableFillUnitIndex = nil
                end
            end
            logStationDebug("loading point released a vehicle that is no longer at this silo")
        end
    end
    if next(fillableObjects) == nil and loadTrigger.activatable ~= nil and g_currentMission ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(loadTrigger.activatable)
    end
end

local function getLoadTriggerDistance(loadTrigger, x, y, z)
    if loadTrigger.triggerNode == nil or x == nil then
        return math.huge
    end
    local triggerX, triggerY, triggerZ = getWorldTranslation(loadTrigger.triggerNode)
    return MathUtil.vector3Length(x - triggerX, y - triggerY, z - triggerZ)
end

local function getIsLoadTriggerFillableObjectAvailable(loadTrigger, superFunc)
    releaseDistantFillableObjects(loadTrigger)
    if not superFunc(loadTrigger) then
        return false
    end
    if loadTrigger.isLoading then
        return true
    end
    local fillableObject = loadTrigger.validFillableObject
    local fillUnitIndex = loadTrigger.validFillableFillUnitIndex
    if fillableObject == nil or fillUnitIndex == nil or loadTrigger.source == nil then
        return false
    end
    local fillLevels = loadTrigger.source:getAllFillLevels(g_currentMission:getFarmId())
    for fillTypeIndex, fillLevel in pairs(fillLevels) do
        if
            fillLevel > 0
            and (loadTrigger.fillTypes == nil or loadTrigger.fillTypes[fillTypeIndex])
            and fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex)
        then
            return true
        end
    end
    return false
end

function Bunker.prerequisitesPresent(_specializations)
    return true
end

function Bunker.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("VariableBunker")
    for _, attributeName in ipairs(NODE_ATTRIBUTES) do
        schema:register(XMLValueType.NODE_INDEX, basePath .. ".VariableBunker#" .. attributeName, attributeName)
    end
    UnloadingStation.registerXMLPaths(schema, basePath .. ".VariableBunker.inputStation")
    LoadingStation.registerXMLPaths(schema, basePath .. ".VariableBunker.outputStation")
    schema:setXMLSpecializationType()
end

function Bunker.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", Bunker)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", Bunker)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", Bunker)
    SpecializationUtil.registerEventListener(placeableType, "onSell", Bunker)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", Bunker)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", Bunker)
end

function Bunker.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "setOwnerFarmId", Bunker.setOwnerFarmId)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "setShowMarkers", Bunker.setShowMarkers)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "collectPickObjects", Bunker.collectPickObjects)
end

function Bunker.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerGetConfigurationId",
        Bunker.VariableBunkerGetConfigurationId
    )
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
        "VariableBunkerGetCompactionConfiguration",
        Bunker.VariableBunkerGetCompactionConfiguration
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
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerGetAutoDriveCourseBounds",
        Bunker.VariableBunkerGetAutoDriveCourseBounds
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerDrawAutoDrivePreview",
        Bunker.VariableBunkerDrawAutoDrivePreview
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "VariableBunkerRefreshStationState",
        Bunker.VariableBunkerRefreshStationState
    )
end

function Bunker:onLoad(savegame)
    self.spec_VariableBunker = {}
    local spec = self.spec_VariableBunker
    spec.loadedFromSavegame = savegame ~= nil

    if
        not spec.loadedFromSavegame
        and self.isServer
        and Bunker.settings ~= nil
        and not Bunker.settings.allowWallHeightsAboveFourMeters
        and self.configurations ~= nil
    then
        local storeItem = g_storeManager ~= nil and g_storeManager:getItemByXMLFilename(self.configFileName) or nil
        local heightItems = storeItem ~= nil and storeItem.configurations[ROOT_KEY_HEIGHT] or nil
        if heightItems ~= nil then
            for _, item in ipairs(heightItems) do
                if math.abs((tonumber(item.meters) or 0) - 4) < 0.001 then
                    self.configurations[ROOT_KEY_HEIGHT] = item.index
                    break
                end
            end
        end
    end

    for _, attributeName in ipairs(NODE_ATTRIBUTES) do
        spec[attributeName] =
            self.xmlFile:getValue(BASE_KEY .. "#" .. attributeName, nil, self.components, self.i3dMappings)
    end

    local inputItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_INPUT)
    local outputItem = self:VariableBunkerGetConfigurationItem(ROOT_KEY_OUTPUT)
    spec.inputSide = inputItem ~= nil and inputItem.side or "off"
    spec.outputSide = outputItem ~= nil and outputItem.side or "off"
    spec.hasInputStation = spec.inputSide ~= "off"
    spec.hasOutputStation = spec.outputSide ~= "off"
    spec.hasCompactionService = self:VariableBunkerGetCompactionConfiguration() == COMPACTION_CONFIGURATION_ON

    self:VariableBunkerApplyDimensions()

    if spec.hasInputStation then
        spec.inputStorage = VariableBunkerStorage.new(self, VariableBunkerStorage.MODE_INPUT)
        spec.inputStation = UnloadingStation.new(self.isServer, self.isClient)
        if
            not spec.inputStation:load(
                self.components,
                self.xmlFile,
                BASE_KEY .. ".inputStation",
                self.customEnvironment,
                self.i3dMappings,
                spec.inputStationRootNode
            )
        then
            spec.inputStation:delete()
            spec.inputStation = nil
            spec.inputStorage:delete()
            spec.inputStorage = nil
            spec.hasInputStation = false
        else
            spec.inputStation.stationName = g_i18n:getText("station_VariableBunkerInput", self.customEnvironment)
            spec.inputStation.owningPlaceable = self
            spec.inputStation.hasStoragePerFarm = false
        end
    end

    if spec.hasOutputStation then
        spec.outputStorage = VariableBunkerStorage.new(self, VariableBunkerStorage.MODE_OUTPUT)
        spec.outputStation = LoadingStation.new(self.isServer, self.isClient)
        if
            not spec.outputStation:load(
                self.components,
                self.xmlFile,
                BASE_KEY .. ".outputStation",
                self.customEnvironment,
                self.i3dMappings,
                spec.outputStationRootNode
            )
        then
            spec.outputStation:delete()
            spec.outputStation = nil
            spec.outputStorage:delete()
            spec.outputStorage = nil
            spec.hasOutputStation = false
        else
            spec.outputStation.stationName = g_i18n:getText("station_VariableBunkerOutput", self.customEnvironment)
            spec.outputStation.owningPlaceable = self
            spec.outputStation.hasStoragePerFarm = false
            spec.outputStation.addFillLevelToFillableObject = addFillLevelWithRollback
            for _, loadTrigger in ipairs(spec.outputStation.loadTriggers) do
                local superFunc = loadTrigger.getIsFillableObjectAvailable
                loadTrigger.getIsFillableObjectAvailable = function(trigger)
                    return getIsLoadTriggerFillableObjectAvailable(trigger, superFunc)
                end
                if loadTrigger.activatable ~= nil then
                    loadTrigger.activatable.getDistance = function(_activatable, x, y, z)
                        return getLoadTriggerDistance(loadTrigger, x, y, z)
                    end
                end
            end
        end
    end
    if self.propertyState ~= PlaceablePropertyState.CONSTRUCTION_PREVIEW then
        Bunker.activeSilos[self] = true
    end
end

function Bunker:onDelete()
    local spec = self.spec_VariableBunker
    local storageSystem = g_currentMission ~= nil and g_currentMission.storageSystem or nil
    if spec ~= nil then
        if spec.inputStation ~= nil then
            if storageSystem ~= nil then
                storageSystem:removeUnloadingStation(spec.inputStation, self)
            end
            spec.inputStation:delete()
            spec.inputStation = nil
        end
        if spec.outputStation ~= nil then
            if storageSystem ~= nil then
                storageSystem:removeLoadingStation(spec.outputStation, self)
            end
            spec.outputStation:delete()
            spec.outputStation = nil
        end
        for _, storage in pairs({ spec.inputStorage, spec.outputStorage }) do
            if storage ~= nil then
                if storageSystem ~= nil then
                    storageSystem:removeStorage(storage)
                end
                storage:delete()
            end
        end
        spec.inputStorage = nil
        spec.outputStorage = nil
        if Bunker.VariableBunkerDeleteCompaction ~= nil then
            Bunker.VariableBunkerDeleteCompaction(self)
        end
    end
    Bunker.activeSilos[self] = nil
end

function Bunker:VariableBunkerGetConfigurationId(configName)
    local configId = self.configurations ~= nil and self.configurations[configName] or nil
    if configId == nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
        if storeItem ~= nil and storeItem.defaultConfigurationIds ~= nil then
            configId = storeItem.defaultConfigurationIds[configName]
        end
    end
    return configId
end

function Bunker:VariableBunkerGetConfigurationItem(configName)
    local configId = self:VariableBunkerGetConfigurationId(configName)
    return ConfigurationUtil.getConfigItemByConfigId(self.configFileName, configName, configId)
end

function Bunker:VariableBunkerGetFloorPlateConfiguration()
    return self:VariableBunkerGetConfigurationId(ROOT_KEY_FLOOR) or FLOOR_CONFIGURATION_NONE
end

function Bunker:VariableBunkerGetTypeConfiguration()
    return self:VariableBunkerGetConfigurationId(ROOT_KEY_TYPE) or TYPE_CONFIGURATION_BUNKER
end

function Bunker:VariableBunkerGetCompactionConfiguration()
    return self:VariableBunkerGetConfigurationId(ROOT_KEY_COMPACTION) or COMPACTION_CONFIGURATION_OFF
end

function Bunker:VariableBunkerHasRearWall()
    return self:VariableBunkerGetTypeConfiguration() ~= TYPE_CONFIGURATION_DRIVE_THROUGH
end

function Bunker:VariableBunkerRefreshStationState()
    local spec = self.spec_VariableBunker
    if spec == nil then
        return
    end
    local settings = Bunker.settings or {}
    local inputActive = spec.hasInputStation and settings.allowInputStation ~= false
    local outputActive = spec.hasOutputStation and settings.allowOutputStation ~= false
    local serviceActive = spec.hasCompactionService and settings.allowCompactionService ~= false
    setVisibility(spec.inputStationRootNode, inputActive)
    setVisibility(spec.outputStationRootNode, outputActive)
    if spec.compactionMarkerNode ~= nil then
        setVisibility(spec.compactionMarkerNode, serviceActive)
    end
    setPhysicsNodeEnabled(spec.inputExactFillRootNode, inputActive)
    disableTriggerNode(spec.inputBaleTriggerNode, inputActive)
    disableTriggerNode(spec.outputLoadTriggerNode, outputActive)
    spec.inputGridPhysicsStates = spec.inputGridPhysicsStates or {}
    if self.spec_dynamicallyLoadedParts ~= nil then
        for _, part in ipairs(self.spec_dynamicallyLoadedParts.parts or {}) do
            local filename = string.lower(part.filename or "")
            if part.node ~= nil and string.find(filename, "sellingstationgenericnocoverwidegrid", 1, true) ~= nil then
                setVisibility(part.node, inputActive)
                if spec.stationsFinalized then
                    local physicsEnabled = spec.inputGridPhysicsStates[part.node]
                    if inputActive and physicsEnabled == false then
                        addToPhysics(part.node)
                        spec.inputGridPhysicsStates[part.node] = true
                    elseif not inputActive and physicsEnabled ~= false then
                        removeFromPhysics(part.node)
                        spec.inputGridPhysicsStates[part.node] = false
                    end
                end
            end
        end
    end
    if spec.stationsFinalized and self.setShowMarkers ~= nil and g_currentMission ~= nil then
        self:setShowMarkers(g_currentMission.accessHandler:canPlayerAccess(self))
    end
end

function Bunker.VariableBunkerFinalizeStations(self)
    local spec = self.spec_VariableBunker
    local storageSystem = g_currentMission.storageSystem
    local ownerFarmId = self:getOwnerFarmId()
    if spec.inputStation ~= nil and spec.inputStorage ~= nil then
        spec.inputStation:register(true)
        spec.inputStation:setOwnerFarmId(ownerFarmId, true)
        storageSystem:addUnloadingStation(spec.inputStation, self)
        spec.inputStorage:setOwnerFarmId(ownerFarmId, true)
        storageSystem:addStorage(spec.inputStorage)
        storageSystem:addStorageToUnloadingStation(spec.inputStorage, spec.inputStation)
    end
    if spec.outputStation ~= nil and spec.outputStorage ~= nil then
        spec.outputStation:register(true)
        spec.outputStation:setOwnerFarmId(ownerFarmId, true)
        storageSystem:addLoadingStation(spec.outputStation, self)
        spec.outputStorage:setOwnerFarmId(ownerFarmId, true)
        storageSystem:addStorage(spec.outputStorage)
        storageSystem:addStorageToLoadingStation(spec.outputStorage, spec.outputStation)
    end
    spec.stationsFinalized = true
    self:VariableBunkerRefreshStationState()
    if Bunker.VariableBunkerFinalizeCompaction ~= nil then
        Bunker.VariableBunkerFinalizeCompaction(self)
    end
end

function Bunker:onReadStream(streamId, connection)
    local spec = self.spec_VariableBunker
    if spec.inputStation ~= nil then
        local stationId = NetworkUtil.readNodeObjectId(streamId)
        spec.inputStation:readStream(streamId, connection)
        g_client:finishRegisterObject(spec.inputStation, stationId)
    end
    if spec.outputStation ~= nil then
        local stationId = NetworkUtil.readNodeObjectId(streamId)
        spec.outputStation:readStream(streamId, connection)
        g_client:finishRegisterObject(spec.outputStation, stationId)
    end
end

function Bunker:onWriteStream(streamId, connection)
    local spec = self.spec_VariableBunker
    if spec.inputStation ~= nil then
        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(spec.inputStation))
        spec.inputStation:writeStream(streamId, connection)
        g_server:registerObjectInStream(connection, spec.inputStation)
    end
    if spec.outputStation ~= nil then
        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(spec.outputStation))
        spec.outputStation:writeStream(streamId, connection)
        g_server:registerObjectInStream(connection, spec.outputStation)
    end
end

function Bunker:setOwnerFarmId(superFunc, farmId, noEventSend)
    superFunc(self, farmId, noEventSend)
    local spec = self.spec_VariableBunker
    if spec == nil then
        return
    end
    for _, object in pairs({ spec.inputStation, spec.outputStation, spec.inputStorage, spec.outputStorage }) do
        if object ~= nil then
            object:setOwnerFarmId(farmId, true)
        end
    end
end

function Bunker:collectPickObjects(superFunc, node)
    local spec = self.spec_VariableBunker
    if spec ~= nil then
        if spec.inputStation ~= nil then
            for _, unloadTrigger in ipairs(spec.inputStation.unloadTriggers) do
                if node == unloadTrigger.exactFillRootNode then
                    return
                end
            end
        end
        if spec.outputStation ~= nil then
            for _, loadTrigger in ipairs(spec.outputStation.loadTriggers) do
                if node == loadTrigger.triggerNode then
                    return
                end
            end
        end
    end
    superFunc(self, node)
end

function Bunker:setShowMarkers(superFunc, doShow)
    superFunc(self, doShow)
    local spec = self.spec_VariableBunker
    local markerSpec = self.spec_triggerMarkers
    if spec == nil or markerSpec == nil then
        return
    end
    local settings = Bunker.settings or {}
    if not spec.hasInputStation or settings.allowInputStation == false then
        local marker = markerSpec.triggerMarkers[1]
        if marker ~= nil then
            g_currentMission:removeTriggerMarker(marker.node)
        end
    end
    if not spec.hasOutputStation or settings.allowOutputStation == false then
        local marker = markerSpec.triggerMarkers[2]
        if marker ~= nil then
            g_currentMission:removeTriggerMarker(marker.node)
        end
    end
    if not spec.hasCompactionService or settings.allowCompactionService == false then
        local marker = markerSpec.triggerMarkers[3]
        if marker ~= nil then
            g_currentMission:removeTriggerMarker(marker.node)
        end
    end
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
        spec.leftTipCollisionNode,
        spec.rightTipCollisionNode,
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
        spec.rearTipCollisionNode,
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
    spec.footprintHalfWidth = baseOuterWidth * 0.5
    spec.footprintFrontZ = footprintStart
    spec.footprintRearZ = length * 0.5 + rearOuterExtension

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
    setScale(spec.leftWallSlopeNode, slopeHeight, slopeHeight, length + rearWallExtension)
    setTranslation(spec.rightWallSlopeNode, sideSlopeOffset, WALL_BASE_HEIGHT, sideOuterCenter)
    setScale(spec.rightWallSlopeNode, slopeHeight, slopeHeight, length + rearWallExtension)
    setTranslation(spec.rearWallSlopeNode, 0, WALL_BASE_HEIGHT, rearSlopeOffset)
    setScale(spec.rearWallSlopeNode, slopeHeight, slopeHeight, outerWidth)
    setVisibility(spec.rearWallSlopeNode, hasRearWall)
    setTranslation(spec.leftCornerBaseNode, -cornerBaseOffset, WALL_BASE_HEIGHT * 0.5, rearBaseOffset)
    setScale(spec.leftCornerBaseNode, slopeRun, WALL_BASE_HEIGHT, slopeRun)
    setVisibility(spec.leftCornerBaseNode, hasRearWall)
    setTranslation(spec.rightCornerBaseNode, cornerBaseOffset, WALL_BASE_HEIGHT * 0.5, rearBaseOffset)
    setScale(spec.rightCornerBaseNode, slopeRun, WALL_BASE_HEIGHT, slopeRun)
    setVisibility(spec.rightCornerBaseNode, hasRearWall)
    setTranslation(spec.leftCornerSlopeNode, -outerWidth * 0.5, WALL_BASE_HEIGHT, rearCoreOuterEdge)
    setScale(spec.leftCornerSlopeNode, slopeHeight, slopeHeight, slopeHeight)
    setVisibility(spec.leftCornerSlopeNode, hasRearWall)
    setTranslation(spec.rightCornerSlopeNode, outerWidth * 0.5, WALL_BASE_HEIGHT, rearCoreOuterEdge)
    setScale(spec.rightCornerSlopeNode, slopeHeight, slopeHeight, slopeHeight)
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
        slopeHeight,
        slopeHeight,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rightSlopeCollisionNode,
        sideSlopeOffset,
        WALL_BASE_HEIGHT,
        sideOuterCenter,
        slopeHeight,
        slopeHeight,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rearSlopeCollisionNode,
        0,
        WALL_BASE_HEIGHT,
        rearSlopeOffset,
        slopeHeight,
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
        slopeHeight,
        slopeHeight,
        slopeHeight
    )
    setPhysicsNodeEnabled(spec.leftCornerSlopeCollisionNode, hasRearWall)
    setPhysicsNodeTransform(
        spec.rightCornerSlopeCollisionNode,
        outerWidth * 0.5,
        WALL_BASE_HEIGHT,
        rearCoreOuterEdge,
        slopeHeight,
        slopeHeight,
        slopeHeight
    )
    setPhysicsNodeEnabled(spec.rightCornerSlopeCollisionNode, hasRearWall)
    local tipThickness = WALL_THICKNESS + slopeRun
    local sideTipOffset = width * 0.5 + tipThickness * 0.5
    setPhysicsNodeTransform(
        spec.leftTipCollisionNode,
        -sideTipOffset,
        height * 0.5,
        sideOuterCenter,
        tipThickness,
        height,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rightTipCollisionNode,
        sideTipOffset,
        height * 0.5,
        sideOuterCenter,
        tipThickness,
        height,
        length + rearWallExtension
    )
    setPhysicsNodeTransform(
        spec.rearTipCollisionNode,
        0,
        height * 0.5,
        length * 0.5 + tipThickness * 0.5,
        baseOuterWidth,
        height,
        tipThickness
    )
    setPhysicsNodeEnabled(spec.rearTipCollisionNode, hasRearWall)
    setTipCollisionHeight(spec.leftTipCollisionNode, height)
    setTipCollisionHeight(spec.rightTipCollisionNode, height)
    setTipCollisionHeight(spec.rearTipCollisionNode, height)
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
    applyStationLayout(self, length * 0.5)

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

    local tipOcclusionSpec = self.spec_tipOcclusionAreas
    if tipOcclusionSpec ~= nil and self.loadTipOcclusionArea ~= nil then
        tipOcclusionSpec.areas = {}
        self.xmlFile:iterate("placeable.tipOcclusionUpdateAreas.tipOcclusionUpdateArea", function(_, key)
            local area = {}
            if self:loadTipOcclusionArea(self.xmlFile, key, area) then
                table.insert(tipOcclusionSpec.areas, area)
            end
        end)
    end

    local aiSpec = self.spec_ai
    if aiSpec ~= nil and self.loadAIUpdateArea ~= nil then
        aiSpec.areas = {}
        self.xmlFile:iterate("placeable.ai.updateAreas.updateArea", function(_, key)
            local area = {}
            if self:loadAIUpdateArea(self.xmlFile, key, area) then
                table.insert(aiSpec.areas, area)
            end
        end)
    end

    self:VariableBunkerUpdateCollisionStates()
    self:VariableBunkerRefreshStationState()
    if self.isPreplaced then
        self:addToPhysics()
    end
end
