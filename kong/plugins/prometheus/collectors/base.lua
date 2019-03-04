local Object = require "kong.vendor.classic"

local BaseCollector = Object:extend()

function BaseCollector:new()
end

function BaseCollector:record(request)
end

function BaseCollector:collect()
end

return BaseCollector
