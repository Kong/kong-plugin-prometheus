local prometheus = require "kong.plugins.prometheus.exporter"
local stream_available, stream_api = pcall(require, "kong.tools.stream_api")

return {
  ["/metrics"] = {
    GET = function()
      ngx.header.content_type = "text/plain; charset=UTF-8"

      ngx.print(prometheus:collect())

      if stream_available then
        ngx.print(stream_api.request("prometheus", ""))
      end
    end,
  },

  _stream = stream_available and function()
    return prometheus:collect()
  end or nil,
}
