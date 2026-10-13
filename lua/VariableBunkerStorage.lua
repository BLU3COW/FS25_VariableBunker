VariableBunkerStorage = {}

local VariableBunkerStorage_mt = Class(VariableBunkerStorage, Object)
InitObjectClass(VariableBunkerStorage, "VariableBunkerStorage")

local MODE_INPUT = 1
local MODE_OUTPUT = 2
local MAX_BAND_LENGTH = 4
local SURFACE_ANGLE = math.rad(40)

VariableBunkerStorage.MODE_INPUT = MODE_INPUT
VariableBunkerStorage.MODE_OUTPUT = MODE_OUTPUT

local function getBunkerSilo(placeable)
    local spec = placeable ~= nil and placeable.spec_bunkerSilo or nil
    return spec ~= nil and spec.bunkerSilo or nil
end

local function getAreaFillLevel(area, fillTypeIndex)
    if area == nil or fillTypeIndex == nil or fillTypeIndex == FillType.UNKNOWN then
        return 0
    end
    return DensityMapHeightUtil.getFillLevelAtArea(fillTypeIndex, area.sx, area.sz, area.wx, area.wz, area.hx, area.hz)
end

local function getCurrentFillLevel(bunkerSilo)
    local missionTime = g_currentMission ~= nil and g_currentMission.time or nil
    if bunkerSilo.isServer and (missionTime == nil or bunkerSilo.variableBunkerFillLevelUpdateTime ~= missionTime) then
        bunkerSilo:updateFillLevel()
        bunkerSilo.variableBunkerFillLevelUpdateTime = missionTime
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

local function getEstimatedCapacity(placeable)
    local spec = placeable.spec_VariableBunker
    if spec == nil then
        return 0
    end
    local width = spec.widthMeters or 0
    local length = spec.lengthMeters or 0
    local height = spec.heightMeters or 0
    local mapHeightLimit = getMapHeightLimit()
    if mapHeightLimit ~= nil then
        height = math.min(height, mapHeightLimit)
    end
    local openEnds = spec.hasRearWall and 1 or 2
    local volume = width * math.max(0, length * height - openEnds * height * height / (2 * math.tan(SURFACE_ANGLE)))
    return math.max(volume * 1000, 0)
end

local function createBands(area)
    local dx = area.hx - area.sx
    local dy = area.hy - area.sy
    local dz = area.hz - area.sz
    local length = MathUtil.vector3Length(dx, dy, dz)
    if length < 0.001 then
        return {}
    end
    local dirX = dx / length
    local dirY = dy / length
    local dirZ = dz / length
    local count = math.max(math.ceil(length / MAX_BAND_LENGTH), 1)
    local bandLength = length / count
    local bands = {}
    for index = 1, count do
        local startOffset = (index - 1) * bandLength
        local endOffset = index * bandLength
        table.insert(bands, {
            sx = area.sx + dirX * startOffset,
            sy = area.sy + dirY * startOffset,
            sz = area.sz + dirZ * startOffset,
            wx = area.wx + dirX * startOffset,
            wy = area.wy + dirY * startOffset,
            wz = area.wz + dirZ * startOffset,
            hx = area.sx + dirX * endOffset,
            hy = area.sy + dirY * endOffset,
            hz = area.sz + dirZ * endOffset,
            inputOffsetKey = "input_" .. index,
            outputOffsetKeys = {},
        })
    end
    return bands
end

local function getBands(storage, bunkerSilo)
    if storage.bands == nil then
        storage.bands = createBands(bunkerSilo.bunkerSiloArea.inner)
    end
    return storage.bands
end

local function getBandCenter(band)
    return (band.wx + band.hx) * 0.5, (band.wy + band.hy) * 0.5, (band.wz + band.hz) * 0.5
end

local function moveAtArea(storage, area, liters, fillTypeIndex, offsetKey, addMaterial)
    if math.abs(liters) < 0.001 then
        return 0
    end
    local lsx, lsy, lsz, lex, ley, lez, radius = DensityMapHeightUtil.getLineByAreaDimensions(
        area.sx,
        area.sy,
        area.sz,
        area.wx,
        area.wy,
        area.wz,
        area.hx,
        area.hy,
        area.hz,
        false
    )
    local delta = addMaterial and liters or -liters
    if addMaterial then
        local _, topY, _ =
            localToWorld(storage.placeable.rootNode, 0, storage.placeable.spec_VariableBunker.heightMeters, 0)
        lsy = topY
        ley = topY
    end
    local moved, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(
        nil,
        delta,
        fillTypeIndex,
        lsx,
        lsy,
        lsz,
        lex,
        ley,
        lez,
        radius,
        radius,
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
    self.outputBandIndices = {}
    self.fillTypes = {}
    if mode == MODE_INPUT then
        self.fillTypes[FillType.CHAFF] = true
    else
        self.fillTypes[FillType.CHAFF] = true
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

function VariableBunkerStorage:getFillLevel(fillTypeIndex)
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil or not self:getIsFillTypeSupported(fillTypeIndex) then
        return 0
    end
    if self.mode == MODE_INPUT then
        if bunkerSilo.state == BunkerSilo.STATE_FILL and fillTypeIndex == FillType.CHAFF then
            return getCurrentFillLevel(bunkerSilo)
        end
        return 0
    end
    if not self:getIsOutputEnabled() then
        return 0
    end
    if bunkerSilo.state == BunkerSilo.STATE_FILL and fillTypeIndex == FillType.CHAFF then
        return getCurrentFillLevel(bunkerSilo)
    end
    if
        (bunkerSilo.state == BunkerSilo.STATE_FERMENTED or bunkerSilo.state == BunkerSilo.STATE_DRAIN)
        and fillTypeIndex == FillType.SILAGE
    then
        return getCurrentFillLevel(bunkerSilo)
    end
    return 0
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

function VariableBunkerStorage:getFreeCapacity(fillTypeIndex)
    if self.mode ~= MODE_INPUT or not self:getIsInputEnabled() or fillTypeIndex ~= FillType.CHAFF then
        return 0
    end
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil or bunkerSilo.state ~= BunkerSilo.STATE_FILL then
        return 0
    end
    return math.huge
end

function VariableBunkerStorage:addMaterial(liters, fillTypeIndex)
    local bunkerSilo = getBunkerSilo(self.placeable)
    if
        bunkerSilo == nil
        or bunkerSilo.state ~= BunkerSilo.STATE_FILL
        or fillTypeIndex ~= FillType.CHAFF
        or not self:getIsInputEnabled()
    then
        return 0
    end
    local area = bunkerSilo.bunkerSiloArea.inner
    local moved = 0
    if self.placeable.spec_VariableBunker.hasRearWall then
        local bands = getBands(self, bunkerSilo)
        local bandCount = #bands
        local index = math.min(self.inputBandIndex, bandCount)
        for _ = 1, bandCount do
            local band = bands[index]
            local added = moveAtArea(self, band, liters - moved, fillTypeIndex, band.inputOffsetKey, true)
            moved = moved + added
            if liters - moved < 0.001 then
                self.inputBandIndex = index
                break
            end
            index = index % bandCount + 1
            self.inputBandIndex = index
        end
    else
        moved = moveAtArea(self, area, liters, fillTypeIndex, "input_flat", true)
    end
    return moved
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
        local useFront = not self.placeable.spec_VariableBunker.hasRearWall
        local x
        local y
        local z
        if useFront then
            x = area.sx + area.dwx * 0.5
            y = area.sy + area.dwy * 0.5
            z = area.sz + area.dwz * 0.5
        else
            x = area.hx + area.dwx * 0.5
            y = area.hy + area.dwy * 0.5
            z = area.hz + area.dwz * 0.5
        end
        bunkerSilo:openSilo(x, y, z)
    end
end

function VariableBunkerStorage:removeMaterial(liters, fillTypeIndex)
    local bunkerSilo = getBunkerSilo(self.placeable)
    if bunkerSilo == nil or not self:getIsOutputEnabled() then
        return 0
    end
    if fillTypeIndex == FillType.CHAFF and bunkerSilo.state ~= BunkerSilo.STATE_FILL then
        return 0
    end
    if
        fillTypeIndex == FillType.SILAGE
        and bunkerSilo.state ~= BunkerSilo.STATE_FERMENTED
        and bunkerSilo.state ~= BunkerSilo.STATE_DRAIN
    then
        return 0
    end
    if fillTypeIndex == FillType.SILAGE then
        self:openFermentedSide(bunkerSilo)
    end
    local bands = getBands(self, bunkerSilo)
    local hasRearWall = self.placeable.spec_VariableBunker.hasRearWall
    local step = hasRearWall and -1 or 1
    local defaultIndex = hasRearWall and #bands or 1
    local index = self.outputBandIndices[fillTypeIndex] or defaultIndex
    local moved = 0
    for _ = 1, #bands do
        local band = bands[index]
        if fillTypeIndex == FillType.SILAGE then
            openFermentedBand(bunkerSilo, band)
        end
        local offsetKey = band.outputOffsetKeys[fillTypeIndex]
        if offsetKey == nil then
            offsetKey = string.format("output_%d_%d", fillTypeIndex, index)
            band.outputOffsetKeys[fillTypeIndex] = offsetKey
        end
        local removed = moveAtArea(self, band, liters - moved, fillTypeIndex, offsetKey, false)
        moved = moved + removed
        if liters - moved < 0.001 then
            self.outputBandIndices[fillTypeIndex] = index
            break
        end
        index = index + step
        if index < 1 then
            index = #bands
        elseif index > #bands then
            index = 1
        end
        self.outputBandIndices[fillTypeIndex] = index
    end
    return moved
end

function VariableBunkerStorage:setFillLevel(fillLevel, fillTypeIndex)
    if not self.isServer or not self:getIsFillTypeSupported(fillTypeIndex) then
        return
    end
    local oldFillLevel = self:getFillLevel(fillTypeIndex)
    local delta = fillLevel - oldFillLevel
    local moved = 0
    if self.mode == MODE_INPUT and delta > 0 then
        moved = self:addMaterial(delta, fillTypeIndex)
    elseif self.mode == MODE_OUTPUT and delta < 0 then
        moved = self:removeMaterial(-delta, fillTypeIndex)
    end
    if moved > 0 then
        local bunkerSilo = getBunkerSilo(self.placeable)
        bunkerSilo:updateFillLevel()
        bunkerSilo.variableBunkerFillLevelUpdateTime = g_currentMission ~= nil and g_currentMission.time or nil
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
