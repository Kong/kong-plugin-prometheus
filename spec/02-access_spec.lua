local helpers = require "spec.helpers"
local pl_file = require "pl.file"

local TCP_SERVICE_PORT = 8189
local TCP_PROXY_PORT = 9007

describe("Plugin: prometheus (access)", function()
  local proxy_client
  local admin_client
  local proxy_client_grpc
  local proxy_client_grpcs

  setup(function()
    local bp = helpers.get_db_utils()

    local service = bp.services:insert {
      name = "mock-service",
      host = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
      protocol = helpers.mock_upstream_protocol,
    }

    bp.routes:insert {
      protocols = { "http" },
      name = "http-route",
      paths = { "/" },
      methods = { "GET" },
      service = service,
    }

    local grpc_service = bp.services:insert {
      name = "mock-grpc-service",
      url = "grpc://grpcbin:9000",
    }

    bp.routes:insert {
      protocols = { "grpc" },
      name = "grpc-route",
      hosts = { "grpc" },
      service = grpc_service,
    }

    local grpcs_service = bp.services:insert {
      name = "mock-grpcs-service",
      url = "grpcs://grpcbin:9001",
    }

    bp.routes:insert {
      protocols = { "grpcs" },
      name = "grpcs-route",
      hosts = { "grpcs" },
      service = grpcs_service,
    }

    local tcp_service = bp.services:insert {
      name = "tcp-service",
      url = "tcp://127.0.0.1:" .. TCP_SERVICE_PORT,
    }

    bp.routes:insert {
      protocols = { "tcp" },
      name = "tcp-route",
      service = tcp_service,
      destinations = { { port = TCP_PROXY_PORT } },
    }

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus"
    }

    helpers.tcp_server(TCP_SERVICE_PORT)
    assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, prometheus",
        stream_listen = "127.0.0.1:" .. TCP_PROXY_PORT,
    })
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
    proxy_client_grpc = helpers.proxy_client_grpc()
    proxy_client_grpcs = helpers.proxy_client_grpcs()
  end)

  teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  it("increments the count for proxied requests", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(200, res)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      return body:find('kong_http_status{service="mock-service",route="http-route",code="200"} 1', nil, true)
    end)

    res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/400",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(400, res)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      return body:find('kong_http_status{service="mock-service",route="http-route",code="400"} 1', nil, true)
    end)
  end)

  it("increments the count for proxied grpc requests", function()
    local ok, resp = proxy_client_grpc({
      service = "hello.HelloService.SayHello",
      body = {
        greeting = "world!"
      },
      opts = {
        ["-authority"] = "grpc",
      }
    })
    assert(ok, resp)
    assert.truthy(resp)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      return body:find('kong_http_status{service="mock-grpc-service",route="grpc-route",code="200"} 1', nil, true)
    end)

    ok, resp = proxy_client_grpcs({
      service = "hello.HelloService.SayHello",
      body = {
        greeting = "world!"
      },
      opts = {
        ["-authority"] = "grpcs",
      }
    })
    assert(ok, resp)
    assert.truthy(resp)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      return body:find('kong_http_status{service="mock-grpcs-service",route="grpcs-route",code="200"} 1', nil, true)
    end)
  end)

  pending("increments the count for proxied TCP streams", function()
    local conn = assert(ngx.socket.connect("127.0.0.1", TCP_PROXY_PORT))

    assert(conn:send("hi there!\n"))
    local gotback = assert(conn:receive("*a"))
    assert.equal("hi there!\n", gotback)

    conn:close()

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      return body:find('kong_stream_status{service="tcp-service",route="tcp-route",code="200"} 1', nil, true)
    end)
  end)

  it("does not log error if no service was matched", function()
    -- cleanup logs
    local test_error_log_path = helpers.test_conf.nginx_err_logs
    os.execute(":> " .. test_error_log_path)

    local res = assert(proxy_client:send {
      method  = "POST",
      path    = "/no-route-match-in-kong",
    })
    assert.res_status(404, res)

    -- make sure no errors
    local logs = pl_file.read(test_error_log_path)
    for line in logs:gmatch("[^\r\n]+") do
      assert.not_match("[error]", line, nil, true)
    end
  end)

  it("does not log error during a scrape", function()
    -- cleanup logs
    local test_error_log_path = helpers.test_conf.nginx_err_logs
    os.execute(":> " .. test_error_log_path)

    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    assert.res_status(200, res)

    -- make sure no errors
    local logs = pl_file.read(test_error_log_path)
    for line in logs:gmatch("[^\r\n]+") do
      assert.not_match("[error]", line, nil, true)
    end
  end)

  it("scrape response has metrics and comments only", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)

    for line in body:gmatch("[^\r\n]+") do
      assert.matches("^[#|kong]", line)
    end

  end)

  it("exposes db reachability metrics", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_datastore_reachable 1', body, nil, true)
  end)

  it("exposes Lua worker VM stats", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_workers_lua_vms_bytes', body, nil, true)
  end)

  it("exposes lua_shared_dict metrics", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_lua_shared_dict_total_bytes' ..
                   '{shared_dict="prometheus_metrics"} 5242880', body, nil, true)
    assert.matches('kong_memory_lua_shared_dict_bytes' ..
                   '{shared_dict="prometheus_metrics"}', body, nil, true)
  end)
end)
