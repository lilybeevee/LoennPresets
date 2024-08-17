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

local windowPersister = require("ui.window_position_persister")
local windowPersisterName = "LoennPresets.preset_context_window"

local presets = mods.requireFromPlugin("libraries.presets")

local contextWindow = {}

local contextGroup

local function loennPresetsContextMenuCallback(group, preset, new)
    contextWindow.createContextMenu(preset, new)
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

function contextWindow.saveChangesCallback(context, preset, formData, new)
    return function(formFields)
        local newData = form.getFormData(formFields)

        local oldName = preset.name
        local newName = newData.name

        if preset.global then
            newName = preset.name
        end

        local nameValid = newName ~= ""

        if (new or oldName ~= newName) and presets.getPreset(preset.layer, newName) then
            nameValid = false
        end

        if not nameValid then return end

        if not new then
            presets.removePreset(preset.layer, preset)
        end

        if not preset.global then
            preset.name = newData.name
        end
        preset.keepSize = newData.keepSize

        presets.addPreset(preset.layer, preset)

        updateFavorites(preset.layer, oldName, newName, newData.favorite)

        sceneHandler.sendEvent("loennPresetsUpdated")

        context.window:removeSelf()
    end
end

function contextWindow.editPropertiesCallback(preset)
    return function()
        sceneHandler.sendEvent("loennPresetsPropertyContextMenu", preset, false)
    end
end

function contextWindow.deleteCallback(context ,preset)
    return function()
        if preset.global then
            -- should never happen
            return
        end

        presets.removePreset(preset.layer, preset)

        updateFavorites(preset.layer, preset.name, "", false)

        sceneHandler.sendEvent("loennPresetsUpdated")

        context.window:removeSelf()
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

    if preset.global then
        formData.name = nil
    end

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
    local language = languageRegistry.getLanguage()

    local formData, fieldInformation, fieldOrder = prepareFormData(preset, language, new)

    local saveChangesLanguage = language.ui.LoennPresets.preset_context_window.button.save_changes
    if new then
        saveChangesLanguage = language.ui.LoennPresets.preset_context_window.button.add_preset
    end

    local context = {}

    local buttons = {{
            text = tostring(saveChangesLanguage),
            formMustBeValid = true,
            callback = contextWindow.saveChangesCallback(context, preset, formData, new)
        }, {
            text = tostring(language.ui.LoennPresets.preset_context_window.button.edit_properties),
            callback = contextWindow.editPropertiesCallback(preset)
        }
    }

    if not new and not preset.global then
        table.insert(buttons,{
            text = tostring(language.ui.LoennPresets.preset_context_window.button.delete),
            callback = contextWindow.deleteCallback(context, preset)
        })
    end

    local windowTitle = getWindowTitle(language, preset)
    local selectionForm, formFields = form.getForm(buttons, formData, {
        fields = fieldInformation,
        fieldOrder = fieldOrder
    })

    local window = uiElements.window(windowTitle, selectionForm)
    local windowCloseCallback = windowPersister.getWindowCloseCallback(windowPersisterName)

    context.window = window

    windowPersister.trackWindow(windowPersisterName, window)
    contextGroup.parent:addChild(window)
    widgetUtils.addWindowCloseButton(window, windowCloseCallback)
    widgetUtils.preventOutOfBoundsMovement(window)
    form.prepareScrollableWindow(window)
    form.addTitleChangeHandler(window, windowTitle, formFields)

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