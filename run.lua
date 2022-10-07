#!/usr/bin/env resty

-- silence _G warnings
setmetatable(_G, nil)

local cjson = require("cjson")
local pl_app = require("pl.app")
local pl_tablex = require("pl.tablex")

local parser = require("parser")
local config = require("config")

local log = parser.logger()

local template_file

local flags = pl_app.parse_args()

local arg_target = flags.t or flags.target
local arg_output = flags.o or flags.output
local autogen_config

if config.targets[arg_target] then
  autogen_config = config.targets[arg_target]
  template_file = io.open(autogen_config.template_file_path):read("*a")
else
  error("target not defined, define with -t/--target=<TARGET>")
end

if not arg_output then
  arg_output = "output"
end

-- Starts read Kong version
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
  log.info("Building PDK interfaces for Kong version " .. KONG_VERSION)
end
-- Ends read Kong version

-- Starts parser routine
log.info("Target is \"" .. arg_target .. "\", output directory is \"" .. arg_output .. "\"")

local pdk_functions = parser.iterate_pdk_files(KONG_PATH .. "/kong/pdk")

for fname, fbody in pairs(config.custom_functions) do
  local ptr = pdk_functions
  for f in fname:gmatch('[^%.]+') do
    if not ptr[f] then
      ptr[f] = {}
    end
    ptr = ptr[f]
  end
  if type(fbody) == "string" then
    local ref = pdk_functions
    for f in fbody:gmatch('[^%.]+') do
      ref = ref[f]
    end
    ptr._attr = pl_tablex.deepcopy(ref._attr)
  else
    ptr._attr = fbody
  end
  ptr._attr.name = fname
end

for fname, fbody in pairs(config.types_override) do
  local ptr = pdk_functions
  for f in fname:gmatch('[^%.]+') do
    if not ptr[f] then
      ptr[f] = {}
    end
    ptr = ptr[f]
  end
  for _, attr in ipairs({ "treturn", "tparam" }) do
    if fbody[attr] then
      for i, t in ipairs(fbody[attr]) do
        if ptr._attr[attr] and ptr._attr[attr][i] then
          ptr._attr[attr][i].type = t.type
        end
      end
    end
  end
end
-- Ends parser routine

-- Starts renderer routine
local pl_template = require("pl.template")
local ct = assert(pl_template.compile(template_file))

local function makedirs(path)
  local parent = path:match('(.+)/[^/]+')
  if parent and not os.rename(parent, parent) then
    makedirs(parent)
  end
  lfs.mkdir(path)
end

local function pairs_sorted(tbl)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], tbl[keys[i]]
    end
  end
end

-- DFS lookup
local function render(path, node)
  local functions = {}
  local subclasses = {}
  local need_render
  for k, v in pairs_sorted(node) do
    if node[k]._attr then
      if not config.ignored_functions_matcher(node[k]._attr.name) then
        functions[k] = node[k]._attr
        need_render = true
      end
    end

    if k ~= "_attr" then
      local sub_need_render = render(path .. "/" .. k, node[k])
      if sub_need_render then
        table.insert(subclasses, k)
        need_render = true
      end
    end
  end

  if not need_render and (next(functions) or next(subclasses)) then
    need_render = true
  end

  if path ~= arg_output and need_render then
    local fp = path .. autogen_config.output_extension
    -- if module directory exists, generate path/index.EXT instead
    if os.rename(path, path) and autogen_config.index_file then
      fp = path .. "/" .. autogen_config.index_file .. autogen_config.output_extension
    end
    log.info("Render", fp)

    local rendered = assert(ct:render({
      class = path:match('.+/([^/]+)$'),
      path = "kong/pdk" .. path:sub(#arg_output+2+4),
      functions = functions,
      subclasses = subclasses,
      -- locals
      type_mappers = autogen_config.type_mappers,
      naming_converter = autogen_config.naming_converter,
      escape = function(...) return ... end,
      kong_version = KONG_VERSION,
      use_index_file = not not autogen_config.index_file,
      -- stdlib
      ipairs = ipairs,
      pairs = pairs,
      pairs_sorted = pairs_sorted,
      table = table,
    }))
    makedirs(fp:match('(.+)/[^/]+'))
    local f = assert(io.open(fp, "w"))
    f:write(rendered)
    f:close()
  end

  return need_render
end

render(arg_output, pdk_functions)

-- Ends renderer routine