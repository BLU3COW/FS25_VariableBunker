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

local function getAutoDriveApi()
    local environment = getfenv(0).FS25_AutoDrive
    local autoDrive = AutoDrive or (environment ~= nil and environment.AutoDrive or nil)
    local graphManager = ADGraphManager or (environment ~= nil and environment.ADGraphManager or nil)
    local placeableData = AutoDrivePlaceableData or (environment ~= nil and environment.AutoDrivePlaceableData or nil)
    return autoDrive, graphManager, placeableData
end

local function addUnique(values, value)
    for _, current in ipairs(values) do
        if current == value then
            return
        end
    end
    table.insert(values, value)
end

local function connectWaypoints(wayPoints, firstIndex, secondIndex)
    local first = wayPoints[firstIndex]
    local second = wayPoints[secondIndex]
    addUnique(first.out, second.id)
    addUnique(first.incoming, second.id)
    addUnique(second.out, first.id)
    addUnique(second.incoming, first.id)
end

local function findClosestIndex(zValues, target)
    local closestIndex = 1
    local closestDistance = math.huge
    for index, value in ipairs(zValues) do
        local distance = math.abs(value - target)
        if distance < closestDistance then
            closestDistance = distance
            closestIndex = index
        end
    end
    return closestIndex
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
    local laneCount = math.max(1, math.floor(width / LANE_WIDTH + 0.0001))
    local laneSpacing = width / laneCount
    local front = -length * 0.5 - FRONT_APPROACH
    local rear = length * 0.5 - REAR_CLEARANCE
    local segmentCount = math.max(1, math.ceil((rear - front) / WAYPOINT_SPACING))
    local baseId = graphManager:getWayPointsCount()
    local wayPoints = {}
    local lanes = {}
    local zValues = {}

    for step = 0, segmentCount do
        zValues[step + 1] = front + (rear - front) * step / segmentCount
    end

    for lane = 1, laneCount do
        local localX = -width * 0.5 + laneSpacing * (lane - 0.5)
        lanes[lane] = {}
        for zIndex, localZ in ipairs(zValues) do
            local worldX, _, worldZ = localToWorld(self.rootNode, localX, 0, localZ)
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
            lanes[lane][zIndex] = waypointIndex
        end
    end

    for lane = 1, laneCount do
        for index = 1, #lanes[lane] - 1 do
            connectWaypoints(wayPoints, lanes[lane][index], lanes[lane][index + 1])
        end
    end

    local nearFrontIndex = findClosestIndex(zValues, -length * 0.5 - NEAR_FRONT_CONNECTION_OFFSET)
    local farFrontIndex = findClosestIndex(zValues, -length * 0.5 - FAR_FRONT_CONNECTION_OFFSET)
    for lane = 1, laneCount - 1 do
        connectWaypoints(wayPoints, lanes[lane][nearFrontIndex], lanes[lane + 1][nearFrontIndex])
        connectWaypoints(wayPoints, lanes[lane][farFrontIndex], lanes[lane + 1][farFrontIndex])
    end

    local existingMarkers = graphManager:getMapMarkers()
    local markerOffset = #existingMarkers
    local mapMarkers = {}
    for lane = 1, laneCount do
        mapMarkers[lane] = {
            id = wayPoints[lanes[lane][#lanes[lane]]].id,
            name = string.format("%d_VariableBunker %d", markerOffset + lane, lane),
        }
    end

    return wayPoints, mapMarkers
end

function Bunker:onFinalizePlacement()
    if not self.isServer or not self:VariableBunkerHasAutoDriveCourse() then
        return
    end
    local autoDrive, graphManager, placeableData = getAutoDriveApi()
    if
        autoDrive == nil
        or graphManager == nil
        or placeableData == nil
        or placeableData.active ~= true
        or placeableData.createPlaceable == nil
    then
        Logging.warning("[VariableBunker] AutoDrive course requested, but FS25_AutoDrive is not loaded or active")
        return
    end

    local wayPoints, mapMarkers = self:VariableBunkerCreateAutoDriveCourse(autoDrive, graphManager)
    if #wayPoints > 0 and #mapMarkers > 0 then
        placeableData:createPlaceable(wayPoints, mapMarkers)
        Logging.info(
            "[VariableBunker] Created AutoDrive course with %d waypoints and %d destinations",
            #wayPoints,
            #mapMarkers
        )
    end
end
