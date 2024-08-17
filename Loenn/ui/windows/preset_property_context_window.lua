local uiElements = require("ui.elements")

local languageRegistry = require("language_registry")
local widgetUtils = require("ui.widgets.utils")
local form = require("ui.forms.form")
local layerHandlers = require("layer_handlers")
local formUtils = require("ui.utils.forms")

local windowPersister = require("ui.window_position_persister")
local windowPersisterName = "LoennPresets.preset_property_context_window"

local contextWindow = {}

local contextGroup

local function loennPresetsPropertyContextMenuCallback(group, preset)
    contextWindow.createContextMenu(preset)
end

local function getWindowTitle(language, preset)
    local baseTitle = tostring(language.ui.LoennPresets.preset_property_context_window.title)
    local titleParts = {baseTitle, preset.data._name, preset.name}

    return table.concat(titleParts, " - ")
end

-- TODO - Add history support
function contextWindow.saveChangesCallback(context, preset, dummyData)
    return function(formFields)
        local newData = form.getFormData(formFields)

        -- Apply nil values from new data
        for k, v in pairs(dummyData) do
            if newData[k] == nil then
                preset.data[k] = nil
            end
        end

        for k, v in pairs(newData) do
            preset.data[k] = v
        end

        context.window:removeSelf()
    end
end

local function prepareFormData(layer, item, language)
    local handler = layerHandlers.getHandler(layer)
    local options = {}

    return formUtils.prepareFormData(handler, item, options, {layer, item})
end

function contextWindow.createContextMenu(preset)
    local language = languageRegistry.getLanguage()

    local dummyData, fieldInformation, fieldOrder = prepareFormData(preset.layer, preset.data, language)

    local context = {}

    local buttons = {
        {
            text = tostring(language.ui.selection_context_window.save_changes),
            formMustBeValid = true,
            callback = contextWindow.saveChangesCallback(context, preset, dummyData)
        }
    }

    local windowTitle = getWindowTitle(language, preset)
    local selectionForm, formFields = form.getForm(buttons, dummyData, {
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
        loennPresetsPropertyContextMenu = loennPresetsPropertyContextMenuCallback
    })

    return contextGroup
end

return contextWindow