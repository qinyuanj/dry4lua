local analysis = require("dry4lua.analysis")

local cli = {}

local USAGE = [[
Usage: dry4lua [options] [file-or-directory ...]
       lua5.4 bin/dry4lua [options] [file-or-directory ...]

Options:
  --threshold N   Minimum structural similarity score, default 0.82
  --min-lines N   Minimum source lines in a candidate function, default 4
  --min-nodes N   Minimum AST node count in a candidate function, default 20
  --limit N       Maximum text duplicate rows to print, 0 means no limit
  --json          Output in JSON format
  --text          Output in text format (default)
  --help          Show this help message]]

local function format_location(entry)
  return entry.file .. ":" .. entry.start_line .. "-" .. entry.end_line
end

local function format_text(candidates, limit)
  if #candidates == 0 then
    print("No duplicate candidates found.")
    return
  end
  local printed = #candidates
  if limit ~= nil and limit > 0 and limit < printed then
    printed = limit
  end
  for index = 1, printed do
    local candidate = candidates[index]
    if index > 1 then
      io.write("\n")
    end
    io.write(string.format("DUPLICATE score=%.2f\n", candidate.score))
    io.write("  " .. format_location(candidate.left) .. "  " .. candidate.left.name .. "\n")
    io.write("  " .. format_location(candidate.right) .. "  " .. candidate.right.name .. "\n")
  end
  if printed < #candidates then
    io.write(string.format(
      "\nShowing %d of %d duplicate candidates. Use --limit 0 to show all.\n",
      printed,
      #candidates
    ))
  end
end

local function json_escape(str)
  return str:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
end

local function format_json_entry(entry)
  return string.format(
    '{"file":"%s","name":"%s","start_line":%d,"end_line":%d}',
    json_escape(entry.file), json_escape(entry.name),
    entry.start_line, entry.end_line
  )
end

local function format_json(candidates)
  io.write('{"candidates":[')
  for index, candidate in ipairs(candidates) do
    if index > 1 then
      io.write(",")
    end
    io.write(string.format(
      '{"score":%.4f,"left":%s,"right":%s}',
      candidate.score,
      format_json_entry(candidate.left),
      format_json_entry(candidate.right)
    ))
  end
  io.write("]}\n")
end

local VALUE_OPTIONS = {
  ["--threshold"] = "threshold",
  ["--min-lines"] = "min_lines",
  ["--min-nodes"] = "min_nodes",
  ["--limit"] = "limit",
}

function cli.parse_args(args)
  local options = {
    paths = {},
    threshold = 0.82,
    min_lines = 4,
    min_nodes = 20,
    limit = nil,
    format = "text",
    help = false,
  }
  local index = 1
  while index <= #args do
    local arg_value = args[index]
    if arg_value == "--help" or arg_value == "-h" then
      options.help = true
      return options
    elseif arg_value == "--json" then
      options.format = "json"
    elseif arg_value == "--text" then
      options.format = "text"
    elseif VALUE_OPTIONS[arg_value] then
      index = index + 1
      local number = tonumber(args[index])
      if not number then
        io.stderr:write("Error: " .. arg_value .. " requires a numeric value\n")
        os.exit(2)
      end
      if arg_value == "--limit" and number < 0 then
        io.stderr:write("Error: --limit must be zero or greater\n")
        os.exit(2)
      end
      options[VALUE_OPTIONS[arg_value]] = number
    elseif arg_value:sub(1, 2) == "--" then
      io.stderr:write("Error: unknown option " .. arg_value .. "\n")
      os.exit(2)
    else
      options.paths[#options.paths + 1] = arg_value
    end
    index = index + 1
  end
  if #options.paths == 0 then
    options.paths = { "src" }
  end
  return options
end

function cli.run(args)
  local options = cli.parse_args(args)
  if options.help then
    print(USAGE)
    return 0
  end
  local ok, candidates = pcall(analysis.find_duplicates, options)
  if not ok then
    io.stderr:write("Error: " .. tostring(candidates) .. "\n")
    return 1
  end
  if options.format == "json" then
    format_json(candidates)
  else
    format_text(candidates, options.limit)
  end
  return 0
end

return cli
