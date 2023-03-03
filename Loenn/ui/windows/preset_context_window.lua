local uiElements = require("ui.elements")

local mods = require("mods")
local state = require("loaded_state")
local utils = require("utils")
local languageRegistry = require("language_registry")
local widgetUtils = require("ui.widgets.utils")
local form = require("ui.forms.form")
local logging = require("logging")
local sceneHandler = require("scene_handler")
local debugUtils = require("debug_utils")
local toolHandler = require("tools")
local toolUtils = require("tool_utils")

local presets = mods.requireFromPlugin("libraries.presets")

local contextWindow = {}

local contextGroup
local window
local windowPreviousX = 0
local windowPreviousY = 0

local function loennPresetsContextMenuCallback(group, preset, new)
    contextWindow.createContextMenu(preset, new)
end

local function contextWindowUpdate(orig, self, dt)
    orig(self, dt)

    windowPreviousX = self.x
    windowPreviousY = self.y
end

local function getWindowTitle(language, preset)
    local baseTitle = tostring(language.ui.LoennPresets.preset_context_window.title)
    local titleParts = {baseTitle, preset.name}

    return table.concat(titleParts, " - ")
end

local function updateFavorites(layer, oldName, newName, favorite)
    local placementTool = toolHandler.tools["placement"]

    local oldPlacementName = "LoennPresets#" .. oldName
    local newPlacementName = "LoennPresets#" .. newName

    toolUtils.removePersistenceFavorites(placementTool, layer, oldPlacementName)

    if favorite then
        toolUtils.addPersistenceFavorites(placementTool, layer, newPlacementName)
    end
end

function contextWindow.saveChangesCallback(preset, formData, new)
    return function(formFields)
        local newData = form.getFormData(formFields)

        local oldName = preset.name
        local newName = newData.name

        local nameValid = newName ~= ""

        if (new or oldName ~= newName) and presets.getPreset(preset.layer, newName) then
            nameValid = false
        end

        if not nameValid then return end

        if not new then
            presets.removePreset(preset.layer, preset)
        end

        preset.name = newData.name
        preset.keepSize = newData.keepSize

        presets.addPreset(preset.layer, preset)

        updateFavorites(preset.layer, oldName, newName, newData.favorite)

        sceneHandler.sendEvent("loennPresetsUpdated", preset.layer)

        window:removeSelf()
    end
end

function contextWindow.editPropertiesCallback(preset)
    return function()
        sceneHandler.sendEvent("loennPresetsPropertyContextMenu", preset, false)
    end
end

function contextWindow.deleteCallback(preset)
    return function()
        presets.removePreset(preset.layer, preset)

        sceneHandler.sendEvent("loennPresetsUpdated", preset.layer)

        window:removeSelf()
    end
end

local function isPresetFavorited(layer, name)
    local placementTool = toolHandler.tools["placement"]
    local favorites = toolUtils.getPersistenceFavorites(placementTool, layer)

    local placementName = "LoennPresets#" .. name

    for _, favorite in ipairs(favorites) do
        if favorite == placementName then
            return true
        end
    end

    return false
end

local function prepareFormData(preset, language, new)
    local formData = {
        name = preset.name or "",
        keepSize = preset.keepSize or false,
        favorite = new or isPresetFavorited(preset.layer, preset.name)
    }

    local fieldInformation = {
        name = {
            displayName = tostring(language.ui.LoennPresets.preset_context_window.field.name.name),
            tooltipText = tostring(language.ui.LoennPresets.preset_context_window.field.name.description),
        },
        keepSize = {
            displayName = tostring(language.ui.LoennPresets.preset_context_window.field.keepSize.name),
            tooltipText = tostring(language.ui.LoennPresets.preset_context_window.field.keepSize.description),
        },
        favorite = {
            displayName = tostring(language.ui.LoennPresets.preset_context_window.field.favorite.name),
            tooltipText = tostring(language.ui.LoennPresets.preset_context_window.field.favorite.description),
        }
    }

    local fieldOrder = {"name", "keepSize", "favorite"}

    return formData, fieldInformation, fieldOrder
end

function contextWindow.createContextMenu(preset, new)
    local windowX = windowPreviousX
    local windowY = windowPreviousY
    local language = languageRegistry.getLanguage()

    local formData, fieldInformation, fieldOrder = prepareFormData(preset, language, new)

    local saveChangesLanguage = language.ui.LoennPresets.preset_context_window.button.save_changes
    if new then
        saveChangesLanguage = language.ui.LoennPresets.preset_context_window.button.add_preset
    end

    local buttons = {{
            text = tostring(saveChangesLanguage),
            formMustBeValid = true,
            callback = contextWindow.saveChangesCallback(preset, formData, new)
        }, {
            text = tostring(language.ui.LoennPresets.preset_context_window.button.edit_properties),
            callback = contextWindow.editPropertiesCallback(preset)
        }
    }

    if not new then
        table.insert(buttons,{
            text = tostring(language.ui.LoennPresets.preset_context_window.button.delete),
            callback = contextWindow.deleteCallback(preset)
        })
    end

    local windowTitle = getWindowTitle(language, preset)
    local selectionForm = form.getForm(buttons, formData, {
        fields = fieldInformation,
        fieldOrder = fieldOrder
    })

    window = uiElements.window(windowTitle, selectionForm):with({
        x = windowX,
        y = windowY,

        updateHidden = true
    }):hook({
        update = contextWindowUpdate
    })

    contextGroup.parent:addChild(window)
    widgetUtils.addWindowCloseButton(window)
    form.prepareScrollableWindow(window)

    return window
end

-- Group to get access to the main group and sanely inject windows in it
function contextWindow.getWindow()
    contextGroup = uiElements.group({}):with({
        loennPresetsContextMenu = loennPresetsContextMenuCallback
    })

    return contextGroup
end

return contextWindow