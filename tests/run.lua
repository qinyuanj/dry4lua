-- luaunit test runner for dry4lua (ADR-0005). Usage: lua5.4 tests/run.lua
-- Discovers tests/test_*.lua (fixtures/corpus/baseline are test data, not
-- suites; bench.lua is not a test file), loads each file, and runs the
-- returned luaunit test tables as a single suite.
local script = arg[0] or "tests/run.lua"
ROOT = script:match("^(.+)/tests/run%.lua$") or "."
package.path = ROOT .. "/src/?.lua;" .. package.path

local luacheck_dir = os.getenv("LUACHECK_DIR")
if luacheck_dir then
  package.path = luacheck_dir .. "/?.lua;" .. luacheck_dir .. "/?/init.lua;" .. package.path
end

local lu = require("luaunit")
local lfs = require("lfs")

-- Suites live directly under tests/ (fixtures/corpus/baseline are data
-- directories), so a flat listing is enough and needs no external `find`.
local function discover_test_files()
  local dir = ROOT .. "/tests"
  local files = {}
  local ok, iter, state = pcall(lfs.dir, dir)
  if not ok then
    io.stderr:write("cannot list test directory " .. dir .. ": " .. tostring(iter) .. "\n")
    os.exit(1)
  end
  for name in iter, state do
    local path = dir .. "/" .. name
    if name:match("^test_.*%.lua$") and lfs.attributes(path, "mode") == "file" then
      files[#files + 1] = path
    end
  end
  table.sort(files)
  return files
end

local function suite_name_for(path)
  local base = tostring(path):match("([^/]+)%.lua$") or tostring(path)
  return (base:gsub("[^%w_]", "_"))
end

local test_files = discover_test_files()
if #test_files == 0 then
  io.stderr:write("no test files discovered under " .. ROOT .. "/tests\n")
  os.exit(1)
end

local instances = {}
for _, file in ipairs(test_files) do
  local chunk, load_err = loadfile(file)
  if chunk == nil then
    io.stderr:write("cannot load test file " .. file .. ": " .. tostring(load_err) .. "\n")
    os.exit(1)
  end
  local ok, suite = pcall(chunk)
  if not ok then
    io.stderr:write("test file " .. file .. " failed to load: " .. tostring(suite) .. "\n")
    os.exit(1)
  end
  if type(suite) ~= "table" then
    io.stderr:write("test file " .. file .. " must return a luaunit test table\n")
    os.exit(1)
  end
  instances[#instances + 1] = { suite_name_for(file), suite }
end

local runner = lu.LuaUnit.new()
os.exit(runner:runSuiteByInstancesNoCmdLineParsing(instances) > 0 and 1 or 0)
