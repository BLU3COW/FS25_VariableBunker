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

local function getBunkerSilo(placeable)
    local spec = placeable ~= nil and placeable.spec_bunkerSilo or nil
    return spec ~= nil and spec.bunkerSilo or nil
end

local function getText(placeable, key)
    return g_i18n:getText(key, placeable ~= nil and placeable.customEnvironment or nil)
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
        getText(placeable, "dialog_VariableBunkerCompaction"),
        g_i18n:formatVolume(remaining, 0),
        g_i18n:formatNumber(hours, 1, true),
        g_i18n:formatMoney(price, 0, true, true)
    )
    YesNoDialog.show(
        onCompactionDialogClosed,
        nil,
        text,
        getText(placeable, "configuration_VariableBunkerCompaction"),
        nil,
        nil,
        nil,
        nil,
        nil,
        placeable
    )
end

local function getInteractorPosition()
    local player = g_localPlayer
    if player == nil then
        return nil
    end
    if player:getIsInVehicle() then
        local vehicle = player:getCurrentVehicle()
        if vehicle ~= nil and vehicle.rootNode ~= nil then
            return getWorldTranslation(vehicle.rootNode)
        end
        return nil
    end
    return player:getPosition()
end

local CompactionActivatable = {}
local CompactionActivatable_mt = Class(CompactionActivatable)

function CompactionActivatable.new(placeable)
    local self = setmetatable({}, CompactionActivatable_mt)
    self.placeable = placeable
    self.activateText = getText(placeable, "action_VariableBunkerCompaction")
    return self
end

function CompactionActivatable:getAreaNode()
    local spec = self.placeable.spec_VariableBunker
    return spec ~= nil and spec.inputStationRootNode or nil
end

function CompactionActivatable:getIsActivatable()
    local placeable = self.placeable
    local node = self:getAreaNode()
    if node == nil or placeable.isDeleted or g_currentMission == nil then
        return false
    end
    if not g_currentMission.accessHandler:canPlayerAccess(placeable) then
        return false
    end
    if Bunker.getCompactionRemainingLiters(placeable) < MIN_REMAINING_LITERS then
        return false
    end
    local x, y, z = getInteractorPosition()
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
