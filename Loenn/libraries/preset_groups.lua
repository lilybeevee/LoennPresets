local state = require("loaded_state")
local modHandler = require("mods")
local utils = require("utils")
local sceneHandler = require("scene_handler")
local toolHandler = require("tools")
local toolUtils = require("tool_utils")
local logging = require("logging")

local persistence = modHandler.getModPersistence()
local settings = modHandler.getModSettings()

local presetUtils = modHandler.requireFromPlugin("libraries.preset_utils")
local presets

local presetGroups = {}

presetGroups.current = "global"

-- Solves dependency loop
function presetGroups.init(_presets)
    presets = _presets

    presetGroups.current = persistence.currentGroup

    if not presetGroups.current then
        if not settings.groups ~= nil then
            -- Not first launch, keep current favorites/presets in a new group
            presetGroups.setGroup("Unsaved Group", {})
            presetGroups.current = "Unsaved Group"
        else
            -- First launch, go to the global group by default
            presetGroups.current = "global"
        end
    elseif not presetGroups.getGroup(presetGroups.current) then
        presetGroups.setGroup(presetGroups.current, {})
    end

    persistence.currentGroup = presetGroups.current
end

function presetGroups.getSavedGroups()
    return settings.groups or {
        ["global"] = {}
    }
end

function presetGroups.setSavedGroups(value)
    settings.groups = value

    presetUtils.saveSettings()
end

function presetGroups.getSavedBackups()
    return settings.groupBackups or {}
end

function presetGroups.setSavedBackups(value)
    settings.groupBackups = value

    presetUtils.saveSettings()
end

function presetGroups.getPersistenceGroupForMap(filename)
    return utils.getPath(persistence, {"mapGroup", filename})
end

function presetGroups.setPersistenceGroupForMap(filename, group)
    utils.setPath(persistence, {"mapGroup", filename}, group, true)
end

function presetGroups.getGroup(name)
    local groups = presetGroups.getSavedGroups()

    if not name then
        name = presetGroups.current
    end

    return groups[name]
end

function presetGroups.setGroup(name, value)
    if not name then return end

    local groups = presetGroups.getSavedGroups()

    groups[name] = value

    presetGroups.setSavedGroups(groups)
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

function presetGroups.saveBackup(groupName)
    groupName = groupName or presetGroups.current

    local group = presetGroups.getGroup(groupName)

    if not group then
        return
    end

    local savedBackups = presetGroups.getSavedBackups()
    local groupBackups = savedBackups[groupName] or {}

    if #groupBackups > 0 and utils.equals(group, groupBackups[1].data) then
        return
    end

    local backupName = groupName .. " - " .. os.date("%Y-%m-%d %H:%M:%S")

    table.insert(groupBackups, 1, {
        name = backupName,
        data = utils.deepcopy(group)
    })

    if #groupBackups > 10 then
        table.remove(groupBackups, #groupBackups)
    end

    savedBackups[groupName] = groupBackups
    presetGroups.setSavedBackups(savedBackups)
end

function presetGroups.renameBackups(oldName, newName)
    local savedBackups = presetGroups.getSavedBackups()

    if oldName == newName or not savedBackups[oldName] then
        return
    end

    local oldBackups = savedBackups[oldName]

    savedBackups[oldName] = nil

    if savedBackups[newName] then
        for i, backup in ipairs(oldBackups) do
            table.insert(savedBackups[newName], i, backup)
        end

        while #savedBackups[newName] > 20 do
            table.remove(savedBackups[newName], #savedBackups[newName])
        end
    else
        savedBackups[newName] = oldBackups
    end

    presetGroups.setSavedBackups(savedBackups)
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
    persistence.currentGroup = presetGroups.current

    local presetTool = toolHandler.tools["presets"] or {name = "presets", group = "presets"}
    local groupMaterial = presetGroups.current

    if presetGroups.current == "global" then
        groupMaterial = "(G) Global Group"
    end

    toolUtils.setPersistenceMaterial(presetTool, "presetGroups", groupMaterial)
end

function presetGroups.setCurrent(name, options)
    options = options or {}

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

    if options.backup ~= false then
        presetGroups.saveBackup(oldName)

        if oldName ~= "global" then
            presetGroups.saveBackup("global")
        end
    end

    local newGroup = presetGroups.getGroup(name)

    if not newGroup then
        if options.create then
            newGroup = createNewGroup(options.copy)
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

function presetGroups.saveGroupAndBackup(groupName)
    groupName = groupName or presetGroups.current

    local globalGroup = presetGroups.getGroup("global")

    presetGroups.updateGroup(groupName, function(group)
        if not group then return end

        saveFavorites(groupName, group, globalGroup)
        savePresets(groupName, group, globalGroup)

        sceneHandler.sendEvent("loennPresetsGroupSaved", groupName, group, globalGroup)
    end)

    presetGroups.saveBackup(groupName)

    if groupName ~= "global" then
        presetGroups.saveBackup("global")
    end
end

function presetGroups.loadBackup(name, index)
    index = index or 1

    local group = presetGroups.getGroup(name)

    local savedBackups = presetGroups.getSavedBackups()
    local groupBackups = savedBackups[name] or {}

    if not group or not groupBackups[index] then
        return false
    end

    local backup = groupBackups[index]

    backup.data = backup.data or {}
    backup.data.name = backup.data.name or name

    local newName = backup.data.name

    if newName ~= name then
        presetGroups.setGroup(name, nil)
        presetGroups.setGroup(newName, backup.data)

        presetGroups.renameBackups(name, newName)
    else
        presetGroups.setGroup(name, backup.data)
    end

    if presetGroups.current ~= name then
        return true, newName
    end

    local newGroup = presetGroups.getGroup(newName)
    local globalGroup = presetGroups.getGroup("global")

    presetGroups.current = newName
    presetGroups.updatePersistence()

    loadFavorites(newName, newGroup, globalGroup)
    loadPresets(newName, newGroup, globalGroup)

    sceneHandler.sendEvent("loennPresetsGroupLoaded", newName, newGroup, globalGroup)

    return true, newName
end

function presetGroups.getFirstAvailableGroup()
    return "global"
end

return presetGroups