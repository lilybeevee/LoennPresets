local version = require("utils.version_parser")
local meta = require("meta")

local presetUtils = {}

function presetUtils.toLookup(tbl)
    local lookup = {}

    for _, v in ipairs(tbl) do
        lookup[v] = true
    end

    return lookup
end

function presetUtils.checkVersion()
    return meta.version == version("0.5.1") or meta.version == version("0.0.0-dev")
end

return presetUtils