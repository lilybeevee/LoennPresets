local state = require("loaded_state")
local modHandler = require("mods")
local utils = require("utils")
local persistence = require("persistence")
local sceneHandler = require("scene_handler")
local toolHandler = require("tools")
local toolUtils = require("tool_utils")
local logging = require("logging")

local presetUtils = modHandler.requireFromPlugin("libraries.preset_utils")
local presets

local presetGroups = {}

presetGroups.current = "global"

-- Solves dependency loop
function presetGroups.init(_presets)
    presets = _presets

    presetGroups.current = persistence.loennPresetsPluginCurrentGroup

    if not presetGroups.current or not presetGroups.getGroup(presetGroups.current) then
        presetGroups.setCurrent(presetGroups.getFirstAvailableGroup())
    end
end

function presetGroups.getPersistenceGroups()
    return persistence.loennPresetsPluginGroups or {
        ["global"] = {}
    }
end

function presetGroups.setPersistenceGroups(value)
    persistence.loennPresetsPluginGroups = value
end

function presetGroups.getPersistenceGroupForMap(filename)
    return utils.getPath(persistence, {"loennPresetsPluginCurrentGroupForMap", filename})
end

function presetGroups.setPersistenceGroupForMap(filename, group)
    utils.setPath(persistence, {"loennPresetsPluginCurrentGroupForMap", filename}, group, true)
end

function presetGroups.getGroup(name)
    local groups = presetGroups.getPersistenceGroups()

    if not name then
        name = presetGroups.current
    end

    return groups[name]
end

function presetGroups.setGroup(name, value)
    if not name then return end

    local groups = presetGroups.getPersistenceGroups()

    groups[name] = value

    presetGroups.setPersistenceGroups(groups)
end

function presetGroups.updateGroup(name, func)
    local group = presetGroups.getGroup(name)

    local result = func(group)

    if result ~= false then
        presetGroups.setGroup(name, group)
    end
end

function presetGroups.getGroupValue(name, key, default)
    local group = presetGroups.getGroup(name)

    if group and group[key] ~= nil then
        return group[key]
    end

    return default
end

function presetGroups.setGroupValue(name, key, value)
    local group = presetGroups.getGroup(name)

    if group then
        group[key] = value
    end

    presetGroups.setGroup(name, group)
end

function presetGroups.updateGroupValue(name, key, func)
    local group = presetGroups.getGroup(name)

    if group then
        local result = func(group[key])

        if result ~= false then
            group[key] = result
        end
    end

    presetGroups.setGroup(name, group)
end

local function saveFavorites(name, group, globals)
    group.favorites = {}

    if name ~= "global" then
        group.favoritesExclude = {}
    end

    local processedTools = {}

    for toolName, tool in pairs(toolHandler.tools) do
        local toolPersistId = toolUtils.getToolPersistenceIdentifier(tool)
        local layers = toolHandler.getLayers(toolName)

        processedTools[toolPersistId] = processedTools[toolPersistId] or {}

        for _, layer in ipairs(layers) do
            if not processedTools[toolPersistId][layer] then
                processedTools[toolPersistId][layer] = true

                local savedFavorites = {}
                local excludedFavorites = {}

                local favorites = toolUtils.getPersistenceFavorites(tool, layer) or {}

                if name ~= "global" then
                    local globalFavorites = utils.getPath(globals, {"favorites", toolPersistId, layer}, {})
                    local globalLookup = presetUtils.toLookup(globalFavorites)

                    local addedFavorite = {}
                    for _, favorite in ipairs(favorites) do
                        if not globalLookup[favorite] then
                            table.insert(savedFavorites, favorite)
                        end
                        addedFavorite[favorite] = true
                    end

                    for _, favorite in ipairs(globalFavorites) do
                        if not addedFavorite[favorite] then
                            table.insert(excludedFavorites, favorite)
                        end
                    end
                else
                    for _, favorite in ipairs(favorites) do
                        table.insert(savedFavorites, favorite)
                    end
                end

                if #savedFavorites > 0 then
                    utils.setPath(group.favorites, {toolPersistId, layer}, savedFavorites, true)
                end
                if #excludedFavorites > 0 then
                    utils.setPath(group.favoritesExclude, {toolPersistId, layer}, excludedFavorites, true)
                end
            end
        end
    end
end

local function loadFavorites(name, group, globals)
    local processedTools = {}

    for toolName, tool in pairs(toolHandler.tools) do
        local toolPersistId = toolUtils.getToolPersistenceIdentifier(tool)
        local layers = toolHandler.getLayers(toolName)

        processedTools[toolPersistId] = processedTools[toolPersistId] or {}

        for _, layer in ipairs(layers) do
            if not processedTools[toolPersistId][layer] then
                processedTools[toolPersistId][layer] = true

                local favorites = utils.getPath(group, {"favorites", toolPersistId, layer}, {})

                local loadedFavorites = {}

                for _, favorite in ipairs(favorites) do
                    table.insert(loadedFavorites, favorite)
                end

                if name ~= "global" then
                    local globalFavorites = utils.getPath(globals, {"favorites", toolPersistId, layer}, {})
                    local excludedFavorites = utils.getPath(group, {"favoritesExclude", toolPersistId, layer}, {})

                    local excludedLookup = presetUtils.toLookup(excludedFavorites)

                    for _, favorite in ipairs(globalFavorites) do
                        if not excludedLookup[favorite] then
                            table.insert(loadedFavorites, favorite)
                        end
                    end
                end

                local currentlyLoadedFavorites = toolUtils.getPersistenceFavorites(tool, layer) or {}

                if #loadedFavorites > 0 or #currentlyLoadedFavorites > 0 then
                    toolUtils.setPersistenceFavorites(tool, layer, loadedFavorites)
                end
            end
        end
    end
end

local function savePresets(name, group, globals)
    group.presets = {}

    local registeredPresets = presets.getRegisteredPresets()

    local savedAnyGlobal = false

    for layer, layerPresets in pairs(registeredPresets) do
        local savedPresets = {}

        local globalPresets = {}

        if name ~= "global" then
            globalPresets = utils.getPath(globals, {"presets", layer}, {})
        end

        for presetName, preset in pairs(layerPresets) do
            local presetToSave = utils.deepcopy(preset)

            presetToSave.global = nil -- Unnecessary data

            if not globalPresets[presetName] then
                savedPresets[presetName] = presetToSave
            else
                globalPresets[presetName] = presetToSave
                savedAnyGlobal = true
            end
        end

        if not utils.isEmpty(savedPresets) then
            group.presets[layer] = savedPresets
        end
    end

    if name ~= "global" and savedAnyGlobal then
        presetGroups.setGroup("global", globals)
    end
end

local function loadPresets(name, group, globals)
    for _, layer in ipairs(presets.layers) do
        local loadedPresets = {}

        if name ~= "global" then
            local globalPresets = utils.getPath(globals, {"presets", layer}, {})

            for presetName, preset in pairs(globalPresets) do
                local presetToLoad = utils.deepcopy(preset)

                presetToLoad.global = true

                loadedPresets[presetName] = presetToLoad
            end
        end

        local groupPresets = utils.getPath(group, {"presets", layer}, {})

        for presetName, preset in pairs(groupPresets) do
            loadedPresets[presetName] = utils.deepcopy(preset)
        end

        presets.setRegisteredPresets(layer, loadedPresets)
    end

    sceneHandler.sendEvent("loennPresetsUpdated")
end

local function createNewGroup(copy)
    local newGroup = {}

    local groupName = presetGroups.current

    if copy and groupName ~= "global" then
        local oldGroup = presetGroups.getGroup(groupName)

        if oldGroup then
            newGroup = utils.deepcopy(oldGroup)
        end
    end

    return newGroup
end

function presetGroups.updatePersistence()
    if state.filename then
        presetGroups.setPersistenceGroupForMap(state.filename, presetGroups.current)
    end
    persistence.loennPresetsPluginCurrentGroup = presetGroups.current
end

function presetGroups.setCurrent(name, createIfMissing, copyGroup)
    local oldName = presetGroups.current

    if oldName == name then
        return false
    end

    local globalGroup = presetGroups.getGroup("global")

    presetGroups.updateGroup(presetGroups.current, function(group)
        if not group then return end

        saveFavorites(oldName, group, globalGroup)
        savePresets(oldName, group, globalGroup)

        sceneHandler.sendEvent("loennPresetsGroupSaved", oldName, group, globalGroup)
    end)

    local newGroup = presetGroups.getGroup(name)

    if not newGroup then
        if createIfMissing then
            newGroup = createNewGroup(copyGroup)
            presetGroups.setGroup(name, newGroup)
        else
            return false
        end
    end

    presetGroups.current = name
    presetGroups.updatePersistence()

    if oldName == "global" then
        -- we need to reload the global group, as it may have been modified by the save
        globalGroup = presetGroups.getGroup("global")
    end

    loadFavorites(name, newGroup, globalGroup)
    loadPresets(name, newGroup, globalGroup)

    sceneHandler.sendEvent("loennPresetsGroupLoaded", name, newGroup, globalGroup)

    return true
end

function presetGroups.getFirstAvailableGroup()
    return "global"
end

return presetGroups