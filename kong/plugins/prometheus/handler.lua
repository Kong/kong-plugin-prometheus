local prometheus = require "kong.plugins.prometheus.exporter"
local kong = kong


prometheus.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "1.1.0",
}

function PrometheusHandler.init_worker()
  prometheus.init_worker()
end


function PrometheusHandler.log(self, conf)
  local message = kong.log.serialize()

  local serialized = {
    param_list = conf.param_collect_list,
    param_extract = conf.param_value_extract,
    location = conf.location_collect,
    location_extract = conf.location_extract,
  }
  if conf.per_consumer and message.consumer ~= nil then
    serialized.consumer = message.consumer.username
  end

  prometheus.log(message, serialized)
end


return PrometheusHandler
