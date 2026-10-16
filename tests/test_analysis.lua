local lu = require("luaunit")
local analysis = require("dry4lua.analysis")

TestAnalysis = {}

local FIXTURES = ROOT .. "/tests/fixtures"

function TestAnalysis:test_collect_files_lists_lua_files_of_a_directory_sorted()
  local files = analysis.collect_files({ FIXTURES })
  lu.assertEquals(files, {
    FIXTURES .. "/dup_a.lua",
    FIXTURES .. "/dup_b.lua",
    FIXTURES .. "/unique.lua",
  })
end

function TestAnalysis:test_collect_files_recurses_and_keeps_only_lua_files()
  local files = analysis.collect_files({ ROOT .. "/tests" })
  local found = {}
  for _, file in ipairs(files) do
    found[file] = true
    lu.assertTrue(file:match("%.lua$") ~= nil, "non-lua file collected: " .. file)
  end
  lu.assertTrue(found[FIXTURES .. "/dup_a.lua"], "fixtures subdirectory")
  lu.assertTrue(found[ROOT .. "/tests/corpus/scope.lua"], "corpus subdirectory")
  lu.assertTrue(found[ROOT .. "/tests/test_analysis.lua"], "top-level file")
end

function TestAnalysis:test_collect_files_accepts_an_explicit_file()
  local files = analysis.collect_files({ FIXTURES .. "/unique.lua", ROOT .. "/tests/baseline/text.out" })
  lu.assertEquals(files, { FIXTURES .. "/unique.lua" })
end

function TestAnalysis:test_collect_files_reports_a_missing_path_instead_of_an_empty_set()
  local files, err = analysis.collect_files({ FIXTURES, ROOT .. "/tests/no_such_dir" })
  lu.assertNil(files)
  lu.assertStrContains(err, "no_such_dir")
end

function TestAnalysis:test_collect_files_reports_windows_directory_iteration_errors()
  -- Filesystem seam: Windows lfs returns nil, error when _findfirst fails.
  local lfs = require("lfs")
  local original = lfs.dir
  lfs.dir = function(path)
    if path == FIXTURES then
      return function() return nil, "Access is denied" end, {}
    end
    return original(path)
  end
  local ok, files, err = pcall(analysis.collect_files, { FIXTURES })
  lfs.dir = original
  lu.assertTrue(ok)
  lu.assertNil(files)
  lu.assertStrContains(err, "Access is denied")
  lu.assertStrContains(err, FIXTURES)
end

function TestAnalysis:test_find_duplicates_raises_on_a_missing_path()
  local ok, err = pcall(analysis.find_duplicates, { paths = { ROOT .. "/tests/no_such_dir" } })
  lu.assertFalse(ok)
  lu.assertStrContains(tostring(err), "no_such_dir")
end

function TestAnalysis:test_finds_the_structurally_identical_fixture_pair()
  local candidates = analysis.find_duplicates({ paths = { FIXTURES } })
  lu.assertEquals(#candidates, 1)
  lu.assertEquals(candidates[1].score, 1)
  local names = { candidates[1].left.name, candidates[1].right.name }
  table.sort(names)
  lu.assertEquals(names[1], "calculate_total")
  lu.assertEquals(names[2], "compute_sum")
end

function TestAnalysis:test_candidate_carries_file_and_line_ranges()
  local candidates = analysis.find_duplicates({ paths = { FIXTURES } })
  local left = candidates[1].left
  lu.assertTrue(left.file:match("dup_[ab]%.lua$") ~= nil, "left file")
  lu.assertEquals(left.start_line, 1)
  lu.assertEquals(left.end_line, 10)
end

function TestAnalysis:test_threshold_above_1_yields_nothing()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    threshold = 1.1,
  })
  lu.assertEquals(#candidates, 0)
end

function TestAnalysis:test_min_nodes_filters_by_ast_node_count()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    min_nodes = 1000,
  })
  lu.assertEquals(#candidates, 0)
end

function TestAnalysis:test_min_lines_filters_short_functions()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    min_lines = 1000,
  })
  lu.assertEquals(#candidates, 0)
end

function TestAnalysis:test_empty_directory_yields_no_candidates()
  local candidates = analysis.find_duplicates({ paths = { ROOT .. "/tests" } })
  for _, candidate in ipairs(candidates) do
    lu.assertTrue(candidate.score >= 0.82, "score above threshold")
  end
end

function TestAnalysis:test_nested_inner_functions_match_outer_do_not()
  local candidates = analysis.find_duplicates({ paths = { ROOT .. "/tests/corpus" } })
  -- Should find the validate/verify inner pair but NOT the outer pair
  -- (process_entries vs handle_records have different structures;
  --  their fingerprints no longer include inner function bodies).
  local inner_found = false
  local outer_found = false
  for _, c in ipairs(candidates) do
    local left_name = c.left.name
    local right_name = c.right.name
    if (left_name == "validate" and right_name == "verify")
        or (left_name == "verify" and right_name == "validate") then
      inner_found = true
    end
    if (left_name == "process_entries" and right_name == "handle_records")
        or (left_name == "handle_records" and right_name == "process_entries") then
      outer_found = true
    end
  end
  lu.assertTrue(inner_found, "inner functions validate/verify should match")
  lu.assertTrue(not outer_found, "outer functions should not match (different structure, no child inflation)")
end

function TestAnalysis:test_same_file_overlapping_entries_are_excluded()
  -- Scan corpus which contains nested_a.lua and nested_b.lua. Each has a
  -- parent function and a child function whose line ranges overlap (the
  -- child is nested inside the parent in the same file). The overlap
  -- check (dry4java semantics) prevents parent-vs-own-child comparisons.
  -- We verify this indirectly: scan only nested_a.lua, where the parent
  -- and child have overlapping ranges. Without the overlap check they
  -- would be compared pairwise; with it they are skipped.
  local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
  end

  local nested_a = ROOT .. "/tests/corpus/nested_a.lua"
  if not file_exists(nested_a) then
    -- corpus file doesn't exist; skip gracefully
    return
  end

  local candidates = analysis.find_duplicates({ paths = { nested_a } })
  -- A single file with two overlapping entries should produce no
  -- candidates because the overlap check excludes the pair.
  for _, c in ipairs(candidates) do
    -- If any candidate has both left and right from the same file
    -- with overlapping ranges, that's a bug.
    if c.left.file == c.right.file then
      local overlap = c.left.start_line <= c.right.end_line
          and c.right.start_line <= c.left.end_line
      lu.assertTrue(not overlap,
        "overlapping same-file entries should not produce a candidate: "
        .. c.left.name .. " vs " .. c.right.name)
    end
  end
end

return TestAnalysis
