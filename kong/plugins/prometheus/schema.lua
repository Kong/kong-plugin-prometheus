local function validate_shared_dict()
  if not ngx.shared.prometheus_metrics then
    return nil,
           "ngx shared dict 'prometheus_metrics' not found"
  end
  return true
end


return {
  name = "prometheus",
  fields = {
    { config = {
        type = "record",
        fields = {
          { param_collect_list = { type = "array", elements = { type = "string", match = "^[a-z_]+$" }, }, },
          { param_value_extract  = { type = "string" }, },	-- regex
          { location_collect = { type = "boolean", default = false }, },
          { location_extract = { type = "string" }, },	-- regex
          { per_consumer = { type = "boolean", default = false }, },
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
