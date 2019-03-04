local function export(prometheus, opts)
    prometheus:collect{handler=function(output)
        ngx.header.content_type = "text/plain"
        ngx.print(output)
    end}

    local opts = opts or {}
    local modules = opts.modules or {}
    local stream = modules.stream or {}
    if stream and stream.port then
        local http = require "resty.http"

        local httpc = http.new()
        httpc:set_timeout(stream.timeout or 30000)
        local host = stream.host or "localhost"
        local port = stream.port
        local ok, err = httpc:connect(host, port)
        if not ok then
            kong.log.err("failed to connect to ", host, ":", tostring(port), ": ", err)
            return false
        end

        local res, err = httpc:request({method = "GET", path = "/metrics"})
        if not res then
            kong.log.err("failed request to ", host, ":", tostring(port), ": ", err)
            httpc:set_keepalive(false)
            return false
        end

        local body, err = res:read_body()
        if not body then
            kong.log.err("no response body from ", host, ":", tostring(port), ": ", err)
            httpc:set_keepalive(false)
            return false
        end

        ok, err = httpc:set_keepalive(false)
        if not ok then
            kong.log.err("failed keepalive for ", host, ":", tostring(port), ": ", err)
        end

        ngx.say()
        ngx.say(body)
    end
end

local function server_error()
    kong.response.exit(500, { message = "An unexpected error occurred" })
end

return {
    export       = export,
    server_error = server_error,
}
