local lu = require("luaunit")
local cli = require("dry4lua.cli")

TestCli = {}

function TestCli:test_defaults()
  local options = cli.parse_args({})
  lu.assertEquals(options.threshold, 0.82)
  lu.assertEquals(options.min_lines, 4)
  lu.assertEquals(options.min_nodes, 20)
  lu.assertEquals(options.limit, nil)
  lu.assertEquals(options.format, "text")
  lu.assertEquals(options.help, false)
  lu.assertEquals(options.paths[1], "src")
  lu.assertEquals(#options.paths, 1)
end

function TestCli:test_explicit_paths()
  local options = cli.parse_args({ "lib", "tests/fixtures" })
  lu.assertEquals(options.paths[1], "lib")
  lu.assertEquals(options.paths[2], "tests/fixtures")
end

function TestCli:test_value_options()
  local options = cli.parse_args({
    "--threshold", "0.5",
    "--min-lines", "8",
    "--min-nodes", "40",
    "--limit", "3",
  })
  lu.assertEquals(options.threshold, 0.5)
  lu.assertEquals(options.min_lines, 8)
  lu.assertEquals(options.min_nodes, 40)
  lu.assertEquals(options.limit, 3)
end

function TestCli:test_format_flags()
  lu.assertEquals(cli.parse_args({ "--json" }).format, "json")
  lu.assertEquals(cli.parse_args({ "--text" }).format, "text")
  lu.assertEquals(cli.parse_args({ "--json", "--text" }).format, "text")
end

function TestCli:test_help_flag()
  lu.assertEquals(cli.parse_args({ "--help" }).help, true)
  lu.assertEquals(cli.parse_args({ "-h" }).help, true)
end

local function expect_exit(code, args)
  local real_exit = os.exit
  os.exit = function(value) error("exit:" .. tostring(value), 0) end
  local ok, err = pcall(cli.parse_args, args)
  os.exit = real_exit
  lu.assertTrue(not ok, "expected os.exit")
  lu.assertEquals(err, "exit:" .. tostring(code))
end

function TestCli:test_unknown_option_exits_with_code_2()
  expect_exit(2, { "--nope" })
end

function TestCli:test_non_numeric_option_value_exits_with_code_2()
  expect_exit(2, { "--threshold", "abc" })
end

function TestCli:test_negative_limit_exits_with_code_2()
  expect_exit(2, { "--limit", "-1" })
end

function TestCli:test_missing_path_fails_with_exit_code_1()
  local real_stderr = io.stderr
  local written = {}
  io.stderr = { write = function(_, text) written[#written + 1] = text end }
  local ok, code = pcall(cli.run, { ROOT .. "/tests/no_such_dir" })
  io.stderr = real_stderr
  lu.assertTrue(ok, tostring(code))
  lu.assertEquals(code, 1)
  lu.assertStrContains(table.concat(written), "no_such_dir")
end

return TestCli
