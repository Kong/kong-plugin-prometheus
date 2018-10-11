local Schema = require("kong.db.schema")
local prometheus = require "kong.plugins.prometheus.exporter"


return {

  ["/metrics"] = {
    schema = Schema.new(), -- not used, could be any schema
    methods = {
      GET = function()
        prometheus.collect()
      end,
    },
  },
}
