VariableBunkerStorage = {}

local VariableBunkerStorage_mt = Class(VariableBunkerStorage, Object)
InitObjectClass(VariableBunkerStorage, "VariableBunkerStorage")

local MODE_INPUT = 1
local MODE_OUTPUT = 2
local MAX_BAND_LENGTH = 1
local LAYER_STEP = 0.5
local MAX_LAYER_PASSES = 4
local MAX_PENDING_LITERS = 250
local MIN_OUTPUT_CHUNK = 250
local FULL_RETRY_TIME = 2000
local FULL_CHECK_INTERVAL = 500
local FULL_HEIGHT_TOLERANCE = 0.15
local FULL_RELEASE_LITERS = 1000
local FULL_RELEASE_SHARE = 0.002
local SURFACE_ANGLE = math.rad(40)
local PIXEL_MARGIN = 0.01
local DEFAULT_WALL_CORE = 0.4
local DEFAULT_PIXEL_SIZE = 0.5
local FACE_APRON = 1
local FACE_HEIGHT_MARGIN = 0.5
local FACE_MAX_STEPS = 40
local DEBUG_DUMP_CELL = 0.5
local DEBUG_DUMP_CHARS = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local DEBUG_LABEL_STEP = 10

VariableBunkerStorage.MODE_INPUT = MODE_INPUT
VariableBunkerStorage.MODE_OUTPUT = MODE_OUTPUT

local function isDebug(category)
    local bunker = VariableBunker
    return bunker ~= nil and bunker.getIsDebugActive ~= nil and bunker.getIsDebugActive(category)
end

local function debugLog(category, text, ...)
    if isDebug(category) then
        VariableBunker.debugLog(category, text, ...)
    end
end

local function debugNumber(value)
    if value == nil then
        return "nil"
    end
    return string.format("%.3f", value)
end

local function getDensityPixelSize()
    local manager = g_densityMapHeightManager
    local size = manager ~= nil and manager.densityToWorldMap or nil
    if size == nil or size <= 0 then
        return DEFAULT_PIXEL_SIZE
    end
    return size
end

local function getLocalArea(rootNode, x0, x1, z0, z1)
    local sx, _, sz = localToWorld(rootNode, x0, 0, z0)
    local wx, _, wz = localToWorld(rootNode, x1, 0, z0)
    local hx, _, hz = localToWorld(rootNode, x0, 0, z1)
    return sx, sz, wx, wz, hx, hz
end

local function getLocalAreaFillLevel(rootNode, x0, x1, z0, z1, fillTypes)
    local sx, sz, wx, wz, hx, hz = getLocalArea(rootNode, x0, x1, z0, z1)
    local level = 0
    for _, fillType in ipairs(fillTypes) do
        level = level + DensityMapHeightUtil.getFillLevelAtArea(fillType, sx, sz, wx, wz, hx, hz)
    end
    return level
end

local heapModifiers = nil

local function getHeapModifiers()
    if heapModifiers == nil and DensityMapHeightUtil.terrainDetailHeightId ~= nil then
        local height = DensityMapModifier.new(
            DensityMapHeightUtil.terrainDetailHeightId,
            DensityMapHeightUtil.heightFirstChannel,
            DensityMapHeightUtil.heightNumChannels
        )
        local type = DensityMapModifier.new(
            DensityMapHeightUtil.terrainDetailHeightId,
            DensityMapHeightUtil.typeFirstChannel,
            DensityMapHeightUtil.typeNumChannels
        )
        heapModifiers = {
            height = height,
            type = type,
            aboveFilter = DensityMapFilter.new(height),
            emptyFilter = DensityMapFilter.new(height),
            typeFilters = {},
        }
        heapModifiers.emptyFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)
    end
    return heapModifiers
end

local function getHeapTypeFilter(modifiers, heightTypeIndex)
    local filter = modifiers.typeFilters[heightTypeIndex]
    if filter == nil then
        filter = DensityMapFilter.new(modifiers.type)
        filter:setValueCompareParams(DensityValueCompareType.EQUAL, heightTypeIndex)
        modifiers.typeFilters[heightTypeIndex] = filter
    end
    return filter
end

local function setHeapArea(modifiers, sx, sz, wx, wz, hx, hz)
    modifiers.height:setParallelogramWorldCoords(sx, sz, wx, wz, hx, hz, DensityCoordType.POINT_POINT_POINT)
    modifiers.type:setParallelogramWorldCoords(sx, sz, wx, wz, hx, hz, DensityCoordType.POINT_POINT_POINT)
end

local function removeHeapTypeAtArea(sx, sz, wx, wz, hx, hz, heightTypeIndex)
    local modifiers = getHeapModifiers()
    if modifiers == nil then
        return 0
    end
    local filter = getHeapTypeFilter(modifiers, heightTypeIndex)
    setHeapArea(modifiers, sx, sz, wx, wz, hx, hz)
    local density = modifiers.height:executeGet(filter)
    modifiers.height:executeSet(0, filter)
    modifiers.type:executeSet(0, filter)
    return density or 0
end

local function capHeapAtArea(sx, sz, wx, wz, hx, hz, capUnits, heightTypes)
    local modifiers = getHeapModifiers()
    if modifiers == nil then
        return 0
    end
    setHeapArea(modifiers, sx, sz, wx, wz, hx, hz)
    modifiers.aboveFilter:setValueCompareParams(DensityValueCompareType.GREATER, capUnits)
    local removed = 0
    for _, heightType in ipairs(heightTypes) do
        local filter = getHeapTypeFilter(modifiers, heightType.index)
        local before = modifiers.height:executeGet(filter) or 0
        if before > 0 then
            modifiers.height:executeSet(capUnits, filter, modifiers.aboveFilter)
            local after = modifiers.height:executeGet(filter) or 0
            removed = removed + (before - after) * heightType.liters
            if capUnits == 0 then
                modifiers.type:executeSet(0, filter, modifiers.emptyFilter)
            end
        end
    end
    return removed
end

local function removeLocalArea(rootNode, x0, x1, z0, z1, fillTypes)
    if g_densityMapHeightManager == nil then
        return 0
    end
    local sx, sz, wx, wz, hx, hz = getLocalArea(rootNode, x0, x1, z0, z1)
    local removed = 0
    for _, fillType in ipairs(fillTypes) do
        local heightType = g_densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(fillType)
        if heightType ~= nil then
            local density = removeHeapTypeAtArea(sx, sz, wx, wz, hx, hz, heightType.index)
            removed = removed + density * g_densityMapHeightManager:getMinValidLiterValue(fillType)
        end
    end
    return removed
end

local function removeUntypedHeapAtArea(rootNode, x0, x1, z0, z1)
    local sx, sz, wx, wz, hx, hz = getLocalArea(rootNode, x0, x1, z0, z1)
    return removeHeapTypeAtArea(sx, sz, wx, wz, hx, hz, 0)
end

local function getWallCore(placeable)
    local spec = placeable.spec_VariableBunker
    return spec ~= nil and spec.wallCoreThickness or DEFAULT_WALL_CORE
end

local function getRemovableFillTypes(bunkerSilo, fillTypeIndex)
    local fillTypes = { fillTypeIndex }
    local fermentingFillType = bunkerSilo.fermentingFillType
    if
        fillTypeIndex == FillType.SILAGE
        and fermentingFillType ~= nil
        and fermentingFillType ~= FillType.UNKNOWN
        and fermentingFillType ~= fillTypeIndex
    then
        table.insert(fillTypes, fermentingFillType)
    end
    return fillTypes
end

local function getBunkerSilo(placeable)
    local spec = placeable ~= nil and placeable.spec_bunkerSilo or nil
    return spec ~= nil and spec.bunkerSilo or nil
end

local function getMissionTime()
    return g_currentMission ~= nil and g_currentMission.time or nil
end

local function getAreaFillLevel(area, fillTypeIndex)
    if area == nil or fillTypeIndex == nil or fillTypeIndex == FillType.UNKNOWN then
        return 0
    end
    return DensityMapHeightUtil.getFillLevelAtArea(fillTypeIndex, area.sx, area.sz, area.wx, area.wz, area.hx, area.hz)
end

local function updateMeasuredFillLevel(bunkerSilo)
    bunkerSilo:updateFillLevel()
    bunkerSilo.variableBunkerFillLevelUpdateTime = getMissionTime()
end

local function getCurrentFillLevel(bunkerSilo)
    local missionTime = getMissionTime()
    if bunkerSilo.isServer and (missionTime == nil or bunkerSilo.variableBunkerFillLevelUpdateTime ~= missionTime) then
        updateMeasuredFillLevel(bunkerSilo)
    end
    return bunkerSilo.fillLevel or 0
end

local function getMapHeightLimit()
    local getDensityMapMaxHeightFunction = getfenv(0).getDensityMapMaxHeight
    if
        getDensityMapMaxHeightFunction ~= nil
        and DensityMapHeightUtil ~= nil
        and DensityMapHeightUtil.terrainDetailHeightId ~= nil
    then
        return getDensityMapMaxHeightFunction(DensityMapHeightUtil.terrainDetailHeightId)
    end
    return nil
end

local function getSurfaceSlope(fillTypeIndex)
    local heightType = g_densityMapHeightManager ~= nil
            and g_densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(fillTypeIndex)
        or nil
    local angle = heightType ~= nil and heightType.maxSurfaceAngle or SURFACE_ANGLE
    return math.tan(angle)
end

local function getCapacityForDimensions(width, length, height, openEnds)
    local mapHeightLimit = getMapHeightLimit()
    local fillHeight = mapHeightLimit ~= nil and math.min(height, mapHeightLimit) or height
    local count = math.max(math.ceil(length / MAX_BAND_LENGTH), 1)
    local bandLength = length / count
    local rampStep = bandLength * math.tan(SURFACE_ANGLE)
    local area = 0
    for index = 1, count do
        local bandsToOpenEnd = count - index
        if openEnds > 1 then
            bandsToOpenEnd = math.min(bandsToOpenEnd, index - 1)
        end
        area = area + math.min(bandsToOpenEnd * rampStep, fillHeight) * bandLength
    end
    return math.max(width * area * 1000, 0)
end

local function getEstimatedCapacity(placeable)
    local spec = placeable.spec_VariableBunker
    if spec == nil then
        return 0
    end
    local openEnds = spec.hasRearWall and 1 or 2
    return getCapacityForDimensions(spec.widthMeters or 0, spec.lengthMeters or 0, spec.heightMeters or 0, openEnds)
end

VariableBunkerStorage.getMapHeightLimit = getMapHeightLimit
VariableBunkerStorage.getCapacityForDimensions = getCapacityForDimensions
VariableBunkerStorage.getEstimatedCapacity = getEstimatedCapacity

local function createBands(placeable)
    local spec = placeable.spec_VariableBunker
    local rootNode = placeable.rootNode
    local width = spec ~= nil and spec.widthMeters or 0
    local length = spec ~= nil and spec.lengthMeters or 0
    if rootNode == nil or width < 0.001 or length < 0.001 then
        return {}
    end
    local count = math.max(math.ceil(length / MAX_BAND_LENGTH), 1)
    local bandLength = length / count
    local radius = bandLength * 0.5
    local halfWidth = width * 0.5
    local lineHalfWidth = math.max(halfWidth - radius, 0)
    local bands = {}
    for index = 1, count do
        local startZ = length * 0.5 - (index - 1) * bandLength
        local endZ = startZ - bandLength
        local centerZ = (startZ + endZ) * 0.5
        local band = {
            index = index,
            centerZ = centerZ,
            startZ = startZ,
            endZ = endZ,
            halfWidth = halfWidth,
            length = bandLength,
            radius = radius,
            inputOffsetKey = "input_" .. index,
        }
        band.sx, band.sy, band.sz = localToWorld(rootNode, halfWidth, 0, startZ)
        band.wx, band.wy, band.wz = localToWorld(rootNode, -halfWidth, 0, startZ)
        band.hx, band.hy, band.hz = localToWorld(rootNode, halfWidth, 0, endZ)
        band.lsx, band.lsy, band.lsz = localToWorld(rootNode, lineHalfWidth, 0, centerZ)
        band.lex, band.ley, band.lez = localToWorld(rootNode, -lineHalfWidth, 0, centerZ)
        band.samples = {}
        for _, sampleX in ipairs({ -lineHalfWidth, 0, lineHalfWidth }) do
            local x, y, z = localToWorld(rootNode, sampleX, 0, centerZ)
            table.insert(band.samples, { x = x, y = y, z = z })
        end
        table.insert(bands, band)
    end
    return bands
end

local function getBands(storage)
    if storage.bands == nil then
        storage.bands = createBands(storage.placeable)
    end
    return storage.bands
end

local function getBandHeightLimit(placeable, bands, index, fillTypeIndex)
    local spec = placeable.spec_VariableBunker
    local count = #bands
    local bandsToOpenEnd = count - index
    if not spec.hasRearWall then
        bandsToOpenEnd = math.min(bandsToOpenEnd, index - 1)
    end
    local limit = bandsToOpenEnd * bands[index].length * getSurfaceSlope(fillTypeIndex)
    return math.min(limit, spec.heightMeters or 0)
end

local function addAtBand(storage, band, liters, fillTypeIndex, lineHeight)
    if liters < 0.001 then
        return 0
    end
    local _, topY, _ = localToWorld(storage.placeable.rootNode, 0, lineHeight, 0)
    local moved, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(
        nil,
        liters,
        fillTypeIndex,
        band.lsx,
        topY,
        band.lsz,
        band.lex,
        topY,
        band.lez,
        band.radius,
        band.radius,
        storage.lineOffsets[band.inputOffsetKey],
        true,
        nil,
        false,
        true
    )
    storage.lineOffsets[band.inputOffsetKey] = lineOffset
    return math.abs(moved)
end

local function getDebugCellChar(thickness)
    local decimeters = math.floor((thickness or 0) * 10 + 0.5)
    if decimeters <= 0 then
        return "."
    end
    if decimeters > #DEBUG_DUMP_CHARS then
        return "#"
    end
    return string.sub(DEBUG_DUMP_CHARS, decimeters, decimeters)
end

local function getDebugFillTypes(bunkerSilo)
    local fillTypes = {}
    local seen = {}
    for _, fillType in ipairs({ bunkerSilo.inputFillType, bunkerSilo.fermentingFillType, bunkerSilo.outputFillType }) do
        if fillType ~= nil and fillType ~= FillType.UNKNOWN and not seen[fillType] then
            seen[fillType] = true
            table.insert(fillTypes, fillType)
        end
    end
    return fillTypes
end

local function getDebugBandLevel(bunkerSilo, band)
    local level = 0
    for _, fillType in ipairs(getDebugFillTypes(bunkerSilo)) do
        level = level + getAreaFillLevel(band, fillType)
    end
    return level
end

local function getDebugStorages(placeable)
    local spec = placeable.spec_VariableBunker
    if spec == nil then
        return nil, nil
    end
    return spec.inputStorage, spec.outputStorage
end

local function getDebugBands(placeable)
    local inputStorage, outputStorage = getDebugStorages(placeable)
    local storage = outputStorage or inputStorage
    if storage ~= nil then
        return getBands(storage)
    end
    return createBands(placeable)
end

function VariableBunkerStorage.debugDump(placeable, reason)
    local spec = placeable ~= nil and placeable.spec_VariableBunker or nil
    local bunkerSilo = getBunkerSilo(placeable)
    local rootNode = placeable ~= nil and placeable.rootNode or nil
    if spec == nil or bunkerSilo == nil or rootNode == nil then
        return
    end
    local width = spec.widthMeters or 0
    local halfWidth = width * 0.5
    local inputStorage, outputStorage = getDebugStorages(placeable)
    local bands = getDebugBands(placeable)
    local inputBand = inputStorage ~= nil and inputStorage.inputBandIndex or nil
    local faceZ = outputStorage ~= nil and outputStorage.faceZ or nil
    local x, _, z = getWorldTranslation(rootNode)
    VariableBunker.debugLog(
        "dump",
        "begin (%s) '%s' at %.1f %.1f, %s %sx%sx%s m, state %s, fill level %.0f l, compacted %.0f l, bands %d",
        tostring(reason),
        tostring(placeable:getName()),
        x,
        z,
        spec.hasRearWall and "bunker" or "drive-through",
        tostring(spec.widthMeters),
        tostring(spec.lengthMeters),
        tostring(spec.heightMeters),
        tostring(bunkerSilo.state),
        bunkerSilo.fillLevel or 0,
        bunkerSilo.compactedFillLevel or 0,
        #bands
    )
    if inputStorage ~= nil then
        VariableBunker.debugLog(
            "dump",
            "input: band %s, layer %s m, pending %.0f l, full latch %s, exhausted %s",
            tostring(inputBand),
            debugNumber(inputStorage.layerHeight),
            inputStorage.pendingLiters or 0,
            debugNumber(inputStorage.fullFillLevel),
            tostring(inputStorage.fillExhausted)
        )
    end
    if outputStorage ~= nil then
        VariableBunker.debugLog(
            "dump",
            "output: face at %s m, silage buffer %.0f l",
            debugNumber(faceZ),
            outputStorage.outputBuffers[FillType.SILAGE] or 0
        )
    end
    VariableBunker.debugLog(
        "dump",
        "rows from band 1 (rear wall or exit) to the entrance, columns from the left to the right wall seen from the entrance, %.1f m cells",
        DEBUG_DUMP_CELL
    )
    VariableBunker.debugLog(
        "dump",
        "thickness in dm: . = 0, 1-9, A-Z = 10-35, a-z = 36-61, # = more; > input band, < foot of the face"
    )
    local columns = math.max(math.floor(width / DEBUG_DUMP_CELL + 0.5), 1)
    local length = spec.lengthMeters or 0
    local outerX = halfWidth + DEBUG_DUMP_CELL * 0.5
    local function getCell(cellX, cellZ)
        local wx, wy, wz = localToWorld(rootNode, cellX, 0, cellZ)
        local _, thickness = DensityMapHeightUtil.getHeightAtWorldPos(wx, wy, wz)
        return getDebugCellChar(thickness)
    end
    local function getRow(cellZ)
        local cells = {}
        for column = 1, columns do
            cells[column] = getCell(halfWidth - (column - 0.5) * width / columns, cellZ)
        end
        return string.format("%s|%s|%s", getCell(outerX, cellZ), table.concat(cells), getCell(-outerX, cellZ))
    end
    VariableBunker.debugLog("dump", "outer columns and the rear row lie under the wall core")
    if spec.hasRearWall then
        VariableBunker.debugLog("dump", "rear  %s", getRow(length * 0.5 + DEBUG_DUMP_CELL * 0.5))
    end
    for index, band in ipairs(bands) do
        local rows = math.max(math.floor(band.length / DEBUG_DUMP_CELL + 0.5), 1)
        local startZ = length * 0.5 - (index - 1) * band.length
        local hasFace = faceZ ~= nil and faceZ <= band.startZ and faceZ > band.endZ
        local marker = (index == inputBand and ">" or " ") .. (hasFace and "<" or " ")
        for row = 1, rows do
            local cellZ = startZ - (row - 0.5) * band.length / rows
            if row == 1 then
                VariableBunker.debugLog(
                    "dump",
                    "b%03d%s %s %.0f l",
                    index,
                    marker,
                    getRow(cellZ),
                    getDebugBandLevel(bunkerSilo, band)
                )
            else
                VariableBunker.debugLog("dump", "%s%s", string.rep(" ", 6), getRow(cellZ))
            end
        end
    end
    VariableBunker.debugLog("dump", "end")
end

local function drawDebugCrossLine(rootNode, halfWidth, y, z, red, green, blue)
    local x1, y1, z1 = localToWorld(rootNode, halfWidth, y, z)
    local x2, y2, z2 = localToWorld(rootNode, -halfWidth, y, z)
    drawDebugLine(x1, y1, z1, red, green, blue, x2, y2, z2, red, green, blue)
    return x1, y1, z1, x2, y2, z2
end

function VariableBunkerStorage.debugDraw(placeable)
    local spec = placeable ~= nil and placeable.spec_VariableBunker or nil
    local rootNode = placeable ~= nil and placeable.rootNode or nil
    if spec == nil or rootNode == nil or drawDebugLine == nil then
        return
    end
    local halfWidth = (spec.widthMeters or 0) * 0.5
    local halfLength = (spec.lengthMeters or 0) * 0.5
    local top = (spec.heightMeters or 0) + 0.3
    local corners = {
        { halfWidth, halfLength },
        { -halfWidth, halfLength },
        { -halfWidth, -halfLength },
        { halfWidth, -halfLength },
    }
    for index, corner in ipairs(corners) do
        local nextCorner = corners[index % #corners + 1]
        local x1, y1, z1 = localToWorld(rootNode, corner[1], top, corner[2])
        local x2, y2, z2 = localToWorld(rootNode, nextCorner[1], top, nextCorner[2])
        drawDebugLine(x1, y1, z1, 1, 1, 1, x2, y2, z2, 1, 1, 1)
    end
    local bands = getDebugBands(placeable)
    for index, band in ipairs(bands) do
        if index == 1 or index == #bands or index % DEBUG_LABEL_STEP == 0 then
            local x, y, z = localToWorld(rootNode, halfWidth, top, band.centerZ)
            Utils.renderTextAtWorldPosition(x, y, z, string.format("b%d", index), 0.015, 0)
        end
    end
    local inputStorage, outputStorage = getDebugStorages(placeable)
    local inputBand = inputStorage ~= nil and bands[inputStorage.inputBandIndex or 0] or nil
    if inputBand ~= nil then
        local lineHeight = spec.hasRearWall and (spec.heightMeters or 0) or (inputStorage.layerHeight or LAYER_STEP)
        local x, y, z = drawDebugCrossLine(rootNode, halfWidth, lineHeight, inputBand.centerZ, 0, 1, 0)
        Utils.renderTextAtWorldPosition(
            x,
            y + 0.5,
            z,
            string.format("IN b%d %.1f m", inputBand.index, lineHeight),
            0.015,
            0
        )
    end
    local faceZ = outputStorage ~= nil and outputStorage.faceZ or nil
    if faceZ ~= nil and faceZ > -halfLength - 1 and faceZ < halfLength + 1 then
        local _, _, _, x, y, z = drawDebugCrossLine(rootNode, halfWidth, 0.2, faceZ, 1, 0, 0)
        Utils.renderTextAtWorldPosition(x, y + 0.5, z, string.format("FACE %.1f m", faceZ), 0.015, 0)
    end
end

function VariableBunkerStorage.new(placeable, mode, customMt)
    local self = Object.new(placeable.isServer, placeable.isClient, customMt or VariableBunkerStorage_mt)
    self.placeable = placeable
    self.mode = mode
    self.rootNode = placeable.rootNode
    self.isExtension = false
    self.unloadingStations = {}
    self.loadingStations = {}
    self.lineOffsets = {}
    self.bands = nil
    self.inputBandIndex = 1
    self.pendingLiters = 0
    self.fullUntilTime = nil
    self.fullFillLevel = nil
    self.fillExhausted = false
    self.fullCheckTime = nil
    self.fullCheckResult = false
    self.openBandIndex = 1
    self.layerHeight = nil
    self.faceZ = nil
    self.outputBuffers = {}
    self.reportedFillLevels = {}
    self.reportedFillLevelTime = nil
    self.wallLevel = 0
    self.wallLevelTime = nil
    self.removalWarningShown = false
    self.fillTypes = {}
    if mode == MODE_INPUT then
        self.fillTypes[FillType.CHAFF] = true
    else
        self.fillTypes[FillType.SILAGE] = true
    end
    return self
end

function VariableBunkerStorage:delete()
    self.placeable = nil
    VariableBunkerStorage:superClass().delete(self)
end

function VariableBunkerStorage:getIsInputEnabled()
    local settings = VariableBunker ~= nil and VariableBunker.settings or nil
    return settings == nil or settings.allowInputStation ~= false
end

function VariableBunkerStorage:getIsOutputEnabled()
    local settings = VariableBunker ~= nil and VariableBunker.settings or nil
    return settings == nil or settings.allowOutputStation ~= false
end

function VariableBunkerStorage:getIsFillTypeSupported(fillTypeIndex)
    return self.fillTypes[fillTypeIndex] == true
end

function VariableBunkerStorage:getSupportedFillTypes()
    return self.fillTypes
end

function VariableBunkerStorage:getIsFillTypeAvailable(bunkerSilo, fillTypeIndex)
    if self.mode == MODE_INPUT and fillTypeIndex == FillType.CHAFF then
        return bunkerSilo.state == BunkerSilo.STATE_FILL
    end
    if self.mode == MODE_OUTPUT and fillTypeIndex == FillType.SILAGE then
        return bunkerSilo.state == BunkerSilo.STATE_FERMENTED or bunkerSilo.state == BunkerSilo.STATE_DRAIN
    end
    return false
end

function VariableBunkerStorage:getOutputBuffer(bunkerSilo, fillTypeIndex)
    local buffer = self.outputBuffers[fillTypeIndex] or 0
    if buffer > 0 and not self:getIsFillTypeAvailable(bunkerSilo, fillTypeIndex) then
        self.outputBuffers[fillTypeIndex] = 0
        return 0
    end
    return buffer
end

function VariableBunkerStorage:getMeasuredFillLevel(bunkerSilo)
    local base = getCurrentFillLevel(bunkerSilo)
    if not self.isServer then
        return base
    end
    local missionTime = getMissionTime()
    if missionTime ~= nil and self.wallLevelTime == missionTime then
        return math.max(self.wallLevel or 0, base)
    end
    local bands = getBands(self)
    local first = bands[1]
    local last = bands[#bands]
    local fullLevel = 0
    if first ~= nil and last ~= nil then
        local state = bunkerSilo.state
        local types = {}
        if state == BunkerSilo.STATE_FILL then
            types = { bunkerSilo.inputFillType }
        elseif state == BunkerSilo.STATE_CLOSED then
            types = { bunkerSilo.fermentingFillType }
        elseif state == BunkerSilo.STATE_FERMENTED or state == BunkerSilo.STATE_DRAIN then
            types = { bunkerSilo.fermentingFillType, bunkerSilo.outputFillType }
        end
        local area = { sx = first.sx, sz = first.sz, wx = first.wx, wz = first.wz, hx = last.hx, hz = last.hz }
        for _, fillType in ipairs(types) do
            fullLevel = fullLevel + getAreaFillLevel(area, fillType)
        end
    end
    self.wallLevel = fullLevel
    self.wallLevelTime = missionTime
    return math.max(fullLevel, base)
end

function VariableBunkerStorage:getFillLevel(fillTypeIndex)
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil or not self:getIsFillTypeSupported(fillTypeIndex) then
        return 0
    end
    if self.mode == MODE_OUTPUT and not self:getIsOutputEnabled() then
        return 0
    end
    if not self:getIsFillTypeAvailable(bunkerSilo, fillTypeIndex) then
        return 0
    end
    local missionTime = getMissionTime()
    if missionTime ~= nil and self.reportedFillLevelTime == missionTime then
        local reported = self.reportedFillLevels[fillTypeIndex]
        if reported ~= nil then
            return reported
        end
    end
    if self.mode == MODE_INPUT then
        return self:getMeasuredFillLevel(bunkerSilo) + self.pendingLiters
    end
    return self:getMeasuredFillLevel(bunkerSilo) + self:getOutputBuffer(bunkerSilo, fillTypeIndex)
end

function VariableBunkerStorage:getFillLevels()
    local fillLevels = {}
    for fillTypeIndex in pairs(self.fillTypes) do
        fillLevels[fillTypeIndex] = self:getFillLevel(fillTypeIndex)
    end
    return fillLevels
end

function VariableBunkerStorage:getCapacity(fillTypeIndex)
    if not self:getIsFillTypeSupported(fillTypeIndex) then
        return 0
    end
    return getEstimatedCapacity(self.placeable)
end

function VariableBunkerStorage:getIsBandFull(bands, index, mapHeightLimit)
    local limit = getBandHeightLimit(self.placeable, bands, index, FillType.CHAFF)
    if mapHeightLimit ~= nil then
        limit = math.min(limit, mapHeightLimit)
    end
    if limit < LAYER_STEP * 0.5 then
        return true
    end
    for _, sample in ipairs(bands[index].samples) do
        local _, thickness = DensityMapHeightUtil.getHeightAtWorldPos(sample.x, sample.y, sample.z)
        if (thickness or 0) < limit - FULL_HEIGHT_TOLERANCE then
            return false
        end
    end
    return true
end

function VariableBunkerStorage:getIsGeometricallyFull()
    local missionTime = getMissionTime()
    if missionTime ~= nil and self.fullCheckTime ~= nil and missionTime - self.fullCheckTime < FULL_CHECK_INTERVAL then
        return self.fullCheckResult
    end
    self.fullCheckTime = missionTime
    local bands = getBands(self)
    local bandCount = #bands
    local isFull = bandCount > 0
    if isFull then
        local mapHeightLimit = getMapHeightLimit()
        local index = math.min(self.openBandIndex, bandCount)
        for _ = 1, bandCount do
            if not self:getIsBandFull(bands, index, mapHeightLimit) then
                self.openBandIndex = index
                isFull = false
                break
            end
            index = index % bandCount + 1
        end
    end
    self.fullCheckResult = isFull
    return isFull
end

local function reportFreeCapacity(storage, reason, freeCapacity)
    if storage.debugFreeCapacityReason ~= reason then
        storage.debugFreeCapacityReason = reason
        debugLog("stations", "unloading station capacity: %s", reason)
    end
    return freeCapacity
end

function VariableBunkerStorage:getFreeCapacity(fillTypeIndex)
    if self.mode ~= MODE_INPUT or not self:getIsInputEnabled() or fillTypeIndex ~= FillType.CHAFF then
        return 0
    end
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil or bunkerSilo.state ~= BunkerSilo.STATE_FILL then
        self.fullFillLevel = nil
        return reportFreeCapacity(self, "closed, silo is not in the fill state", 0)
    end
    if self.fullFillLevel ~= nil then
        local releaseLiters = math.max(FULL_RELEASE_LITERS, self.fullFillLevel * FULL_RELEASE_SHARE)
        if getCurrentFillLevel(bunkerSilo) > self.fullFillLevel - releaseLiters then
            return reportFreeCapacity(self, string.format("closed, full latch at %.0f l", self.fullFillLevel), 0)
        end
        self.fullFillLevel = nil
    end
    local missionTime = getMissionTime()
    if self.fullUntilTime ~= nil then
        if missionTime ~= nil and missionTime < self.fullUntilTime then
            return reportFreeCapacity(self, "closed, retry block after a failed placement", 0)
        end
        self.fullUntilTime = nil
    end
    if self:getIsGeometricallyFull() then
        return reportFreeCapacity(self, "closed, every band is geometrically full", 0)
    end
    return reportFreeCapacity(self, "open", math.huge)
end

local function getInitialLayerHeight(bunkerSilo)
    local area = bunkerSilo.bunkerSiloArea.inner
    local width = MathUtil.vector3Length(area.wx - area.sx, area.wy - area.sy, area.wz - area.sz)
    local length = MathUtil.vector3Length(area.hx - area.sx, area.hy - area.sy, area.hz - area.sz)
    local surface = width * length
    if surface < 0.001 then
        return LAYER_STEP
    end
    local averageHeight = (bunkerSilo.fillLevel or 0) / 1000 / surface
    return math.max(LAYER_STEP, math.ceil(averageHeight / LAYER_STEP) * LAYER_STEP)
end

function VariableBunkerStorage:fillBand(bands, index, liters, fillTypeIndex, lineHeight)
    local height = math.min(lineHeight, getBandHeightLimit(self.placeable, bands, index, fillTypeIndex))
    if height < LAYER_STEP * 0.5 then
        return 0
    end
    local band = bands[index]
    return addAtBand(self, band, liters, fillTypeIndex, height)
end

function VariableBunkerStorage:fillBandsToWallHeight(liters, fillTypeIndex)
    local bands = getBands(self)
    local bandCount = #bands
    if bandCount == 0 then
        return 0
    end
    local wallHeight = self.placeable.spec_VariableBunker.heightMeters
    local moved = 0
    local index = math.min(self.inputBandIndex, bandCount)
    local touched = isDebug("filling") and {} or nil
    for _ = 1, bandCount do
        local added = self:fillBand(bands, index, liters - moved, fillTypeIndex, wallHeight)
        moved = moved + added
        if touched ~= nil and added >= 0.001 then
            table.insert(touched, string.format("b%d:%.0f", index, added))
        end
        if liters - moved < 0.001 then
            break
        end
        index = index % bandCount + 1
    end
    self.inputBandIndex = index
    self.fillExhausted = liters - moved >= MAX_PENDING_LITERS
    if touched ~= nil then
        debugLog(
            "filling",
            "to wall height: request %.0f, placed %.0f, next band %d, exhausted %s, bands %s",
            liters,
            moved,
            index,
            tostring(self.fillExhausted),
            table.concat(touched, " ")
        )
    end
    return moved
end

function VariableBunkerStorage:getIsLayerComplete(bands, layerHeight, fillTypeIndex)
    local mapHeightLimit = getMapHeightLimit()
    local rootNode = self.placeable.rootNode
    for index, band in ipairs(bands) do
        local target = math.min(layerHeight, getBandHeightLimit(self.placeable, bands, index, fillTypeIndex))
        if mapHeightLimit ~= nil then
            target = math.min(target, mapHeightLimit)
        end
        if target >= LAYER_STEP * 0.5 then
            local _, targetY, _ = localToWorld(rootNode, 0, target, 0)
            for _, sample in ipairs(band.samples) do
                local height, thickness = DensityMapHeightUtil.getHeightAtWorldPos(sample.x, sample.y, sample.z)
                if
                    (height or 0) < targetY - FULL_HEIGHT_TOLERANCE
                    and (thickness or 0) < target - FULL_HEIGHT_TOLERANCE
                then
                    return false
                end
            end
        end
    end
    return true
end

function VariableBunkerStorage:fillBandsInLayers(bunkerSilo, liters, fillTypeIndex)
    local bands = getBands(self)
    local bandCount = #bands
    local maxHeight = self.placeable.spec_VariableBunker.heightMeters
    if bandCount == 0 or maxHeight == nil then
        return 0
    end
    if self.layerHeight == nil then
        self.layerHeight = math.min(getInitialLayerHeight(bunkerSilo), maxHeight)
    end
    local moved = 0
    local passes = 0
    local index = math.min(self.inputBandIndex, bandCount)
    local touched = isDebug("filling") and {} or nil
    local startLayerHeight = self.layerHeight
    while liters - moved >= 0.001 do
        local movedInPass = 0
        for _ = 1, bandCount do
            local added = self:fillBand(bands, index, liters - moved, fillTypeIndex, self.layerHeight)
            moved = moved + added
            movedInPass = movedInPass + added
            if touched ~= nil and added >= 0.001 then
                table.insert(touched, string.format("b%d:%.0f", index, added))
            end
            if liters - moved < 0.001 then
                break
            end
            index = index % bandCount + 1
        end
        if liters - moved < 0.001 then
            break
        end
        passes = passes + 1
        local isLayerComplete = self:getIsLayerComplete(bands, self.layerHeight, fillTypeIndex)
        if not isLayerComplete and movedInPass >= 0.001 then
            if passes >= MAX_LAYER_PASSES then
                break
            end
        elseif not isLayerComplete and liters - moved < MAX_PENDING_LITERS then
            break
        else
            if self.layerHeight >= maxHeight - 0.001 then
                self.fillExhausted = movedInPass < 0.001 and liters - moved >= MAX_PENDING_LITERS
                break
            end
            self.layerHeight = math.min(self.layerHeight + LAYER_STEP, maxHeight)
            passes = 0
            debugLog(
                "filling",
                "layer raised to %.1f m (complete %s, left %.0f l)",
                self.layerHeight,
                tostring(isLayerComplete),
                liters - moved
            )
        end
    end
    self.inputBandIndex = index
    if touched ~= nil then
        debugLog(
            "filling",
            "in layers: request %.0f, placed %.0f, layer %.1f -> %.1f m, passes %d, next band %d, exhausted %s, bands %s",
            liters,
            moved,
            startLayerHeight or 0,
            self.layerHeight or 0,
            passes,
            index,
            tostring(self.fillExhausted),
            table.concat(touched, " ")
        )
    end
    return moved
end

function VariableBunkerStorage:addMaterial(liters, fillTypeIndex)
    self.fillExhausted = false
    local bunkerSilo = getBunkerSilo(self.placeable)
    if
        bunkerSilo == nil
        or bunkerSilo.state ~= BunkerSilo.STATE_FILL
        or fillTypeIndex ~= FillType.CHAFF
        or not self:getIsInputEnabled()
    then
        return 0
    end
    if (bunkerSilo.fillLevel or 0) < 1 then
        if self.inputBandIndex ~= 1 or self.layerHeight ~= nil then
            debugLog("filling", "empty silo, filling starts again at band 1")
        end
        self.inputBandIndex = 1
        self.layerHeight = nil
    end
    if self.placeable.spec_VariableBunker.hasRearWall then
        return self:fillBandsToWallHeight(liters, fillTypeIndex)
    end
    return self:fillBandsInLayers(bunkerSilo, liters, fillTypeIndex)
end

function VariableBunkerStorage:openFermentedSide(bunkerSilo)
    if bunkerSilo.state == BunkerSilo.STATE_FERMENTED then
        self.faceZ = nil
        local area = bunkerSilo.bunkerSiloArea
        bunkerSilo:openSilo(area.hx + area.dwx * 0.5, area.hy + area.dwy * 0.5, area.hz + area.dwz * 0.5)
    end
end

function VariableBunkerStorage:getFaceGeometry(fillTypeIndex)
    local spec = self.placeable.spec_VariableBunker
    local wallCore = getWallCore(self.placeable)
    local halfLength = (spec.lengthMeters or 0) * 0.5
    local maxHeight = spec.heightMeters or 0
    local mapHeightLimit = getMapHeightLimit()
    if mapHeightLimit ~= nil then
        maxHeight = math.min(maxHeight, mapHeightLimit)
    end
    maxHeight = maxHeight + FACE_HEIGHT_MARGIN
    local slope = getSurfaceSlope(fillTypeIndex)
    return {
        frontZ = -halfLength - FACE_APRON,
        rearZ = halfLength + (spec.hasRearWall and wallCore or FACE_APRON),
        outerHalfWidth = (spec.widthMeters or 0) * 0.5 + wallCore + PIXEL_MARGIN,
        maxHeight = maxHeight,
        slope = slope,
        run = maxHeight / slope,
        pixel = getDensityPixelSize(),
    }
end

local function getFaceHeightTypes(bunkerSilo, fillTypeIndex)
    local manager = g_densityMapHeightManager
    local heightTypes = {}
    if manager == nil then
        return heightTypes
    end
    for _, fillType in ipairs(getRemovableFillTypes(bunkerSilo, fillTypeIndex)) do
        local heightType = manager:getDensityMapHeightTypeByFillTypeIndex(fillType)
        if heightType ~= nil then
            table.insert(heightTypes, { index = heightType.index, liters = manager:getMinValidLiterValue(fillType) })
        end
    end
    return heightTypes
end

function VariableBunkerStorage:findFaceStart(geometry, fillTypes)
    local rootNode = self.placeable.rootNode
    local z = geometry.frontZ
    while z < geometry.rearZ do
        local z1 = math.min(z + geometry.pixel, geometry.rearZ)
        local level = getLocalAreaFillLevel(
            rootNode,
            geometry.outerHalfWidth,
            -geometry.outerHalfWidth,
            z1 + PIXEL_MARGIN,
            z - PIXEL_MARGIN,
            fillTypes
        )
        if level >= 0.001 then
            return z - geometry.run
        end
        z = z1
    end
    return geometry.rearZ + geometry.run
end

function VariableBunkerStorage:cutFaceWindow(geometry, heightTypes, unitsPerMeter)
    local rootNode = self.placeable.rootNode
    local faceZ = self.faceZ
    local fromZ = math.max(faceZ - geometry.pixel, geometry.frontZ)
    local toZ = math.min(faceZ + geometry.run + geometry.pixel, geometry.rearZ)
    local removed = 0
    local row = math.floor((fromZ - geometry.frontZ) / geometry.pixel)
    while true do
        local z0 = geometry.frontZ + row * geometry.pixel
        if z0 >= toZ then
            break
        end
        local z1 = math.min(z0 + geometry.pixel, geometry.rearZ)
        local cap = math.max((z0 + z1) * 0.5 - faceZ, 0) * geometry.slope
        if cap < geometry.maxHeight then
            local sx, sz, wx, wz, hx, hz = getLocalArea(
                rootNode,
                geometry.outerHalfWidth,
                -geometry.outerHalfWidth,
                z1 + PIXEL_MARGIN,
                z0 - PIXEL_MARGIN
            )
            removed = removed + capHeapAtArea(sx, sz, wx, wz, hx, hz, math.floor(cap * unitsPerMeter), heightTypes)
        end
        row = row + 1
    end
    return removed
end

function VariableBunkerStorage:uncoverAtFace(bunkerSilo, geometry)
    if bunkerSilo.state ~= BunkerSilo.STATE_DRAIN or bunkerSilo.onChangedFillLevelCallback == nil then
        return
    end
    local rootNode = self.placeable.rootNode
    local topZ = math.min(self.faceZ + geometry.run, geometry.rearZ)
    local x, y, z = localToWorld(rootNode, 0, 0, topZ)
    bunkerSilo:onChangedFillLevelCallback(nil, -1, bunkerSilo.outputFillType, x, y, z)
    local fermentingFillType = bunkerSilo.fermentingFillType
    if fermentingFillType ~= nil and fermentingFillType ~= bunkerSilo.outputFillType then
        local sx, sz, wx, wz, hx, hz = getLocalArea(
            rootNode,
            geometry.outerHalfWidth,
            -geometry.outerHalfWidth,
            math.min(topZ + geometry.pixel, geometry.rearZ),
            math.max(self.faceZ - geometry.pixel, geometry.frontZ)
        )
        DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, fermentingFillType, bunkerSilo.outputFillType)
    end
end

function VariableBunkerStorage:removeMaterial(liters, fillTypeIndex)
    local bunkerSilo = getBunkerSilo(self.placeable)
    local manager = g_densityMapHeightManager
    if
        bunkerSilo == nil
        or manager == nil
        or not self:getIsOutputEnabled()
        or not self:getIsFillTypeAvailable(bunkerSilo, fillTypeIndex)
    then
        return 0
    end
    if fillTypeIndex == FillType.SILAGE then
        self:openFermentedSide(bunkerSilo)
    end
    local geometry = self:getFaceGeometry(fillTypeIndex)
    local heightTypes = getFaceHeightTypes(bunkerSilo, fillTypeIndex)
    local unitsPerMeter = manager.heightToDensityValue or 0
    if #heightTypes == 0 or unitsPerMeter <= 0 or getHeapModifiers() == nil then
        return 0
    end
    if self.faceZ == nil then
        self.faceZ = self:findFaceStart(geometry, getRemovableFillTypes(bunkerSilo, fillTypeIndex))
    end
    self:uncoverAtFace(bunkerSilo, geometry)
    local endZ = geometry.rearZ + geometry.run
    local step = 1 / unitsPerMeter / geometry.slope
    local removed = 0
    local steps = 0
    while removed < liters and self.faceZ < endZ and steps < FACE_MAX_STEPS do
        self.faceZ = math.min(self.faceZ + step, endZ)
        removed = removed + self:cutFaceWindow(geometry, heightTypes, unitsPerMeter)
        steps = steps + 1
    end
    debugLog(
        "extraction",
        "request %.0f, removed %.0f, face at %.2f m (%.2f to %.2f), %d steps",
        liters,
        removed,
        self.faceZ,
        geometry.frontZ,
        endZ,
        steps
    )
    return removed
end

function VariableBunkerStorage:setReportedFillLevel(fillTypeIndex, fillLevel)
    local missionTime = getMissionTime()
    if self.reportedFillLevelTime ~= missionTime then
        self.reportedFillLevels = {}
        self.reportedFillLevelTime = missionTime
    end
    self.reportedFillLevels[fillTypeIndex] = math.max(fillLevel, 0)
end

function VariableBunkerStorage:addFromStation(bunkerSilo, liters, fillTypeIndex)
    local request = liters + self.pendingLiters
    self.wallLevelTime = nil
    local placed = self:addMaterial(request, fillTypeIndex)
    local missing = math.max(request - placed, 0)
    local accepted = liters
    if missing > MAX_PENDING_LITERS then
        accepted = math.max(liters - (missing - MAX_PENDING_LITERS), 0)
        missing = MAX_PENDING_LITERS
        local missionTime = getMissionTime()
        self.fullUntilTime = missionTime ~= nil and missionTime + FULL_RETRY_TIME or nil
        debugLog(
            "stations",
            "unloading: %.0f l could not be placed, blocking for %d ms",
            request - placed,
            FULL_RETRY_TIME
        )
    end
    if self.fillExhausted then
        self.fullFillLevel = getCurrentFillLevel(bunkerSilo)
        debugLog("stations", "unloading: silo full, latched at %.0f l", self.fullFillLevel)
    end
    debugLog(
        "stations",
        "unloading: delivered %.0f, with credit %.0f, placed %.0f, accepted %.0f, credit now %.0f",
        liters,
        request,
        placed,
        accepted,
        missing
    )
    self.pendingLiters = missing
    if placed > 0 then
        updateMeasuredFillLevel(bunkerSilo)
    end
    return accepted, placed
end

function VariableBunkerStorage:takeForStation(bunkerSilo, liters, fillTypeIndex)
    local buffer = self:getOutputBuffer(bunkerSilo, fillTypeIndex)
    local fromBuffer = math.min(buffer, liters)
    self.wallLevelTime = nil
    buffer = buffer - fromBuffer
    local missing = liters - fromBuffer
    local removed = 0
    if missing > 0.001 then
        removed = self:removeMaterial(math.max(missing, MIN_OUTPUT_CHUNK), fillTypeIndex)
        if removed > 0 then
            updateMeasuredFillLevel(bunkerSilo)
        elseif not self.removalWarningShown and getCurrentFillLevel(bunkerSilo) > MIN_OUTPUT_CHUNK then
            self.removalWarningShown = true
            Logging.warning(
                "[VariableBunker] Extraction could not remove %s although %.0f l are stored (state %d)",
                tostring(g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)),
                getCurrentFillLevel(bunkerSilo),
                bunkerSilo.state or -1
            )
            if isDebug("dump") then
                VariableBunkerStorage.debugDump(self.placeable, "extraction failed")
            end
        end
    end
    local delivered = fromBuffer + math.min(removed, missing)
    self.outputBuffers[fillTypeIndex] = buffer + math.max(removed - missing, 0)
    debugLog(
        "stations",
        "loading: request %.0f, from buffer %.0f, removed %.0f, delivered %.0f, buffer now %.0f",
        liters,
        fromBuffer,
        removed,
        delivered,
        self.outputBuffers[fillTypeIndex]
    )
    return delivered, removed
end

function VariableBunkerStorage:setFillLevel(fillLevel, fillTypeIndex)
    if not self.isServer or not self:getIsFillTypeSupported(fillTypeIndex) then
        return
    end
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil then
        return
    end
    local oldFillLevel = self:getFillLevel(fillTypeIndex)
    local delta = fillLevel - oldFillLevel
    local changed = 0
    if self.mode == MODE_INPUT and delta > 0 then
        local accepted
        accepted, changed = self:addFromStation(bunkerSilo, delta, fillTypeIndex)
        self:setReportedFillLevel(fillTypeIndex, oldFillLevel + accepted)
    elseif self.mode == MODE_OUTPUT and delta < 0 then
        local delivered
        delivered, changed = self:takeForStation(bunkerSilo, -delta, fillTypeIndex)
        self:setReportedFillLevel(fillTypeIndex, oldFillLevel - delivered)
    end
    if changed > 0 then
        bunkerSilo:updateCompacting(bunkerSilo.compactedFillLevel)
        bunkerSilo:raiseDirtyFlags(bunkerSilo.bunkerSiloDirtyFlag)
    end
end

function VariableBunkerStorage:addUnloadingStation(station)
    self.unloadingStations[station] = station
end

function VariableBunkerStorage:removeUnloadingStation(station)
    self.unloadingStations[station] = nil
end

function VariableBunkerStorage:addLoadingStation(station)
    self.loadingStations[station] = station
end

function VariableBunkerStorage:removeLoadingStation(station)
    self.loadingStations[station] = nil
end

local function getFootprintArea(placeable)
    local spec = placeable.spec_VariableBunker
    local wallCore = getWallCore(placeable)
    local outerHalfWidth = (spec.widthMeters or 0) * 0.5 + wallCore + PIXEL_MARGIN
    local halfLength = (spec.lengthMeters or 0) * 0.5
    local rearZ = halfLength + (spec.hasRearWall and wallCore or 0) + PIXEL_MARGIN
    return outerHalfWidth, -outerHalfWidth, rearZ, -halfLength - PIXEL_MARGIN
end

local function clearEmptiedSilo(placeable)
    local rootNode = placeable.rootNode
    if placeable.spec_VariableBunker == nil or rootNode == nil then
        return
    end
    local x0, x1, z0, z1 = getFootprintArea(placeable)
    local sx, sz, wx, wz, hx, hz = getLocalArea(rootNode, x0, x1, z0, z1)
    DensityMapHeightUtil.clearArea(sx, sz, wx, wz, hx, hz)
    debugLog("extraction", "silo emptied by the base game, everything left inside the walls cleared")
end

function VariableBunkerStorage.cleanupLeftovers(placeable)
    local bunkerSilo = getBunkerSilo(placeable)
    local rootNode = placeable.rootNode
    if bunkerSilo == nil or rootNode == nil or placeable.spec_VariableBunker == nil then
        return
    end
    if bunkerSilo.state ~= BunkerSilo.STATE_FILL then
        return
    end
    local x0, x1, z0, z1 = getFootprintArea(placeable)
    local fillTypes = {}
    for _, fillType in ipairs({ bunkerSilo.fermentingFillType, bunkerSilo.outputFillType }) do
        if fillType ~= nil and fillType ~= FillType.UNKNOWN and fillType ~= bunkerSilo.inputFillType then
            table.insert(fillTypes, fillType)
        end
    end
    local removed = removeLocalArea(rootNode, x0, x1, z0, z1, fillTypes)
    local untyped = removeUntypedHeapAtArea(rootNode, x0, x1, z0, z1)
    if removed > 0 or untyped > 0 then
        debugLog(
            "extraction",
            "leftovers of an earlier extraction cleared: %.0f l covered or silage, %d untyped height units",
            removed,
            untyped
        )
    end
end

local function setBunkerSiloState(bunkerSilo, superFunc, state, ...)
    local oldState = bunkerSilo.state
    local result = superFunc(bunkerSilo, state, ...)
    if
        bunkerSilo.isServer
        and oldState == BunkerSilo.STATE_DRAIN
        and state == BunkerSilo.STATE_FILL
        and VariableBunker ~= nil
        and VariableBunker.activeSilos ~= nil
    then
        for placeable in pairs(VariableBunker.activeSilos) do
            if getBunkerSilo(placeable) == bunkerSilo then
                clearEmptiedSilo(placeable)
                break
            end
        end
    end
    return result
end

if BunkerSilo ~= nil and BunkerSilo.setState ~= nil and not VariableBunkerStorage.setStateHookInstalled then
    BunkerSilo.setState = Utils.overwrittenFunction(BunkerSilo.setState, setBunkerSiloState)
    VariableBunkerStorage.setStateHookInstalled = true
end

VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local COMPACTION_LITERS_PER_HOUR = 300000
local DIESEL_LITERS_PER_HOUR = 20
local WEAR_COST_PER_HOUR = 40
local DEFAULT_WAGE_PER_MS = 0.0005
local MS_PER_HOUR = 3600000
local MIN_REMAINING_LITERS = 1
local AREA_HALF_WIDTH = 6.5
local AREA_SILO_SIDE = 4
local AREA_FAR_SIDE = 9

local function getCompactionText(placeable, key)
    return g_i18n:getText(key, placeable ~= nil and placeable.customEnvironment or nil)
end

function Bunker.getIsCompactionServiceEnabled()
    return Bunker.settings == nil or Bunker.settings.allowCompactionService ~= false
end

function Bunker.getCompactionRemainingLiters(placeable)
    local bunkerSilo = getBunkerSilo(placeable)
    if bunkerSilo == nil or bunkerSilo.state ~= BunkerSilo.STATE_FILL then
        return 0
    end
    local fillLevel = bunkerSilo.fillLevel or 0
    if bunkerSilo.isServer then
        return math.max(fillLevel - (bunkerSilo.compactedFillLevel or 0), 0)
    end
    return math.max(fillLevel * (100 - (bunkerSilo.compactedPercent or 0)) / 100, 0)
end

local function getWagePerHour()
    local pricePerMs = DEFAULT_WAGE_PER_MS
    if AIJobFieldWork ~= nil and AIJobFieldWork.getPricePerMs ~= nil then
        pricePerMs = AIJobFieldWork.getPricePerMs(AIJobFieldWork) or pricePerMs
    end
    return pricePerMs * MS_PER_HOUR
end

function Bunker.getCompactionOffer(placeable, remaining)
    local bunkerSilo = getBunkerSilo(placeable)
    if bunkerSilo == nil or remaining < MIN_REMAINING_LITERS then
        return 0, 0
    end
    local hours = remaining / COMPACTION_LITERS_PER_HOUR
    local costMultiplier = EconomyManager.getCostMultiplier() or 1
    local dieselPrice = 0
    local economyManager = g_currentMission.economyManager
    if economyManager ~= nil then
        dieselPrice = economyManager:getCostPerLiter(FillType.DIESEL) or 0
    end
    local hourlyCost = (getWagePerHour() + WEAR_COST_PER_HOUR) * costMultiplier + DIESEL_LITERS_PER_HOUR * dieselPrice
    local factor = Bunker.settings ~= nil and Bunker.settings.compactionPriceFactor or 1
    debugLog(
        "compaction",
        "offer: %.0f l, %.2f h, hourly cost %.0f (cost multiplier %.2f, diesel %.2f/l), price factor %.2f",
        remaining,
        hours,
        hourlyCost,
        costMultiplier,
        dieselPrice,
        factor
    )
    return math.ceil(hours * hourlyCost * factor), hours
end

function Bunker.executeCompaction(placeable)
    local spec = placeable ~= nil and placeable.spec_VariableBunker or nil
    local bunkerSilo = getBunkerSilo(placeable)
    if
        spec == nil
        or not spec.hasCompactionService
        or not Bunker.getIsCompactionServiceEnabled()
        or bunkerSilo == nil
        or bunkerSilo.state ~= BunkerSilo.STATE_FILL
    then
        return false
    end
    bunkerSilo:updateFillLevel()
    local remaining = Bunker.getCompactionRemainingLiters(placeable)
    local price, hours = Bunker.getCompactionOffer(placeable, remaining)
    debugLog(
        "compaction",
        "service requested: fill level %.0f l, compacted %.0f l, remaining %.0f l, %.2f h, price %.0f",
        bunkerSilo.fillLevel or 0,
        bunkerSilo.compactedFillLevel or 0,
        remaining,
        hours or 0,
        price
    )
    if price <= 0 then
        return false
    end
    local farmId = placeable:getOwnerFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farm:getBalance() < price then
        debugLog("compaction", "service refused: farm %s cannot pay %.0f", tostring(farmId), price)
        return false
    end
    g_currentMission:addMoney(-price, farmId, MoneyType.AI, true, true)
    bunkerSilo:updateCompacting(bunkerSilo.fillLevel)
    debugLog("compaction", "service done: farm %s paid %.0f", tostring(farmId), price)
    return true
end

local VariableBunkerCompactionEvent = {}
local VariableBunkerCompactionEvent_mt = Class(VariableBunkerCompactionEvent, Event)
InitEventClass(VariableBunkerCompactionEvent, "VariableBunkerCompactionEvent")

function VariableBunkerCompactionEvent.emptyNew()
    return Event.new(VariableBunkerCompactionEvent_mt)
end

function VariableBunkerCompactionEvent.new(placeable)
    local self = VariableBunkerCompactionEvent.emptyNew()
    self.placeable = placeable
    return self
end

function VariableBunkerCompactionEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function VariableBunkerCompactionEvent:writeStream(streamId, _connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
end

function VariableBunkerCompactionEvent:run(connection)
    if connection:getIsServer() or self.placeable == nil then
        return
    end
    local farmId = self.placeable:getOwnerFarmId()
    if g_currentMission:getHasPlayerPermission(Farm.PERMISSION.HIRE_ASSISTANT, connection, farmId) then
        Bunker.executeCompaction(self.placeable)
    end
end

local function requestCompaction(placeable)
    if g_server ~= nil then
        Bunker.executeCompaction(placeable)
    else
        g_client:getServerConnection():sendEvent(VariableBunkerCompactionEvent.new(placeable))
    end
end

local function onCompactionDialogClosed(yes, placeable)
    if yes and placeable ~= nil and not placeable.isDeleted then
        requestCompaction(placeable)
    end
end

function Bunker.showCompactionDialog(placeable)
    local remaining = Bunker.getCompactionRemainingLiters(placeable)
    local price, hours = Bunker.getCompactionOffer(placeable, remaining)
    if price <= 0 then
        return
    end
    if not g_currentMission:getHasPlayerPermission(Farm.PERMISSION.HIRE_ASSISTANT) then
        InfoDialog.show(g_i18n:getText("shop_messageNoPermissionGeneral"))
        return
    end
    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if farm == nil or farm:getBalance() < price then
        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
        return
    end
    local text = string.format(
        getCompactionText(placeable, "dialog_VariableBunkerCompaction"),
        g_i18n:formatVolume(remaining, 0),
        g_i18n:formatNumber(hours, 1, true),
        g_i18n:formatMoney(price, 0, true, true)
    )
    YesNoDialog.show(
        onCompactionDialogClosed,
        nil,
        text,
        getCompactionText(placeable, "configuration_VariableBunkerCompaction"),
        nil,
        nil,
        nil,
        nil,
        nil,
        placeable
    )
end

local function getPlayerOnFootPosition()
    local player = g_localPlayer
    if player == nil or player:getIsInVehicle() then
        return nil
    end
    return player:getPosition()
end

local CompactionActivatable = {}
local CompactionActivatable_mt = Class(CompactionActivatable)

function CompactionActivatable.new(placeable)
    local self = setmetatable({}, CompactionActivatable_mt)
    self.placeable = placeable
    self.activateText = getCompactionText(placeable, "action_VariableBunkerCompaction")
    return self
end

function CompactionActivatable:getAreaNode()
    local spec = self.placeable.spec_VariableBunker
    return spec ~= nil and spec.inputStationRootNode or nil
end

function CompactionActivatable:getIsActivatable()
    local placeable = self.placeable
    local node = self:getAreaNode()
    if node == nil or placeable.isDeleted or g_currentMission == nil or not Bunker.getIsCompactionServiceEnabled() then
        return false
    end
    if not g_currentMission.accessHandler:canPlayerAccess(placeable) then
        return false
    end
    if Bunker.getCompactionRemainingLiters(placeable) < MIN_REMAINING_LITERS then
        return false
    end
    local x, y, z = getPlayerOnFootPosition()
    if x == nil then
        return false
    end
    local localX, _, localZ = worldToLocal(node, x, y, z)
    return math.abs(localX) <= AREA_HALF_WIDTH and localZ >= -AREA_SILO_SIDE and localZ <= AREA_FAR_SIDE
end

function CompactionActivatable:getDistance(x, y, z)
    local node = self:getAreaNode()
    if node == nil then
        return math.huge
    end
    local nodeX, nodeY, nodeZ = getWorldTranslation(node)
    return MathUtil.vector3Length(x - nodeX, y - nodeY, z - nodeZ)
end

function CompactionActivatable:run()
    Bunker.showCompactionDialog(self.placeable)
end

function Bunker.VariableBunkerFinalizeCompaction(self)
    local spec = self.spec_VariableBunker
    if spec == nil or not spec.hasCompactionService or not self.isClient or spec.compactionActivatable ~= nil then
        return
    end
    spec.compactionActivatable = CompactionActivatable.new(self)
    g_currentMission.activatableObjectsSystem:addActivatable(spec.compactionActivatable)
end

function Bunker.VariableBunkerDeleteCompaction(self)
    local spec = self.spec_VariableBunker
    if spec == nil or spec.compactionActivatable == nil then
        return
    end
    if g_currentMission ~= nil and g_currentMission.activatableObjectsSystem ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.compactionActivatable)
    end
    spec.compactionActivatable = nil
end
