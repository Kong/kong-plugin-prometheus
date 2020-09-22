local prometheus = require "kong.plugins.prometheus.exporter"

if ngx.config.subsystem == "stream" then
  local stream_api = require "kong.tools.stream_api"

  stream_api.register_endpoint("/stream-metrics", function(req)
    req:get_headers()
    return req:response(200, { ["Content-Type"] = "text/plain; charset=UTF-8" },
            prometheus:collect())
  end)

else
  local resty_http = require "resty.http"
  local STREAM_API_PORT = 8086    -- TODO: get from config

  local function pull_from_stream()
    local httpc = resty_http.new()
    assert(httpc:connect("localhost", STREAM_API_PORT))

    local res = assert(httpc:request({ method = "GET", path="/stream-metrics" }))
    local body = res:read_body()

    httpc:set_keepalive(false)

    return body
  end


  return {
    ["/metrics"] = {
      GET = function()
        ngx.header.content_type = "text/plain; charset=UTF-8"

        ngx.say(prometheus:collect())
        ngx.say(pull_from_stream())
      end,
    },
  }
end
