local modHandler = require("mods")
local utils = require("utils")
local entities = require("entities")
local triggers = require("triggers")
local inputDevice = require("input_device")
local logging = require("logging")
local languageRegistry = require("language_registry")
local debugUtils = require("debug_utils")
local sceneHandler = require("scene_handler")

local persistence = modHandler.getModPersistence()
local settings = modHandler.getModSettings()

local presetUtils = modHandler.requireFromPlugin("libraries.preset_utils")
local presetGroups = modHandler.requireFromPlugin("libraries.preset_groups")
local placementRefreshDevice = modHandler.requireFromPlugin("input_devices.placement_refresh_device")
local groupPersistenceDevice = modHandler.requireFromPlugin("input_devices.group_persistence_device")

local presets = {}

presets.layers = {
    "entities",
    "triggers"
}

function presets.getRegisteredPresets(layer)
    local registry = settings.presets

    if layer then
        return registry and registry[layer] or {}
    end

    return registry or {}
end

function presets.setRegisteredPresets(layer, newRegistry)
    local registry = settings.presets or {}

    registry[layer] = utils.deepcopy(newRegistry)

    settings.presets = registry

    presetUtils.saveSettings()
end

function presets.getPreset(layer, name)
    local registry = presets.getRegisteredPresets(layer)

    return registry[name]
end

function presets.addPreset(layer, preset)
    local registry = presets.getRegisteredPresets(layer)

    local newPreset = utils.deepcopy(preset)

    preset.layer = preset.layer or layer
    preset.keepSize = preset.keepSize or false
    preset.data = preset.data or {}

    local validName = preset.name and preset.name ~= "" and not registry[preset.name]
    if not validName then
        return
    end

    registry[preset.name] = newPreset

    presets.setRegisteredPresets(layer, registry)
end

function presets.removePreset(layer, preset)
    local registry = presets.getRegisteredPresets(layer)

    registry[preset.name] = nil

    presets.setRegisteredPresets(layer, registry)
end

function presets.renamePreset(layer, oldName, newName)
    local registry = presets.getRegisteredPresets(layer)

    local preset = registry[oldName]
    if not preset then
        return false
    end

    local validName = newName and newName ~= "" and not registry[newName]
    if not validName then
        return false
    end

    registry[oldName] = nil
    registry[newName] = preset

    presets.setRegisteredPresets(layer, registry)

    return true
end

-- Copied from Loenn
local function guessPlacementType(name, handler, placement)
    if placement and placement.data then
        if placement.data.width or placement.data.height then
            return "rectangle"
        end

        if placement.data.nodes then
            return "line"
        end
    end

    local fakeEntity = {_name = name}
    local minimumNodes, maximumNodes = entities.nodeLimits(nil, nil, fakeEntity)

    if minimumNodes == 1 and maximumNodes == 1 then
        return "line"
    end

    return "point"
end

local function guessPlacementFromData(item, name, handler, default)
    local fallback = {
        name = name,
        data = {}
    }

    if handler then
        local placements = utils.callIfFunction(handler.placements)

        if placements then
            if #placements > 0 then
                if default then
                    return placements.default or fallback
                else
                    return placements[1]
                end

            else
                return placements
            end
        end
    end

    return fallback
end

function presets.getEntityPlacement(preset)
    local entityName = preset.data._name
    local handler = entities.registeredEntities[entityName]

    local sourcePlacement = guessPlacementFromData(preset.data, entityName, handler, false)
    local placementName = "LoennPresets#" .. preset.name
    local presetSuffix = string.format(modHandler.modNamesFormat, "Preset")
    local displayName = table.concat({preset.name, presetSuffix}, " ")

    local itemTemplate = {
        _name = entityName,
        _id = 0,
    }

    for k, v in pairs(preset.data) do
        itemTemplate[k] = v
    end

    itemTemplate.x = itemTemplate.x or 0
    itemTemplate.y = itemTemplate.y or 0

    local placementType = "point"
    if not preset.keepSize then
        placementType = sourcePlacement.placementType or guessPlacementType(entityName, handler, sourcePlacement)

        -- Minimize placement size if possible
        local defaultPlacement = guessPlacementFromData(preset.data, entityName, handler, true)

        local sourceWidth = sourcePlacement.data.width or defaultPlacement.data.width
        local sourceHeight = sourcePlacement.data.height or defaultPlacement.data.height

        itemTemplate.width = sourceWidth or itemTemplate.width
        itemTemplate.height = sourceHeight or itemTemplate.height
    end

    local associatedMods = sourcePlacement.associatedMods or entities.associatedMods(itemTemplate)

    local placement = {
        name = placementName,
        displayName = displayName,
        layer = "entities",
        placementType = placementType,
        itemTemplate = itemTemplate,
        associatedMods = associatedMods
    }

    return placement
end

function presets.getTriggerPlacement(preset)
    local triggerName = preset.data._name
    local handler = triggers.registeredTriggers[triggerName]

    local sourcePlacement = guessPlacementFromData(preset.data, triggerName, handler)
    local placementType = preset.keepSize and "point" or "rectangle"
    local placementName = "LoennPresets#" .. preset.name

    local itemTemplate = {
        _name = triggerName,
        _id = 0,
    }

    for k, v in pairs(preset.data) do
        itemTemplate[k] = v
    end

    itemTemplate.x = itemTemplate.x or 0
    itemTemplate.y = itemTemplate.y or 0

    itemTemplate.width = itemTemplate.width or 16
    itemTemplate.height = itemTemplate.height or 16

    local associatedMods = sourcePlacement.associatedMods or triggers.associatedMods(itemTemplate)

    local placement = {
        name = placementName,
        displayName = preset.name,
        layer = "triggers",
        placementType = placementType,
        itemTemplate = itemTemplate,
        associatedMods = associatedMods
    }

    return placement
end

function presets.newPresetFromItem(layer, item)
    local handler

    if layer == "entities" then handler = entities.registeredEntities[item._name] end
    if layer == "triggers" then handler = triggers.registeredTriggers[item._name] end

    local placement = guessPlacementFromData(item, item._name, handler)
    local language = languageRegistry.getLanguage()

    local displayName = placement.name
    local displayNameLanguage = language.entities[item._name].placements.name[placement.name]

    if displayNameLanguage._exists then
        displayName = tostring(displayNameLanguage)
    end

    local preset = {
        name = displayName,
        layer = layer,
        keepSize = false,
        data = utils.deepcopy(item)
    }

    return preset
end

function presets.getPlacement(preset)
    if not preset then return end

    if preset.layer == "entities" then
        return presets.getEntityPlacement(preset)
    elseif preset.layer == "triggers" then
        return presets.getTriggerPlacement(preset)
    end
end

local function hookPlacementFunction(f, layer)
    return function(...)
        local placements = f(...)

        for name, preset in pairs(presets.getRegisteredPresets(layer)) do
            local placement = presets.getPlacement(preset)

            if placement then
                table.insert(placements, placement)
            end
        end

        return placements
    end
end

function presets.loadHooks()
    local prevHook = LOENNPRESETS_HOOKED

    if prevHook then
        if prevHook.entities     then entities.getPlacements  = prevHook.entities     end
        if prevHook.triggers     then triggers.getPlacements  = prevHook.triggers     end
        if prevHook.reloadScenes then debugUtils.reloadScenes = prevHook.reloadScenes end
    end

    LOENNPRESETS_HOOKED = {
        entities     = entities.getPlacements,
        triggers     = triggers.getPlacements,
        reloadScenes = debugUtils.reloadScenes
    }

    entities.getPlacements = hookPlacementFunction(entities.getPlacements, "entities")
    triggers.getPlacements = hookPlacementFunction(triggers.getPlacements, "triggers")

    local oldReloadScenes = debugUtils.reloadScenes
    debugUtils.reloadScenes = function(...)
        -- make sure we add our devices to the correct scene
        oldReloadScenes(...)
        presets.loadDevices()
    end
end

-- TODO: stops working after reloading everything. why?
function presets.loadDevices()
    local scene = sceneHandler.getScene("Editor")

    for i, device in ipairs(scene.inputDevices) do
        if device.__loennPresetsDevice == true then
            -- already have a device
            return
        end
    end

    inputDevice.newInputDevice(scene.inputDevices, placementRefreshDevice)
    inputDevice.newInputDevice(scene.inputDevices, groupPersistenceDevice)
end

if presetUtils.checkVersion() then
    presets.loadHooks()
    presets.loadDevices()

    presetGroups.init(presets)
end

return presets