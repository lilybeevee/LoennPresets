local version = require("utils.version_parser")
local meta = require("meta")
local modHandler = require("mods")
local config = require("utils.config")

local presetUtils = {}

function presetUtils.toLookup(tbl)
    local lookup = {}

    for _, v in ipairs(tbl) do
        lookup[v] = true
    end

    return lookup
end

-- This should make sure we're running the latest supported version, but it's disabled while I'm not actively maintaining it
function presetUtils.checkVersion()
    --return meta.version == version("0.7.10") or meta.version == version("0.0.0-dev")
    return true
end

function presetUtils.saveSettings()
    config.writeConfig(modHandler.getModSettings(), true)
end

return presetUtils