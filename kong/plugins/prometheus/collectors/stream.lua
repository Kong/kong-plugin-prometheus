local BaseCollector = require "kong.plugins.prometheus.collectors.base"

local StreamMetrics = BaseCollector:extend()

function StreamMetrics:new(prometheus)
    -- per service

    self.bandwidth = prometheus:counter("bandwidth",
        "Total bandwidth in bytes consumed per service in Kong",
        {"type", "service"})
end

function StreamMetrics:record(message)
    local service_name
    if message and message.service then
        service_name = message.service.name or message.service.host
    else
        -- do not record any stats if the service is not present
        return
    end

    local request_size = message.request and message.request.size and tonumber(message.request.size) or 0
    if request_size and request_size > 0 then
        self.bandwidth:inc(request_size, { "ingress", service_name })
    end

    local response_size = message.response and message.response.size and tonumber(message.response.size) or 0
    if response_size and response_size > 0 then
        self.bandwidth:inc(response_size, { "egress", service_name })
    end
end

return StreamMetrics
