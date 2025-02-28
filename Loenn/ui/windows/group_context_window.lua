local ui = require("ui")
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
local windowPersisterName = "LoennPresets.group_context_window"

local presetGroups = mods.requireFromPlugin("libraries.preset_groups")

local contextWindow = {}

local contextGroup

local function loennPresetsGroupContextMenuCallback(group, groupName, new)
    contextWindow.createContextMenu(groupName, new)
end

local function getWindowTitle(language, groupName, new)
    if new then
        return tostring(language.ui.LoennPresets.group_context_window.title.new)
    else
        local baseTitle = tostring(language.ui.LoennPresets.group_context_window.title.edit)
        local titleParts = {baseTitle, groupName}

        return table.concat(titleParts, " - ")
    end
end

function contextWindow.saveChangesCallback(context, groupName)
    return function(formFields)
        local data = form.getFormData(formFields)

        local backupIndex = tonumber(data.backup)

        if backupIndex and backupIndex > 0 then
            presetGroups.loadBackup(groupName, backupIndex)

            sceneHandler.sendEvent("loennPresetsGroupsUpdated")

            context.window:removeSelf()
            return
        end

        if groupName == "global" then
            context.window:removeSelf()
            return
        end

        if data.name == "" or (groupName ~= data.name and presetGroups.getGroup(data.name)) then
            -- Invalid name
            return false
        end

        presetGroups.saveGroupAndBackup(groupName)
        presetGroups.renameBackups(groupName, data.name)

        local group = presetGroups.getGroup(groupName)

        presetGroups.setGroup(groupName, nil)
        presetGroups.setGroup(data.name, group)

        presetGroups.current = data.name
        presetGroups.updatePersistence()

        sceneHandler.sendEvent("loennPresetsGroupsUpdated")

        context.window:removeSelf()
    end
end

function contextWindow.createGroupCallback(context, copy)
    return function(formFields)
        local data = form.getFormData(formFields)

        if data.name == "" or presetGroups.getGroup(data.name) then
            -- Invalid name
            return false
        end

        presetGroups.setCurrent(data.name, {create = true, copy = true})

        sceneHandler.sendEvent("loennPresetsGroupsUpdated")

        context.window:removeSelf()
    end
end

function contextWindow.deleteGroupCallback(context, groupName)
    return function()
        if groupName == "global" then
            -- should be unreachable
            return
        end

        presetGroups.saveBackup(groupName)

        presetGroups.setGroup(groupName, nil)

        local targetGroup = presetGroups.getFirstAvailableGroup()
        presetGroups.setCurrent(targetGroup, {backup = false})

        sceneHandler.sendEvent("loennPresetsGroupsUpdated")

        context.window:removeSelf()
    end
end

local function createBackupOptions(groupName)
    local options = {
        {"...", "0"}
    }

    local savedBackups = presetGroups.getSavedBackups()
    local groupBackups = savedBackups[groupName] or {}

    for i, backup in ipairs(groupBackups) do
        table.insert(options, {backup.name, tostring(i)})
    end

    return options
end

local function prepareFormData(groupName, new, language)
    local formData = {}
    local fieldInformation = {}

    if groupName ~= "global" then
        formData.name = groupName or "New Group"
        fieldInformation.name = {
            displayName = tostring(language.ui.LoennPresets.group_context_window.field.name.name),
            tooltipText = tostring(language.ui.LoennPresets.group_context_window.field.name.description),
        }
    end

    if not new then
        formData.backup = "..."
        fieldInformation.backup = {
            displayName = tostring(language.ui.LoennPresets.group_context_window.field.backup.name),
            tooltipText = tostring(language.ui.LoennPresets.group_context_window.field.backup.description),
            editable = false,
            options = createBackupOptions(groupName)
        }
    end

    local fieldOrder = {"name", "backup"}

    return formData, fieldInformation, fieldOrder
end

function contextWindow.createContextMenu(groupName, new)
    local language = languageRegistry.getLanguage()

    local formData, fieldInformation, fieldOrder = prepareFormData(groupName, new, language)
    local buttons

    local context = {}

    if new then
        buttons = {{
            text = tostring(language.ui.LoennPresets.group_context_window.button.create),
            callback = contextWindow.createGroupCallback(context, false)
        }, {
            text = tostring(language.ui.LoennPresets.group_context_window.button.create_from_current),
            callback = contextWindow.createGroupCallback(context, true)
        }}
    else
        buttons = {{
            text = tostring(language.ui.LoennPresets.group_context_window.button.save_changes),
            callback = contextWindow.saveChangesCallback(context, groupName)
        }}
        if groupName ~= "global" then
            table.insert(buttons, {
                text = tostring(language.ui.LoennPresets.group_context_window.button.delete),
                callback = contextWindow.deleteGroupCallback(context, groupName)
            })
        end
    end

    local windowTitle = getWindowTitle(language, groupName, new)
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
        loennPresetsGroupContextMenu = loennPresetsGroupContextMenuCallback
    })

    return contextGroup
end

return contextWindow