local counter = require "resty.counter"

local kong = kong
local ngx = ngx
local find = string.find
local select = select

local DEFAULT_BUCKETS = { 1, 2, 5, 7, 10, 15, 20, 25, 30, 40, 50, 60, 70,
                          80, 90, 100, 200, 300, 400, 500, 1000,
                          2000, 5000, 10000, 30000, 60000 }
local metrics = {}
-- prometheus.lua instance
local prometheus
-- lua-resty-counter instance
local counter_instance


local function init()
  local shm = "prometheus_metrics"
  if not ngx.shared.prometheus_metrics then
    kong.log.err("prometheus: ngx shared dict 'prometheus_metrics' not found")
    return
  end

  prometheus = require("kong.plugins.prometheus.prometheus").init(shm, "kong_")

  -- global metrics
  metrics.connections = prometheus:gauge("nginx_http_current_connections",
                                         "Number of HTTP connections",
                                         {"state"})
  metrics.db_reachable = prometheus:gauge("datastore_reachable",
                                          "Datastore reachable from Kong, " ..
                                          "0 is unreachable")
  local memory_stats = {}
  memory_stats.worker_vms = prometheus:gauge("memory_workers_lua_vms_bytes",
                                             "Allocated bytes in worker Lua VM",
                                             {"pid"})
  memory_stats.shms = prometheus:gauge("memory_lua_shared_dict_bytes",
                                       "Allocated slabs in bytes in a shared_dict",
                                       {"shared_dict"})
  memory_stats.shm_capacity = prometheus:gauge("memory_lua_shared_dict_total_bytes",
                                               "Total capacity in bytes of a shared_dict",
                                               {"shared_dict"})

  local res = kong.node.get_memory_stats()
  for shm_name, value in pairs(res.lua_shared_dicts) do
    memory_stats.shm_capacity:set(value.capacity, {shm_name})
  end

  metrics.memory_stats = memory_stats

  -- per service/route
  metrics.status = prometheus:counter("http_status",
                                      "HTTP status codes per service/route in Kong",
                                      {"code", "service", "route"})
  metrics.latency = prometheus:histogram("latency",
                                         "Latency added by Kong, total " ..
                                         "request time and upstream latency " ..
                                         "for each service/route in Kong",
                                         {"type", "service", "route"},
                                         DEFAULT_BUCKETS) -- TODO make this configurable
  metrics.bandwidth = prometheus:counter("bandwidth",
                                         "Total bandwidth in bytes " ..
                                         "consumed per service/route in Kong",
                                         {"type", "service", "route"})
end

local function init_worker()
  local err
  -- create a lua-resty-counter instance with sync interval of every second
  counter_instance, err = counter.new("prometheus_metrics", 1)
  if err then
    error(err)
  end
  prometheus:set_resty_counter(counter_instance)
end

local function log(message)
  if not metrics then
    kong.log.err("prometheus: can not log metrics because of an initialization "
                 .. "error, please make sure that you've declared "
                 .. "'prometheus_metrics' shared dict in your nginx template")
    return
  end

  local service_name
  if message and message.service then
    service_name = message.service.name or message.service.host
  else
    -- do not record any stats if the service is not present
    return
  end

  local route_name
  if message and message.route then
    route_name = message.route.name or message.route.id
  end

  metrics.status:inc(1, { message.response.status, service_name, route_name })

  local request_size = tonumber(message.request.size)
  if request_size and request_size > 0 then
    metrics.bandwidth:inc(request_size, { "ingress", service_name, route_name })
  end

  local response_size = tonumber(message.response.size)
  if response_size and response_size > 0 then
    metrics.bandwidth:inc(response_size, { "egress", service_name, route_name })
  end

  local request_latency = message.latencies.request
  if request_latency and request_latency >= 0 then
    metrics.latency:observe(request_latency, { "request", service_name, route_name })
  end

  local upstream_latency = message.latencies.proxy
  if upstream_latency ~= nil and upstream_latency >= 0 then
    metrics.latency:observe(upstream_latency, { "upstream", service_name, route_name })
  end

  local kong_proxy_latency = message.latencies.kong
  if kong_proxy_latency ~= nil and kong_proxy_latency >= 0 then
    metrics.latency:observe(kong_proxy_latency, { "kong", service_name, route_name })
  end
end


local function collect()
  if not prometheus or not metrics then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local r = ngx.location.capture "/nginx_status"

  if r.status ~= 200 then
    kong.log.warn("prometheus: failed to retrieve /nginx_status ",
                  "while processing /metrics endpoint")

  else
    local accepted, handled, total = select(3, find(r.body,
                                            "accepts handled requests\n (%d*) (%d*) (%d*)"))
    metrics.connections:set(accepted, { "accepted" })
    metrics.connections:set(handled, { "handled" })
    metrics.connections:set(total, { "total" })
  end

  metrics.connections:set(ngx.var.connections_active, { "active" })
  metrics.connections:set(ngx.var.connections_reading, { "reading" })
  metrics.connections:set(ngx.var.connections_writing, { "writing" })
  metrics.connections:set(ngx.var.connections_waiting, { "waiting" })

  -- db reachable?
  local ok, err = kong.db.connector:connect()
  if ok then
    metrics.db_reachable:set(1)

  else
    metrics.db_reachable:set(0)
    kong.log.err("prometheus: failed to reach database while processing",
                 "/metrics endpoint: ", err)
  end

  -- memory stats
  local res = kong.node.get_memory_stats()
  for shm_name, value in pairs(res.lua_shared_dicts) do
    metrics.memory_stats.shms:set(value.allocated_slabs, {shm_name})
  end
  for i = 1, #res.workers_lua_vms do
    metrics.memory_stats.worker_vms:set(res.workers_lua_vms[i].http_allocated_gc,
                                        {res.workers_lua_vms[i].pid})
  end

  -- force a manual sync of counter local state to make integration test working
  counter_instance:sync()

  prometheus:collect()
end


return {
  init        = init,
  init_worker = init_worker,
  log         = log,
  collect     = collect,
}
