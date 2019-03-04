local BaseCollector = require "kong.plugins.prometheus.collectors.base"

local KongMetrics = BaseCollector:extend()

function KongMetrics:new(prometheus)
    -- across all services

    self.db_reachable = prometheus:gauge("datastore_reachable",
        "Datastore reachable from Kong, 0 is unreachable")
end

function KongMetrics:collect()
    -- update Guages in here

    -- db reachable?
    local ok, err = kong.db.connector:connect()
    if ok then
        self.db_reachable:set(1)

    else
        self.db_reachable:set(0)
        kong.log.err("prometheus: failed to reach database while processing",
            "/metrics endpoint: ", err)
    end
end

return KongMetrics
