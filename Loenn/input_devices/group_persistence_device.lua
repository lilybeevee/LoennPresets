local modHandler = require("mods")
local logging = require("logging")

local presetGroups = modHandler.requireFromPlugin("libraries.preset_groups")

local device = {}

device.__loennPresetsDevice = true

function device.editorMapLoaded(filename)
    local targetGroup = presetGroups.getPersistenceGroupForMap(filename)

    if not targetGroup then
        presetGroups.setPersistenceGroupForMap(filename, presetGroups.current)
    else
        presetGroups.setCurrent(targetGroup)
    end
end

return device