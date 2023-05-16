local config = {
  targets = {

    python = {
      template_file_path = "templates/python.template",
      output_extension = ".py",
      type_mappers = {
        ["string"] = "str",
        ["boolean"] = "bool",
        ["any"] = "Any",
        ["nil"] = "None",
      },
      -- as-is
      naming_converter = function(...) return ... end,
      index_file = "__init__",
    },
  
    javascript = {
      template_file_path = "templates/ts.template",
      output_extension = ".d.ts",
      type_mappers = {
        ["table"] = "Array<string | number> | object",
        ["nil"] = "null",
        ["bytes"] = "Buffer",
      },
      -- underscore_case to camelCase
      naming_converter = function(s, cap)
        local s = string.gsub(s, "[a-z]_[a-z]", function(g)
          return string.sub(g, 1, 1) .. string.sub(g, 3, 4):upper()
        end)
        if cap then
          s = s:sub(1, 1):upper() .. s:sub(2)
        end
        return s
      end,
      index_file = "index",
    }

  },

  ignored_functions = {
    "kong.table",
    "kong.log$", -- avoid collision with kong.log.X
    "kong.log.LEVEL",
    "kong.log.inspect", -- TODO: maybe we need it?
    "kong.service.set_tls_cert_key",
    "kong.service.set_tls_verify_store",
    "kong.tracing", -- tracing returns lua table, so doesn't work out of the box
    "kong.vault.try", -- accepts a Lua function, unsupported
  },

  custom_functions = {
    ["kong.log.serialize"] = {
      phases = {
        -- TODO
      },
    },

    ["kong.nginx.get_var"] = {
      treturn = {
        {
          type = "string",
          desc = "get NGINX variable value",
        },
      },
      phases = {
        -- TODO
      },
    },
    ["kong.nginx.get_tls1_version_str"] = {
      treturn = {
        {
          type = "string",
          desc = "the TLSv1 version string",
        },
      },
      phases = {
        -- TODO
      },
    },
    ["kong.nginx.get_subsystem"] = {
      treturn = {
        {
          type = "string",
          desc = "the subsystem name",
        },
      },
      phases = {
        -- TODO
      },
    },

    ["kong.nginx.get_ctx"] = {
      tparam = {
        {
          name = "k",
          type = "string",
          desc = "key for the ctx data",
        }
      },
      treturn = {
        {
          type = "any",
          desc = "the per-request context data in ngx.ctx",
        },
      },
      phases = {
        -- TODO
      },
      desc = "get a key-value pair from Kong's per-request context",
    },
    ["kong.nginx.set_ctx"] = {
      tparam = {
        {
          name = "k",
          type = "string",
          desc = "key for the ctx data",
        },
        {
          name = "any",
          type = "string",
          desc = "value for the ctx data",
        }
      },
      phases = {
        -- TODO
      },
      desc = "set a key-value pair in Kong's per-request context",
    },

    ["kong.nginx.shared.get"] = {
      tparam = {
        {
          name = "k",
          type = "string",
          desc = "key for the ctx data",
        }
      },
      treturn = {
        {
          type = "any",
          desc = "the per-request context data in ngx.ctx",
        },
      },
      phases = {
        -- TODO
      },
      desc = "get a key-value pair from Kong's shared memory",
    },
    ["kong.nginx.shared.set"] = {
      tparam = {
        {
          name = "k",
          type = "string",
          desc = "key for the ctx data",
        },
        {
          name = "v",
          type = "string",
          desc = "value for the ctx data",
        }
      },
      phases = {
        -- TODO
      },
      desc = "set a key-value pair in Kong's shared memory",
    },

    ["kong.nginx.req_start_time"] = {
      treturn = {
        {
          type = "number",
        },
      },
      phases = {
        -- TODO
      },
      desc = "get the current request's start timestamp",
    },

    ["kong.log.alert"] = "kong.log.LEVEL",
    ["kong.log.crit"] = "kong.log.LEVEL",
    ["kong.log.err"] = "kong.log.LEVEL",
    ["kong.log.warn"] = "kong.log.LEVEL",
    ["kong.log.notice"] = "kong.log.LEVEL",
    ["kong.log.info"] = "kong.log.LEVEL",
    ["kong.log.debug"] = "kong.log.LEVEL",
  },

  types_override = {
    ["kong.response.set_raw_body"] = {
      tparam = {
        {
          name = "body",
          type = "bytes",
        },
      },
    },
    ["kong.request.get_raw_body"] = {
      treturn = {
        {
          type = "bytes",
        },
      },
    },
    ["kong.response.get_raw_body"] = {
      treturn = {
        {
          type = "bytes",
        },
      },
    },
    ["kong.service.response.get_raw_body"] = {
      treturn = {
        {
          type = "bytes",
        },
      },
    },
    ["kong.response.exit"] = {
      tparam = {
        {
          name = "status",
          type = "number",
        },
        {
          name = "body",
          type = "bytes",
        },
      },
    },
  },
}

config.custom_functions["kong.ctx.shared.get"] = config.custom_functions["kong.nginx.shared.get"]
config.custom_functions["kong.ctx.shared.set"] = config.custom_functions["kong.nginx.shared.set"]

config.ignored_functions_matcher = function(f)
  for _, p in ipairs(config.ignored_functions) do
    if f:match(p) then
      return true
    end
  end
end

return config
