VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local CONFIG_NAME = "VariableBunkerAutoDrive"
local ENABLED_CONFIGURATION = 2
local LANE_WIDTH = 5
local FRONT_APPROACH = 27
local REAR_CLEARANCE = 3.2
local NEAR_FRONT_CONNECTION_OFFSET = 4
local FAR_FRONT_CONNECTION_OFFSET = 26
local WAYPOINT_SPACING = 3
local DRIVE_THROUGH_ENTRY_OFFSET = 10
local DRIVE_THROUGH_EXIT_OFFSET = 24
local DRIVE_THROUGH_WAYPOINT_SPACING = 2

local function getAutoDriveApi()
    local environment = getfenv(0).FS25_AutoDrive
    local autoDrive = AutoDrive or (environment ~= nil and environment.AutoDrive or nil)
    local graphManager = ADGraphManager or (environment ~= nil and environment.ADGraphManager or nil)
    local placeableData = AutoDrivePlaceableData or (environment ~= nil and environment.AutoDrivePlaceableData or nil)
    local createPlaceableEvent = CreatePlaceableEvent
        or (environment ~= nil and environment.CreatePlaceableEvent or nil)
    return autoDrive, graphManager, placeableData, createPlaceableEvent
end

local function addUnique(values, value)
    for _, current in ipairs(values) do
        if current == value then
            return
        end
    end
    table.insert(values, value)
end

local function connectDirected(wayPoints, firstIndex, secondIndex)
    local first = wayPoints[firstIndex]
    local second = wayPoints[secondIndex]
    addUnique(first.out, second.id)
    addUnique(second.incoming, first.id)
end

local function connectBidirectional(wayPoints, firstIndex, secondIndex)
    connectDirected(wayPoints, firstIndex, secondIndex)
    connectDirected(wayPoints, secondIndex, firstIndex)
end

local function addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX, localZ)
    local worldX, _, worldZ = localToWorld(placeable.rootNode, localX, 0, localZ)
    local waypointIndex = #wayPoints + 1
    wayPoints[waypointIndex] = {
        id = baseId + waypointIndex,
        x = worldX,
        y = autoDrive:getTerrainHeightAtWorldPos(worldX, worldZ),
        z = worldZ,
        out = {},
        incoming = {},
        flags = 1,
    }
    return waypointIndex
end

local function appendSegmentValues(values, startValue, endValue, spacing)
    local distance = math.abs(endValue - startValue)
    local segmentCount = math.max(1, math.ceil(distance / spacing))
    local firstStep = #values == 0 and 0 or 1
    for step = firstStep, segmentCount do
        values[#values + 1] = startValue + (endValue - startValue) * step / segmentCount
    end
end

local function getLaneLayout(width)
    local laneCount = math.max(1, math.floor(width / LANE_WIDTH + 0.0001))
    return laneCount, width / laneCount
end

local function createMapMarkers(graphManager, wayPoints, markerIndices, suffix)
    local markerOffset = #graphManager:getMapMarkers()
    local mapMarkers = {}
    for lane, waypointIndex in ipairs(markerIndices) do
        mapMarkers[lane] = {
            id = wayPoints[waypointIndex].id,
            name = string.format("%d_VariableBunker %s %d", markerOffset + lane, suffix, lane),
        }
    end
    return mapMarkers
end

local function createBunkerCourse(placeable, autoDrive, graphManager, width, length)
    local laneCount, laneSpacing = getLaneLayout(width)
    local rear = length * 0.5 - REAR_CLEARANCE
    local nearCluster = -length * 0.5 - NEAR_FRONT_CONNECTION_OFFSET
    local nearMain = nearCluster - 1
    local farCluster = -length * 0.5 - FAR_FRONT_CONNECTION_OFFSET
    local farMain = farCluster + 1
    local farTerminal = -length * 0.5 - FRONT_APPROACH
    local zValues = {}
    appendSegmentValues(zValues, rear, nearMain, WAYPOINT_SPACING)
    appendSegmentValues(zValues, nearMain, farMain, WAYPOINT_SPACING)

    local baseId = graphManager:getWayPointsCount()
    local wayPoints = {}
    local markers = {}
    local farOuterLeft = {}
    local farOuterRight = {}
    local nearOuterLeft = {}
    local nearOuterRight = {}

    for lane = 1, laneCount do
        local localX = -width * 0.5 + laneSpacing * (lane - 0.5)
        local main = {}
        for _, localZ in ipairs(zValues) do
            main[#main + 1] = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX, localZ)
        end
        for index = 1, #main - 1 do
            connectBidirectional(wayPoints, main[index], main[index + 1])
        end

        markers[lane] = main[1]
        local farMainIndex = main[#main]
        local nearMainIndex = main[1]
        local nearDistance = math.huge
        for index, localZ in ipairs(zValues) do
            local distance = math.abs(localZ - nearMain)
            if distance < nearDistance then
                nearDistance = distance
                nearMainIndex = main[index]
            end
        end

        local farCenter = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX + 0.25, farCluster)
        local farEnd = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX, farTerminal)
        local returnNode = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX, nearCluster)
        local farInnerLeft = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX - 1, farCluster)
        local farInnerRight = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX + 1, farCluster)
        farOuterLeft[lane] = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX - 2, farCluster)
        farOuterRight[lane] = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX + 2, farCluster)
        local nearInnerLeft = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX - 1, nearCluster)
        local nearInnerRight = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX + 1, nearCluster)
        nearOuterLeft[lane] = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX - 2, nearCluster)
        nearOuterRight[lane] = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX + 2, nearCluster)

        connectDirected(wayPoints, farMainIndex, farCenter)
        connectDirected(wayPoints, farCenter, farEnd)
        connectDirected(wayPoints, farCenter, returnNode)
        connectDirected(wayPoints, farMainIndex, farInnerLeft)
        connectDirected(wayPoints, farMainIndex, farInnerRight)
        connectBidirectional(wayPoints, farInnerLeft, farInnerRight)
        connectBidirectional(wayPoints, farOuterLeft[lane], farInnerLeft)
        connectBidirectional(wayPoints, farInnerRight, farOuterRight[lane])
        connectBidirectional(wayPoints, nearInnerLeft, nearInnerRight)
        connectBidirectional(wayPoints, nearOuterLeft[lane], nearInnerLeft)
        connectBidirectional(wayPoints, nearInnerRight, nearOuterRight[lane])
        connectDirected(wayPoints, nearInnerLeft, nearMainIndex)
        connectDirected(wayPoints, nearInnerRight, nearMainIndex)
    end

    for lane = 1, laneCount - 1 do
        connectBidirectional(wayPoints, farOuterRight[lane], farOuterLeft[lane + 1])
        connectBidirectional(wayPoints, nearOuterRight[lane], nearOuterLeft[lane + 1])
    end

    return wayPoints, createMapMarkers(graphManager, wayPoints, markers, "Bunkersilo")
end

local function createDriveThroughCourse(placeable, autoDrive, graphManager, width, length)
    local laneCount, laneSpacing = getLaneLayout(width)
    local entry = length * 0.5 + DRIVE_THROUGH_ENTRY_OFFSET
    local exit = -length * 0.5 - DRIVE_THROUGH_EXIT_OFFSET
    local zValues = {}
    appendSegmentValues(zValues, entry, exit, DRIVE_THROUGH_WAYPOINT_SPACING)

    local baseId = graphManager:getWayPointsCount()
    local wayPoints = {}
    local markers = {}
    for lane = 1, laneCount do
        local localX = -width * 0.5 + laneSpacing * (lane - 0.5)
        local previousIndex = nil
        for _, localZ in ipairs(zValues) do
            local waypointIndex = addLocalWaypoint(placeable, wayPoints, baseId, autoDrive, localX, localZ)
            if previousIndex ~= nil then
                connectDirected(wayPoints, previousIndex, waypointIndex)
            end
            previousIndex = waypointIndex
        end
        markers[lane] = previousIndex
    end

    return wayPoints, createMapMarkers(graphManager, wayPoints, markers, "Fahrsilo")
end

function Bunker:VariableBunkerHasAutoDriveCourse()
    local configName = Bunker.CONFIG_AUTODRIVE or CONFIG_NAME
    local configId = self.configurations ~= nil and self.configurations[configName] or nil
    return configId == ENABLED_CONFIGURATION
end

function Bunker:VariableBunkerCreateAutoDriveCourse(autoDrive, graphManager)
    local spec = self.spec_VariableBunker
    local width = spec ~= nil and spec.widthMeters or 10
    local length = spec ~= nil and spec.lengthMeters or 40
    if spec ~= nil and spec.hasRearWall == false then
        return createDriveThroughCourse(self, autoDrive, graphManager, width, length)
    end
    return createBunkerCourse(self, autoDrive, graphManager, width, length)
end

function Bunker:onFinalizePlacement()
    local spec = self.spec_VariableBunker
    if
        not self.isServer
        or (spec ~= nil and spec.loadedFromSavegame)
        or not self:VariableBunkerHasAutoDriveCourse()
    then
        return
    end

    local autoDrive, graphManager, placeableData, createPlaceableEvent = getAutoDriveApi()
    local canCreateViaPlaceableData = placeableData ~= nil and placeableData.createPlaceable ~= nil
    local canCreateViaEvent = createPlaceableEvent ~= nil and createPlaceableEvent.sendEvent ~= nil
    if
        autoDrive == nil
        or graphManager == nil
        or (placeableData ~= nil and placeableData.active == false)
        or (not canCreateViaPlaceableData and not canCreateViaEvent)
    then
        Logging.warning("[VariableBunker] AutoDrive course requested, but FS25_AutoDrive is not loaded or active")
        return
    end

    local wayPoints, mapMarkers = self:VariableBunkerCreateAutoDriveCourse(autoDrive, graphManager)
    if #wayPoints > 0 and #mapMarkers > 0 then
        if canCreateViaPlaceableData then
            placeableData:createPlaceable(wayPoints, mapMarkers)
        else
            createPlaceableEvent.sendEvent(wayPoints, mapMarkers)
        end
        Logging.info(
            "[VariableBunker] Created %s AutoDrive course with %d waypoints and %d destinations",
            spec ~= nil and spec.hasRearWall == false and "drive-through" or "bunker",
            #wayPoints,
            #mapMarkers
        )
    end
end
