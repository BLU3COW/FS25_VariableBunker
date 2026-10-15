VariableBunker = VariableBunker or {}

local Bunker = VariableBunker
local HOURS_PER_DAY = 24

local function getBunkerSilo(placeable)
    local spec = placeable ~= nil and placeable.spec_bunkerSilo or nil
    return spec ~= nil and spec.bunkerSilo or nil
end

local function getText(placeable, key)
    return g_i18n:getText(key, placeable.customEnvironment)
end

local function getStatus(bunkerSilo)
    local state = bunkerSilo.state
    if state == BunkerSilo.STATE_FILL then
        if (bunkerSilo.fillLevel or 0) < 1 then
            return "status_VariableBunkerFill", false
        end
        if (bunkerSilo.compactedPercent or 0) < 100 then
            return "status_VariableBunkerCompact", true
        end
        return "status_VariableBunkerCover", true
    end
    if state == BunkerSilo.STATE_CLOSED then
        return "status_VariableBunkerFermenting", false
    end
    if state == BunkerSilo.STATE_FERMENTED then
        return "status_VariableBunkerOpen", true
    end
    return "status_VariableBunkerDrain", false
end

local function getFillLevelText(placeable, bunkerSilo)
    local fillLevel = bunkerSilo.fillLevel or 0
    local capacity = VariableBunkerStorage.getEstimatedCapacity(placeable)
    local text = g_i18n:formatVolume(fillLevel, 0)
    if capacity > 0 then
        text = string.format("%s (%d %%)", text, math.floor(math.min(fillLevel / capacity, 1) * 100 + 0.5))
    end
    return text
end

local function getFermentingText(placeable, bunkerSilo)
    local percent = math.clamp(bunkerSilo.fermentingPercent or 0, 0, 1)
    local environment = g_currentMission.environment
    local daysPerPeriod = environment ~= nil and environment.daysPerPeriod or 1
    local hours = math.ceil((1 - percent) * HOURS_PER_DAY * daysPerPeriod)
    local remaining
    if hours >= HOURS_PER_DAY then
        remaining = string.format(
            getText(placeable, "info_VariableBunkerRemainingDays"),
            math.floor(hours / HOURS_PER_DAY),
            hours % HOURS_PER_DAY
        )
    else
        remaining = string.format(getText(placeable, "info_VariableBunkerRemainingHours"), hours)
    end
    return string.format("%d %% (%s)", math.floor(percent * 100), remaining)
end

local function getInfoPlaceable()
    if g_currentMission == nil or g_localPlayer == nil or Bunker.activeSilos == nil then
        return nil
    end
    for placeable in pairs(Bunker.activeSilos) do
        local bunkerSilo = getBunkerSilo(placeable)
        if
            bunkerSilo ~= nil
            and not placeable.isDeleted
            and bunkerSilo:getCanInteract(true)
            and g_currentMission.accessHandler:canPlayerAccess(placeable)
        then
            return placeable, bunkerSilo
        end
    end
    return nil
end

local infoListener = {}

function infoListener:getBox()
    if self.box == nil then
        local hud = g_currentMission.hud
        if hud == nil or hud.infoDisplay == nil then
            return nil
        end
        self.box = hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
    end
    return self.box
end

function infoListener:update(_dt)
    local placeable, bunkerSilo = getInfoPlaceable()
    if placeable == nil then
        return
    end
    local box = self:getBox()
    if box == nil then
        return
    end
    box:clear()
    box:setTitle(placeable:getName())
    box:addLine(getText(placeable, "info_VariableBunkerFillLevel"), getFillLevelText(placeable, bunkerSilo))
    if bunkerSilo.state == BunkerSilo.STATE_FILL and (bunkerSilo.fillLevel or 0) >= 1 then
        box:addLine(
            getText(placeable, "info_VariableBunkerCompaction"),
            string.format("%d %%", bunkerSilo.compactedPercent or 0)
        )
    elseif bunkerSilo.state == BunkerSilo.STATE_CLOSED then
        box:addLine(getText(placeable, "info_VariableBunkerFermentation"), getFermentingText(placeable, bunkerSilo))
    end
    local statusKey, needsAction = getStatus(bunkerSilo)
    box:addLine(getText(placeable, "info_VariableBunkerStatus"), getText(placeable, statusKey), needsAction)
    box:showNextFrame()
end

function infoListener:deleteMap()
    if self.box ~= nil and g_currentMission ~= nil and g_currentMission.hud ~= nil then
        g_currentMission.hud.infoDisplay:destroyBox(self.box)
    end
    self.box = nil
end

addModEventListener(infoListener)
