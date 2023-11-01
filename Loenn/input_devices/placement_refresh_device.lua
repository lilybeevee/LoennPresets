local toolHandler = require("tools")
local toolUtils = require("tool_utils")
local logging = require("logging")

local device = {}

device.__loennPresetsDevice = true

local needsRefresh = false

function device.update(dt)
    if not needsRefresh then return end

    local tool = toolHandler.currentTool

    if not tool or tool.name ~= "placement" then
        return
    end

    local toolLayer = tool.layer

    -- force the placement tool to update its list of placements
    tool.editorShownDependenciesChanged(tool.layer)

    -- refresh the ui
    toolUtils.sendLayerEvent(tool, "temp")
    toolUtils.sendLayerEvent(tool, toolLayer)

    needsRefresh = false
end

function device.loennPresetsUpdated()
    needsRefresh = true
end

return device