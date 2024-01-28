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

function presetUtils.checkVersion()
    return meta.version == version("0.7.8") or meta.version == version("0.0.0-dev")
end

function presetUtils.saveSettings()
    config.writeConfig(modHandler.getModSettings(), true)
end

return presetUtils