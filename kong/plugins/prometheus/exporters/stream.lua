local function consume_request()
    local sock = assert(ngx.req.socket(true))
    repeat
        local data = sock:receive()  -- read a line from downstream
    until data
end

local function export(prometheus, opts)
    consume_request()

    prometheus:collect{handler=function(output)
        -- compute the value for `Content-Length` header
        local len=0
        for _, line in ipairs(output) do
            len = len + #line
        end
        len = len + 1

        -- at the moment, we only expect internal usage of that endpoint,
        -- that's why we don't parse the request and assume usage HTTP/1.1
        ngx.say("HTTP/1.1 200 OK")
        ngx.say("Content-Type: text/plain; charset=UTF-8")
        ngx.say("Content-Length: " .. len)
        ngx.say("Connection: close")
        ngx.say()
        ngx.say(output)
    end}
end

local function server_error()
    ngx.say("HTTP/1.1 500 Internal Server Error")
    ngx.say("Connection: close")
end

return {
    export       = export,
    server_error = server_error,
}
