local DEFAULT_BUCKETS = { 1, 2, 5, 7, 10, 15, 20, 25, 30, 40, 50, 60, 70,
    80, 90, 100, 200, 300, 400, 500, 1000,
    2000, 5000, 10000, 30000, 60000 }


local BaseCollector = require "kong.plugins.prometheus.collectors.base"

local HttpMetrics = BaseCollector:extend()

function HttpMetrics:new(prometheus)

    -- per service
    self.status = prometheus:counter("http_status",
        "HTTP status codes per service in Kong",
        {"code", "service"})
    self.latency = prometheus:histogram("latency",
        "Latency added by Kong, total request time and upstream latency for each service in Kong",
        {"type", "service"},
        DEFAULT_BUCKETS) -- TODO make this configurable
    self.bandwidth = prometheus:counter("bandwidth",
        "Total bandwidth in bytes consumed per service in Kong",
        {"type", "service"})
end

function HttpMetrics:record(message)
    local service_name
    if message and message.service then
        service_name = message.service.name or message.service.host
    else
        -- do not record any stats if the service is not present
        return
    end

    self.status:inc(1, { message.response.status, service_name })

    local request_size = tonumber(message.request.size)
    if request_size and request_size > 0 then
        self.bandwidth:inc(request_size, { "ingress", service_name })
    end

    local response_size = tonumber(message.response.size)
    if response_size and response_size > 0 then
        self.bandwidth:inc(response_size, { "egress", service_name })
    end

    local request_latency = message.latencies.request
    if request_latency and request_latency >= 0 then
        self.latency:observe(request_latency, { "request", service_name })
    end

    local upstream_latency = message.latencies.proxy
    if upstream_latency ~= nil and upstream_latency >= 0 then
        self.latency:observe(upstream_latency, {"upstream", service_name })
    end

    local kong_proxy_latency = message.latencies.kong
    if kong_proxy_latency ~= nil and kong_proxy_latency >= 0 then
        self.latency:observe(kong_proxy_latency, { "kong", service_name })
    end
end

return HttpMetrics
