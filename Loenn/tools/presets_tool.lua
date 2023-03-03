local state = require("loaded_state")
local configs = require("configs")
local mods = require("mods")
local sceneHandler = require("scene_handler")
local toolHandler = require("tools")
local toolUtils = require("tool_utils")
local selectionUtils = require("selections")
local logging = require("logging")
local presets = mods.requireFromPlugin("libraries.presets")

local tool = {}

tool._type = "tool"
tool.name = "presets"
tool.group = "presets"
tool.image = nil

tool.layer = "entities"
tool.validLayers = {
    "entities",
    "triggers"
}

tool.material = ""

local presetsAvailable

local function sendContextMenuEvent(preset, new)
    sceneHandler.sendEvent("loennPresetsContextMenu", preset, new)
end

local function updatePresets(layer)
    presetsAvailable = {}

    local registry = presets.getRegisteredPresets(layer)

    for name, preset in pairs(registry) do
        table.insert(presetsAvailable, preset.name)
    end
end

function tool.setLayer(layer)
    if layer ~= "temp" and layer ~= tool.layer or not presetsAvailable then
        tool.layer = layer

        updatePresets(layer)

        -- Actually refresh the list
        toolUtils.sendLayerEvent(tool, "temp")
        toolUtils.sendLayerEvent(tool, layer)
    end
end

function tool.setMaterial(material)
    local materialType = type(material)

    local preset = presets.getPreset(tool.layer, material)
    if preset then
        sendContextMenuEvent(preset, false)
    end

    toolUtils.sendMaterialEvent(tool, tool.layer, "")

    return false
end

function tool.getMaterials()
    return presetsAvailable
end

local function createNewPreset(target)
    local preset = presets.newPresetFromItem(tool.layer, target)

    if preset then
        sendContextMenuEvent(preset, true)
    end
end

function tool.mouseclicked(x, y, button, istouch, presses)
    local actionButton = configs.editor.toolActionButton
    local contextMenuButton = configs.editor.contextMenuButton

    if button == actionButton then
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

function tool.loennPresetsUpdated(layer)
    updatePresets(layer)

    toolUtils.sendLayerEvent(tool, "temp")
    toolUtils.sendLayerEvent(tool, layer)
end

return tool