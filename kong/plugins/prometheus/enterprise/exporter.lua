local kong = kong
local ngx = ngx
local sub = string.sub
local floor = math.floor

local metrics = {}


local function init(prometheus)
  metrics.license_errors = prometheus:counter("enterprise_license_errors",
                                              "Errors when collecting license info")
  metrics.license_signature = prometheus:gauge("enterprise_license_signature",
                                              "Last 32 bytes of the license signautre in number")
  metrics.license_expiration = prometheus:gauge("enterprise_license_expiration",
                                                "Unix epoch time when the license expires, " ..
                                                "the timestamp is substracted by 24 hours "..
                                                "to avoid difference in timezone")
  metrics.license_features = prometheus:gauge("enterprise_license_features",
                                                "License features features",
                                              { "feature" })
end

local function isleap(year)
  return (year % 4) == 0 and ((year % 100) > 0 or (year % 400) == 0)
end

local past = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
local function day_of_year(year, mon, mday)
  local d = past[mon] + mday - 1
  if mon > 2 and isleap(year) then
    d = d + 1
  end
  return d
end

local function leaps(year)
  return floor(year / 400) + floor(year / 4) - floor(year / 100)
end

local function license_date_to_unix(yyyy_mm_dd)
  local year = tonumber(sub(yyyy_mm_dd, 1, 4))
  local month = tonumber(sub(yyyy_mm_dd, 6, 7))
  local day = tonumber(sub(yyyy_mm_dd, 9, 10))

  local tm
  tm = (year - 1970) * 365
  tm = tm + leaps(year - 1) - leaps(1969)
  tm = (tm + day_of_year(year, month, day)) * 24
  tm = tm * 3600
  
  return tm
end

local function metric_data()
  if not metrics then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not kong.license or not kong.license.license then
    metrics.license_errors:inc()
    kong.log.err("cannot read kong.license when collecting license info")
    return
  end

  local lic = kong.license.license

  if lic.version ~= 1 then
    metrics.license_errors:inc()
    kong.log.err("enterprise license version (" .. (lic.version or "nil") .. ") unsupported")
    return
  end

  local sig = lic.signature
  if not sig then
    metrics.license_errors:inc()
    kong.log.err("cannot read license signature when collecting license info")
    return
  end
  -- last 32 bytes as an int32
  metrics.license_signature:set(tonumber("0x" .. sub(sig, #sig-33, #sig)))

  local expiration = lic.payload and lic.payload.license_expiration_date
  if not expiration then
    metrics.license_errors:inc()
    kong.log.err("cannot read license expiration when collecting license info")
    return
  end
  expiration = license_date_to_unix(expiration)
  if not license_date_to_unix then
    metrics.license_errors:inc()
    kong.log.err("cannot parse license expiration when collecting license info")
    return
  end
  -- substract it by 24h so everyone one earth is happy monitoring it
  metrics.license_expiration:set(expiration - 86400)


  metrics.license_features:set(kong.licensing:can("ee_plugins") and 1 or 0,
                              { "ee_plugins" })

  metrics.license_features:set(kong.licensing:can("write_admin_api") and 1 or 0,
                              { "write_admin_api" })
end


return {
  init        = init,
  metric_data = metric_data,
}
