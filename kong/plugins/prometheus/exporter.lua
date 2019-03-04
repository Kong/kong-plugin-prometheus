local prometheus
local collectors = {}
local exporter

local function init()
  local shm = "prometheus_metrics"
  if not ngx.shared[shm] then
    kong.log.err("prometheus: ngx shared dict '" .. shm .. "' not found")
    return
  end

  prometheus = require("kong.plugins.prometheus.prometheus").init(shm, "kong_")

  if ngx.config.subsystem == "stream" then
    collectors = {
      require("kong.plugins.prometheus.collectors.stream").new(prometheus)
    }
    exporter = require("kong.plugins.prometheus.exporters.stream")
  elseif ngx.config.subsystem == "http" then
    collectors = {
      require("kong.plugins.prometheus.collectors.http").new(prometheus),
      require("kong.plugins.prometheus.collectors.kong").new(prometheus),
      require("kong.plugins.prometheus.collectors.nginx").new(prometheus)
    }
    exporter = require("kong.plugins.prometheus.exporters.http")
  end
end

local function record(request)
  if not prometheus then
    kong.log.err("prometheus: can not log metrics because of an initialization "
            .. "error, please make sure that you've declared "
            .. "'" .. shm .. "' shared dict in your nginx template")
    return
  end

  for i in ipairs(collectors) do
    collectors[i].record(request)
  end
end

--- At the moment, Lua code running in the context of HTTP module cannot share
-- any state with Lua code running in the context of Streaming module
-- (even through shared memory).
-- That's why we're forced to have 2 separate endpoints with Prometheus metrics:
-- one for HTTP module and another for Streaming module.
-- However, we don't want our users to start depending on it -
-- from their perspective there should be a single Prometheus endpoint.
-- To achieve this, Prometheus endpoint of HTTP module will be making
-- a sub-request to the Prometheus endpoint of Streaming module under the hood.
local function export(opts)
  if not prometheus then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
      " '" .. shm .. "' shared dict is present in nginx template")
    return exporter.server_error()
  end

  for i in ipairs(collectors) do
    collectors[i].collect()
  end

  exporter.export(prometheus, opts)
end

return {
  init    = init,
  log     = record,
  collect = export
}
