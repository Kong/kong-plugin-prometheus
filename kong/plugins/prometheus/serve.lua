local lapis = require "lapis"
local prometheus = require "kong.plugins.prometheus.exporter"

local stream_available, stream_api = pcall(require, "kong.tools.stream_api")


local kong = kong


local app = lapis.Application()


app.default_route = function(self)
  local path = self.req.parsed_url.path:match("^(.*)/$")

  if path and self.app.router:resolve(path, self) then
    return

  elseif self.app.router:resolve(self.req.parsed_url.path .. "/", self) then
    return
  end

  return self.app.handle_404(self)
end


app.handle_404 = function(self) -- luacheck: ignore 212
  local body = '{"message":"Not found"}'
  ngx.status = 404
  ngx.header["Content-Type"] = "application/json; charset=utf-8"
  ngx.header["Content-Length"] = #body + 1
  ngx.say(body)
end


app:match("/", function()
  kong.response.exit(200, "Kong Prometheus exporter, visit /metrics")
end)


app:match("/metrics", function()
  ngx.header.content_type = "text/plain; charset=UTF-8"

  ngx.print(prometheus:collect())

  if stream_available then
    ngx.print(stream_api.request("prometheus", "") or "")
  end
end)


return {
  prometheus_server = function()
    return lapis.serve(app)
  end,
}
