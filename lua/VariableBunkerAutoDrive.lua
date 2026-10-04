VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local CONFIG_NAME = "VariableBunkerAutoDrive"
local ENABLED_CONFIGURATION = 2
local LANE_WIDTH = 5
local FRONT_APPROACH = 10
local REAR_CLEARANCE = 5
local FRONT_CONNECTION_OFFSET = 5
local WAYPOINT_SPACING = 3

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

function Bunker:VariableBunkerCreateAutoDriveCourse()
    local spec = self.spec_VariableBunker
    local width = spec ~= nil and spec.widthMeters or 10
    local length = spec ~= nil and spec.lengthMeters or 40
    local laneCount = math.max(1, math.floor(width / LANE_WIDTH + 0.0001))
    local laneSpacing = width / laneCount
    local front = -length * 0.5 - FRONT_APPROACH
    local rear = length * 0.5 - REAR_CLEARANCE
    local segmentCount = math.max(1, math.ceil((rear - front) / WAYPOINT_SPACING))
    local baseId = ADGraphManager:getWayPointsCount()
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
                y = AutoDrive:getTerrainHeightAtWorldPos(worldX, worldZ),
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

    local centerIndex = findClosestIndex(zValues, 0)
    local frontIndex = findClosestIndex(zValues, -length * 0.5 - FRONT_CONNECTION_OFFSET)
    for lane = 1, laneCount - 1 do
        connectWaypoints(wayPoints, lanes[lane][centerIndex], lanes[lane + 1][centerIndex])
        connectWaypoints(wayPoints, lanes[lane][frontIndex], lanes[lane + 1][frontIndex])
    end

    local existingMarkers = ADGraphManager:getMapMarkers()
    local markerOffset = #existingMarkers
    local mapMarkers = {}
    for lane = 1, laneCount do
        mapMarkers[lane] = {
            id = wayPoints[lanes[lane][1]].id,
            name = string.format("%d_VariableBunker %d", markerOffset + lane, lane),
        }
    end

    return wayPoints, mapMarkers
end

function Bunker:onFinalizePlacement()
    if not self.isServer or not self:VariableBunkerHasAutoDriveCourse() then
        return
    end
    if
        AutoDrive == nil
        or ADGraphManager == nil
        or AutoDrivePlaceableData == nil
        or AutoDrivePlaceableData.active ~= true
        or CreatePlaceableEvent == nil
        or CreatePlaceableEvent.sendEvent == nil
    then
        Logging.warning("[VariableBunker] AutoDrive course requested, but AutoDrive is not active")
        return
    end

    local wayPoints, mapMarkers = self:VariableBunkerCreateAutoDriveCourse()
    if #wayPoints > 0 and #mapMarkers > 0 then
        CreatePlaceableEvent.sendEvent(wayPoints, mapMarkers)
    end
end
