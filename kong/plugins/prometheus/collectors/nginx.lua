local find = string.find
local select = select

local BaseCollector = require "kong.plugins.prometheus.collectors.base"

local NginxMetrics = BaseCollector:extend()

function NginxMetrics:new(prometheus)

    -- across all services
    self.connections = prometheus:gauge("nginx_connections",
        "Number of NGINX connections",
        {"state"})
end

function NginxMetrics:collect()
    -- update Guages in here

    local r = ngx.location.capture "/nginx_status"

    if r.status ~= 200 then
        kong.log.warn("prometheus: failed to retrieve /nginx_status ",
            "while processing /metrics endpoint")

    else
        local accepted, handled, total = select(3, find(r.body,
            "accepts handled requests\n (%d*) (%d*) (%d*)"))
        self.connections:set(accepted, { "accepted" })
        self.connections:set(handled, { "handled" })
        self.connections:set(total, { "total" })
    end

    self.connections:set(ngx.var.connections_active, { "active" })
    self.connections:set(ngx.var.connections_reading, { "reading" })
    self.connections:set(ngx.var.connections_writing, { "writing" })
    self.connections:set(ngx.var.connections_waiting, { "waiting" })
end

return NginxMetrics
