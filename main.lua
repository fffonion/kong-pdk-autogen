#!/usr/bin/env resty

require "resty.core"

local lfs = require("lfs")
local cjson = require("cjson")
local pl_tablex = require("pl.tablex")

local KONG_PATH = assert(os.getenv("KONG_PATH"), "please specify the KONG_PATH environment variable")

package.path = KONG_PATH .. "/?.lua;" .. KONG_PATH .. "/?/init.lua;" .. package.path

local pok, kong_meta = pcall(require, "kong.meta")
if not pok then
  error("failed loading Kong modules. please set the KONG_PATH environment variable.")
end
local meta_version = kong_meta._VERSION_TABLE.major .. "." .. kong_meta._VERSION_TABLE.minor .. ".x"

local KONG_VERSION = os.getenv("KONG_VERSION")
if KONG_VERSION then
--  -- Commented out because kong.meta in `next` branch is always behind :(
--
--  if meta_version ~= KONG_VERSION then
--    error("KONG_VERSION environment variable does not match Kong version in sources.")
--  end
else
  KONG_VERSION = meta_version
  print("Building PDK interfaces for Kong version " .. KONG_VERSION)
end

local function parse_treturn(line, known)
  known = known or {}
  local type, desc = line:match("([^%s]+)%s*(.*)")

  table.insert(known, {
    type = type,
    desc = desc,
  })

  return known
end

local function parse_tparam(line, known)
  known = known or {}
  local optional = false
  if line:sub(1, 5) == "[opt]" then
    optional = true
    line = line:sub(7) -- skip a space as well
  end
  local type, name, desc = line:match("([^%s]+)%s+([^%s]+)%s*(.*)")

  if type == "..." then
    desc = name .. " " .. desc
    name = "varags"
  elseif type:sub(1, 7) == "Nothing" then
    type = "nil"
  end

  known[name] = {
    optional = optional,
    type = type,
    desc = desc,
  }

  return known
end

local function parse_phases(line)
  local phases = {}
  for phase in line:gmatch('[^,%s]+') do
    phase = phase:match('`?(.+)`?')
    table.insert(phases, phase)
  end
  return phases
end

local section_parsers = {
  treturn = parse_treturn,
  tparam  = parse_tparam,
  phases  = parse_phases,
}

local function parse_luadoc(f, known)
  print("parse ", f)
  -- current function pointer in the "known" map
  local func
  -- current section name being processed
  local section

  local buf = {}

  local fd = io.open(f)
  while true do
    local line = fd:read("*l")
    if line == nil then
      break
    end

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
    -- process sections for current function
    elseif func then
      -- XXX: typo in pdk?
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
          func[section] = parser(concated_buf, func[section])
        else -- no parser, store as is
          func[section] = concated_buf
        end
        -- clear the buffer and state
        buf = {}
        section = nil
      end

      if rest == nil then
        -- if rest is nil, we goes beyond comments and likely in lua code
        func = nil
      else
        table.insert(buf, rest)
      end

      -- set section and buffer based on current line
      if sect then
        section = sect
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

local pdk_functions = iterate_pdk_files(KONG_PATH .. "/kong/pdk")

io.open("/tmp/a.json", "w"):write(require("cjson").encode(pdk_functions))
