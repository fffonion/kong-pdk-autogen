#!/usr/bin/env resty

require "resty.core"

local lfs = require("lfs")

-- Starts read Kong version
local KONG_PATH = assert(os.getenv("KONG_PATH"), "please specify the KONG_PATH environment variable")

local _log = function(lvl, ctx, ...)
  local msg = {...}
  local f = ctx and ctx.filename
  if f and ctx.lineno > 0 then
    f = f:sub(#KONG_PATH+2)
    table.insert(msg, "(in " .. f .. ":" .. ctx.lineno .. " function:" .. ctx.funcname .. ")")
  end
  print(lvl, table.concat(msg, " "))
end

local logger = function(ctx)
  return {
    error = function(...) _log("- ", ctx, ...) end,
    info = function(...) _log("+ ", ctx, ...) end,
    warn = function(...) _log("* ", ctx, ...) end,
  }
end

local known_types = {
  number = true,
  table = true,
  string = true,
  boolean = true,
  cdata = true,
  err = true,
  ["nil"] = true,
  any = true,
}

local function check_type(type, logger)
  if type:sub(1, 7) == "Nothing" then
    return "nil"
  end
  local types = {}
  for t in type:gmatch('[^%|]+') do
    if not known_types[t] then
      if t == "true" then
        t = "boolean"
      else
        logger.error("got invalid type", t)
      end
    end
    if t ~= "nil" then
      table.insert(types, t)
    end
  end
  -- as long as the types are more than one, we make this a "any" type
  -- since foreign language doesn't necessary support generic or overload
  if #types > 1 then
    return "any"
  end
  return types[1]
end

local section_parsers = {
  treturn = function(line, known, logger)
    known = known or {}
    local type, desc = line:match("([^%s]+)%s*(.*)")

    type = check_type(type, logger)

    table.insert(known, {
      type = type,
      desc = desc,
    })

    return known
  end,

  tparam = function(line, known, logger)
    known = known or {}
    local optional = false
    if line:sub(1, 5) == "[opt]" then
      optional = true
      line = line:sub(7) -- skip a space as well
    end
    local type, name, desc = line:match("([^%s]+)%s+([a-zA-Z0-9_]+)%s*(.*)")

    if type == "..." then
      desc = name .. " " .. desc
      name = "varargs"
      type = "any"
    end

    type = check_type(type, logger)

    table.insert(known, {
      name = name,
      optional = optional,
      type = type,
      desc = desc,
    })

    return known
  end,

  phases = function(line, _, logger)
    local phases = {}
    for phase in line:gmatch('[^,%s]+') do
      phase = phase:match('`?(.+)`?')
      table.insert(phases, phase)
    end
    return phases
  end,
}

local function parse_luadoc(f, known)
  -- current function pointer in the "known" map
  local func
  -- buffer for multiline comments
  local buf = {}
  -- current section name being processed
  local section
  -- context for debugging
  local ctx = {
    filename = f,
    lineno = 0,
    funcname = "",
  }
  local log = logger(ctx)
  log.info("Parse", f)

  local fd = io.open(f)
  while true do
    local line = fd:read("*l")
    if line == nil then
      break
    end

    ctx.lineno = ctx.lineno + 1

    -- "-- @function kong.foo.bar"
    local sect, rest = line:match("%-%-%s+@(%w+)%s*(.*)")
    -- start a new function paragraph
    if sect == "function" then
      -- split kong.foo.bar to [kong, foo, bar]
      func = known
      for path in rest:gmatch('[^%.]+') do
        if not func[path] then
          func[path] = {}
        end
        func = func[path]
      end
      -- reset section name
      section = nil
      ctx.funcname = rest
      func._attr = {
        name = rest,
        desc = table.concat(buf, "\n")
      }
      buf = {}
    -- process sections for current function
    elseif func then
      -- tXXX are typed version of XXX, we will redirect them in same parser
      if sect == "return" then
        sect = "treturn"
      elseif sect == "param" then
        sect = "tparam"
      end

      if not rest then
        -- is this a doc spanning multiline?
        rest = line:match('%-%-%s*(.*)')
      end

      -- ((@XXX exist in line) or (end of comment)) and (has buffer), then process previous buffer
      if (sect ~= nil or rest == nil) and section then
        local concated_buf = table.concat(buf, "\n")
        local parser = section_parsers[section]
        if parser then
          func._attr[section] = parser(concated_buf, func._attr[section], log)
        else -- no parser, store as is
          func._attr[section] = concated_buf
        end
        -- clear the buffer and state
        buf = {}
        section = nil
      end

      if rest == nil then
        -- if rest is nil, we goes beyond comments and likely in lua code
        func = nil
      elseif #rest > 0 then
        table.insert(buf, rest)
      end

      -- set section and buffer based on current line
      if sect then
        section = sect
      end
    else
      if line:match("^%s*%-%-%-") then -- if start comment block
        buf = {}
      end

      local comment_line = line:match("^%s*%-%-%s(.*)")
      if comment_line then
        table.insert(buf, comment_line)
      end
    end
  end

  fd:close()

  return 
end

local function iterate_pdk_files(path, known)
  known = known or {}
  for file in lfs.dir(path) do
    if file ~= "." and file ~= ".." and file ~= "private" then
      file = path .. "/" .. file
      local attr = lfs.attributes(file)
      if attr.mode == "directory" then
        iterate_pdk_files(file, known)
      else
        parse_luadoc(file, known)
      end
    end
  end

  return known
end

return {
  logger = logger,
  iterate_pdk_files = iterate_pdk_files,
}