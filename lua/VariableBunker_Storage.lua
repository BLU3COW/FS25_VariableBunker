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

VariableBunkerStorage.MODE_INPUT = MODE_INPUT
VariableBunkerStorage.MODE_OUTPUT = MODE_OUTPUT

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
            length = bandLength,
            radius = radius,
            inputOffsetKey = "input_" .. index,
            outputOffsetKeys = {},
        }
        band.sx, band.sy, band.sz = localToWorld(rootNode, halfWidth, 0, startZ)
        band.wx, band.wy, band.wz = localToWorld(rootNode, -halfWidth, 0, startZ)
        band.hx, band.hy, band.hz = localToWorld(rootNode, halfWidth, 0, endZ)
        band.lsx, band.lsy, band.lsz = localToWorld(rootNode, lineHalfWidth, 0, centerZ)
        band.lex, band.ley, band.lez = localToWorld(rootNode, -lineHalfWidth, 0, centerZ)
        band.rsx, band.rsy, band.rsz = localToWorld(rootNode, halfWidth, 0, centerZ)
        band.rex, band.rey, band.rez = localToWorld(rootNode, -halfWidth, 0, centerZ)
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

local function getBandCenter(band)
    return (band.wx + band.hx) * 0.5, (band.wy + band.hy) * 0.5, (band.wz + band.hz) * 0.5
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

local function moveAtArea(storage, area, liters, fillTypeIndex, offsetKey, addMaterial, lineHeight)
    if math.abs(liters) < 0.001 then
        return 0
    end
    local sx, sy, sz = area.rsx, area.rsy, area.rsz
    local ex, ey, ez = area.rex, area.rey, area.rez
    local delta = -liters
    if addMaterial then
        local _, topY, _ = localToWorld(storage.placeable.rootNode, 0, lineHeight, 0)
        sx, sy, sz = area.lsx, topY, area.lsz
        ex, ey, ez = area.lex, topY, area.lez
        delta = liters
    end
    local moved, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(
        nil,
        delta,
        fillTypeIndex,
        sx,
        sy,
        sz,
        ex,
        ey,
        ez,
        area.radius,
        area.radius,
        storage.lineOffsets[offsetKey],
        addMaterial,
        nil,
        false,
        true
    )
    storage.lineOffsets[offsetKey] = lineOffset
    return math.abs(moved)
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
    self.outputBandIndex = nil
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

function VariableBunkerStorage:getFreeCapacity(fillTypeIndex)
    if self.mode ~= MODE_INPUT or not self:getIsInputEnabled() or fillTypeIndex ~= FillType.CHAFF then
        return 0
    end
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil or bunkerSilo.state ~= BunkerSilo.STATE_FILL then
        self.fullFillLevel = nil
        return 0
    end
    if self.fullFillLevel ~= nil then
        local releaseLiters = math.max(FULL_RELEASE_LITERS, self.fullFillLevel * FULL_RELEASE_SHARE)
        if getCurrentFillLevel(bunkerSilo) > self.fullFillLevel - releaseLiters then
            return 0
        end
        self.fullFillLevel = nil
    end
    local missionTime = getMissionTime()
    if self.fullUntilTime ~= nil then
        if missionTime ~= nil and missionTime < self.fullUntilTime then
            return 0
        end
        self.fullUntilTime = nil
    end
    if self:getIsGeometricallyFull() then
        return 0
    end
    return math.huge
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
    return moveAtArea(self, band, liters, fillTypeIndex, band.inputOffsetKey, true, height)
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
    for _ = 1, bandCount do
        moved = moved + self:fillBand(bands, index, liters - moved, fillTypeIndex, wallHeight)
        if liters - moved < 0.001 then
            break
        end
        index = index % bandCount + 1
    end
    self.inputBandIndex = index
    self.fillExhausted = liters - moved >= MAX_PENDING_LITERS
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
    while liters - moved >= 0.001 do
        local movedInPass = 0
        for _ = 1, bandCount do
            local added = self:fillBand(bands, index, liters - moved, fillTypeIndex, self.layerHeight)
            moved = moved + added
            movedInPass = movedInPass + added
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
        end
    end
    self.inputBandIndex = index
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
        self.inputBandIndex = 1
        self.layerHeight = nil
    end
    if self.placeable.spec_VariableBunker.hasRearWall then
        return self:fillBandsToWallHeight(liters, fillTypeIndex)
    end
    return self:fillBandsInLayers(bunkerSilo, liters, fillTypeIndex)
end

local function openFermentedBand(bunkerSilo, band)
    local fermentingFillType = bunkerSilo.fermentingFillType
    if fermentingFillType == nil or getAreaFillLevel(band, fermentingFillType) < 0.001 then
        return
    end
    local x, y, z = getBandCenter(band)
    bunkerSilo:onChangedFillLevelCallback(nil, -1, bunkerSilo.outputFillType, x, y, z)
    if getAreaFillLevel(band, fermentingFillType) > 0.001 then
        DensityMapHeightUtil.changeFillTypeAtArea(
            band.sx,
            band.sz,
            band.wx,
            band.wz,
            band.hx,
            band.hz,
            fermentingFillType,
            bunkerSilo.outputFillType
        )
    end
end

function VariableBunkerStorage:openFermentedSide(bunkerSilo)
    if bunkerSilo.state == BunkerSilo.STATE_FERMENTED then
        local area = bunkerSilo.bunkerSiloArea
        bunkerSilo:openSilo(area.hx + area.dwx * 0.5, area.hy + area.dwy * 0.5, area.hz + area.dwz * 0.5)
    end
end

function VariableBunkerStorage:removeMaterial(liters, fillTypeIndex)
    local bunkerSilo = getBunkerSilo(self.placeable)
    if
        bunkerSilo == nil
        or not self:getIsOutputEnabled()
        or not self:getIsFillTypeAvailable(bunkerSilo, fillTypeIndex)
    then
        return 0
    end
    if fillTypeIndex == FillType.SILAGE then
        self:openFermentedSide(bunkerSilo)
    end
    local bands = getBands(self)
    local bandCount = #bands
    if bandCount == 0 then
        return 0
    end
    local index = math.min(self.outputBandIndex or bandCount, bandCount)
    local moved = 0
    for _ = 1, bandCount do
        local band = bands[index]
        if fillTypeIndex == FillType.SILAGE then
            openFermentedBand(bunkerSilo, band)
        end
        local offsetKey = band.outputOffsetKeys[fillTypeIndex]
        if offsetKey == nil then
            offsetKey = string.format("output_%d_%d", fillTypeIndex, index)
            band.outputOffsetKeys[fillTypeIndex] = offsetKey
        end
        local request = liters - moved
        local removed = moveAtArea(self, band, request, fillTypeIndex, offsetKey, false)
        if request - removed >= 0.001 and self.lineOffsets[offsetKey] ~= nil then
            self.lineOffsets[offsetKey] = nil
            removed = removed + moveAtArea(self, band, request - removed, fillTypeIndex, offsetKey, false)
        end
        moved = moved + removed
        if liters - moved < 0.001 then
            break
        end
        index = index - 1
        if index < 1 then
            index = bandCount
        end
    end
    self.outputBandIndex = index
    return moved
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
    end
    if self.fillExhausted then
        self.fullFillLevel = getCurrentFillLevel(bunkerSilo)
    end
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
        end
    end
    local delivered = fromBuffer + math.min(removed, missing)
    self.outputBuffers[fillTypeIndex] = buffer + math.max(removed - missing, 0)
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

VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local REFERENCE_MASS = 15
local REFERENCE_DISTANCE_PER_HOUR = 8000
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
    local litersPerMeter = REFERENCE_MASS
        / BunkerSilo.COMPACTING_BASE_MASS
        * (bunkerSilo.distanceToCompactedFillLevel or 0)
    local litersPerHour = litersPerMeter * REFERENCE_DISTANCE_PER_HOUR
    if litersPerHour <= 0 then
        return 0, 0
    end
    local hours = remaining / litersPerHour
    local costMultiplier = EconomyManager.getCostMultiplier() or 1
    local dieselPrice = 0
    local economyManager = g_currentMission.economyManager
    if economyManager ~= nil then
        dieselPrice = economyManager:getCostPerLiter(FillType.DIESEL) or 0
    end
    local hourlyCost = (getWagePerHour() + WEAR_COST_PER_HOUR) * costMultiplier + DIESEL_LITERS_PER_HOUR * dieselPrice
    local factor = Bunker.settings ~= nil and Bunker.settings.compactionPriceFactor or 1
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
    local price = Bunker.getCompactionOffer(placeable, Bunker.getCompactionRemainingLiters(placeable))
    if price <= 0 then
        return false
    end
    local farmId = placeable:getOwnerFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farm:getBalance() < price then
        return false
    end
    g_currentMission:addMoney(-price, farmId, MoneyType.AI, true, true)
    bunkerSilo:updateCompacting(bunkerSilo.fillLevel)
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
