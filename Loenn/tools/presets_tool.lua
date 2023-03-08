local state = require("loaded_state")
local utils = require("utils")
local configs = require("configs")
local mods = require("mods")
local sceneHandler = require("scene_handler")
local toolHandler = require("tools")
local toolUtils = require("tool_utils")
local selectionUtils = require("selections")
local logging = require("logging")
local notifications = require("ui.notification")

local presets = mods.requireFromPlugin("libraries.presets")
local presetGroups = mods.requireFromPlugin("libraries.preset_groups")
local presetUtils = mods.requireFromPlugin("libraries.preset_utils")

local tool = {}

tool._type = "tool"
tool.name = "presets"
tool.group = "presets"
tool.image = nil

tool.layer = "entities"
tool.validLayers = {
    "entities",
    "triggers",
    "presetGroups"
}

tool.material = ""

local presetsAvailable
local presetData

local groupsAvailable
local groupData

local function sendPresetContextMenuEvent(preset, new)
    sceneHandler.sendEvent("loennPresetsContextMenu", preset, new)
end

local function sendGroupContextMenuEvent(groupName, new)
    sceneHandler.sendEvent("loennPresetsGroupContextMenu", groupName, new)
end

local function updatePresets(layer)
    presetsAvailable = {}
    presetData = {}

    local registry = presets.getRegisteredPresets(layer)

    for name, preset in pairs(registry) do
        local displayName = preset.name

        if preset.global then
            displayName = "^ " .. displayName
        end

        table.insert(presetsAvailable, displayName)

        presetData[displayName] = preset.name
    end

    return presetsAvailable
end

local function updateSelectedGroup(sendEvent)
    if tool.layer ~= "presetGroups" then
        return
    end

    for name, data in pairs(groupData) do
        if data.type == "group" and data.name == presetGroups.current then
            tool.material = name
            break
        end
    end

    if sendEvent then
        toolUtils.sendMaterialEvent(tool, tool.layer, tool.material)
    end
end

local function updateGroups(sendEvent)
    groupsAvailable = {
        "< New ... >",
        "< Global Group >"
    }
    groupData = {
        ["< New ... >"] = {type = "new"},
        ["< Global Group >"] = {type = "group", name = "global"}
    }

    local groups = presetGroups.getSavedGroups()
    for name, group in pairs(groups) do
        if name ~= "global" then
            table.insert(groupsAvailable, name)

            groupData[name] = {type = "group", name = name}
        end
    end

    if sendEvent then
        local layer = tool.layer
        toolUtils.sendLayerEvent(tool, "temp")
        toolUtils.sendLayerEvent(tool, layer)
    end

    updateSelectedGroup(sendEvent)

    return groupsAvailable
end

function tool.setLayer(layer)
    if layer ~= "temp" and layer ~= tool.layer or not presetsAvailable then
        tool.layer = layer

        if layer == "presetGroups" then
            updateGroups()
        else
            updatePresets(layer)
            tool.material = ""
        end

        -- Actually refresh the list
        toolUtils.sendLayerEvent(tool, "temp")
        toolUtils.sendLayerEvent(tool, layer)

        toolUtils.sendMaterialEvent(tool, layer, tool.material)
    end
end

function tool.setMaterial(material)
    if tool.layer ~= "presetGroups" then
        local presetName = presetData[material] or ""

        local preset = presets.getPreset(tool.layer, presetName)
        if preset then
            sendPresetContextMenuEvent(preset, false)
        end

        toolUtils.sendMaterialEvent(tool, tool.layer, "")

        return false
    else
        local data = groupData[material] or {}

        if data.type == "new" then
            sendGroupContextMenuEvent(nil, true)
            toolUtils.sendMaterialEvent(tool, tool.layer, "")
            return false
        elseif data.type == "group" then
            if presetGroups.current ~= data.name then
                if presetGroups.setCurrent(data.name) then
                    notifications.notify("Switched preset group to " .. material)
                    tool.material = material
                else
                    -- Selected group does not exist
                    toolUtils.sendMaterialEvent(tool, tool.layer, "")
                    return false
                end
            end
        else
            -- Invalid material
            return false
        end
    end
end

function tool.getMaterials()
    if tool.layer == "presetGroups" then
        return groupsAvailable or updateGroups()
    else
        return presetsAvailable
    end
end

local function createNewPreset(target)
    local preset = presets.newPresetFromItem(tool.layer, target)

    if preset then
        sendPresetContextMenuEvent(preset, true)
    end
end

function tool.mouseclicked(x, y, button, istouch, presses)
    local actionButton = configs.editor.toolActionButton

    if button == actionButton then
        if tool.layer == "presetGroups" then
            local data = groupData[tool.material] or {}
            if data.type == "group" and data.name ~= "global" then
                sendGroupContextMenuEvent(data.name, false)
            end
        else
            local cursorX, cursorY = toolUtils.getCursorPositionInRoom(x, y)

            if cursorX and cursorY then
                local room = state.getSelectedRoom()
                local targets = selectionUtils.getContextSelections(room, tool.layer, cursorX, cursorY)

                if targets and #targets > 0 then
                    createNewPreset(targets[1].item)
                end
            end
        end
    end
end

function tool.loennPresetsUpdated()
    local layer = tool.layer

    updatePresets(layer)

    toolUtils.sendLayerEvent(tool, "temp")
    toolUtils.sendLayerEvent(tool, layer)
end

function tool.loennPresetsGroupsUpdated()
    updateGroups(true)
end

function tool.load()
    if not presetUtils.checkVersion() then
        toolHandler.tools[tool.name] = nil
    end
end

return tool