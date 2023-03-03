local uiElements = require("ui.elements")

local languageRegistry = require("language_registry")
local widgetUtils = require("ui.widgets.utils")
local form = require("ui.forms.form")
local layerHandlers = require("layer_handlers")
local formUtils = require("ui.utils.forms")

local contextWindow = {}

local contextGroup
local window
local windowPreviousX = 0
local windowPreviousY = 0

local function loennPresetsPropertyContextMenuCallback(group, preset)
    contextWindow.createContextMenu(preset)
end

local function contextWindowUpdate(orig, self, dt)
    orig(self, dt)

    windowPreviousX = self.x
    windowPreviousY = self.y
end

local function getWindowTitle(language, preset)
    local baseTitle = tostring(language.ui.LoennPresets.preset_property_context_window.title)
    local titleParts = {baseTitle, preset.data._name, preset.name}

    return table.concat(titleParts, " - ")
end

-- TODO - Add history support
function contextWindow.saveChangesCallback(preset, dummyData)
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
    end
end

local function prepareFormData(layer, item, language)
    local handler = layerHandlers.getHandler(layer)
    local options = {}

    return formUtils.prepareFormData(handler, item, options, {layer, item})
end

function contextWindow.createContextMenu(preset)
    local windowX = windowPreviousX
    local windowY = windowPreviousY
    local language = languageRegistry.getLanguage()

    local dummyData, fieldInformation, fieldOrder = prepareFormData(preset.layer, preset.data, language)
    local buttons = {
        {
            text = tostring(language.ui.selection_context_window.save_changes),
            formMustBeValid = true,
            callback = contextWindow.saveChangesCallback(preset, dummyData)
        }
    }

    local windowTitle = getWindowTitle(language, preset)
    local selectionForm = form.getForm(buttons, dummyData, {
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
        loennPresetsPropertyContextMenu = loennPresetsPropertyContextMenuCallback
    })

    return contextGroup
end

return contextWindow