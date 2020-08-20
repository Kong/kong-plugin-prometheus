local prometheus = require "kong.plugins.prometheus.exporter"


prometheus.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "0.9.1",
}

function PrometheusHandler.init_worker()
  prometheus.init_worker()
end


function PrometheusHandler.log()
  local message = kong.log.serialize()
  prometheus.log(message)
end


return PrometheusHandler
