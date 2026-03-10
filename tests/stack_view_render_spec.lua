describe("peekstack.ui.stack_view.render", function()
  local config = require("peekstack.config")
  local location = require("peekstack.core.location")
  local diff = require("peekstack.ui.stack_view.diff")
  local pipeline = require("peekstack.ui.stack_view.pipeline")

  local created_buffers = {}

  local function location_for(path, line, character)
    return {
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = line or 0, character = character or 0 },
        ["end"] = { line = line or 0, character = character or 0 },
      },
      provider = "test",
    }
  end

  local function popup(id, opts)
    return vim.tbl_extend("force", {
      id = id,
      title = nil,
      location = location_for(string.format("/tmp/popup_%d.lua", id), 0, 0),
      pinned = false,
    }, opts or {})
  end

  local function track_buffer(bufnr)
    table.insert(created_buffers, bufnr)
    return bufnr
  end

  local function new_source_buffer(lines, filetype)
    local bufnr = track_buffer(vim.api.nvim_create_buf(false, true))
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = filetype or "lua"
    return bufnr
  end

  local function new_target_buffer()
    return track_buffer(vim.api.nvim_create_buf(false, true))
  end

  local function build_model(opts)
    config.setup(opts.config or {})

    local ui_path = config.get().ui.path or {}
    return pipeline.build({
      items = opts.items or {},
      focused_id = opts.focused_id,
      filter = opts.filter,
      win_width = opts.win_width or 80,
      ui_path = ui_path,
      location_text = function(popup_item, max_width)
        return location.display_text(popup_item.location, 0, {
          path_base = ui_path.base,
          max_width = max_width,
          repo_root_cache = opts.repo_root_cache,
        })
      end,
    })
  end

  before_each(function()
    config.setup({})
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    created_buffers = {}
  end)

  it("filters stack entries by query", function()
    local model = build_model({
      items = {
        popup(1, { title = "Alpha" }),
        popup(2, { title = "Beta" }),
      },
      filter = "alp",
    })

    local joined = table.concat(model.lines, "\n")
    assert.is_true(joined:find("Filter: alp", 1, true) ~= nil)
    assert.is_true(joined:find("Alpha", 1, true) ~= nil)
    assert.is_true(joined:find("Beta", 1, true) == nil)
  end)

  it("renders no matches when filter excludes all items", function()
    local model = build_model({
      items = {
        popup(1, { title = "Alpha" }),
      },
      filter = "zzz",
    })

    local joined = table.concat(model.lines, "\n")
    assert.is_true(joined:find("No matches", 1, true) ~= nil)
  end)

  it("renders the default header when filter is not set", function()
    local model = build_model({
      items = {
        popup(1, { title = "Alpha" }),
        popup(2, { title = "Beta" }),
      },
    })

    assert.is_true(model.lines[1]:find("Stack: 2", 1, true) ~= nil)
  end)

  it("caches repo root resolution within a single render build", function()
    local fs = require("peekstack.util.fs")
    local original_repo_root = fs.repo_root
    local repo_calls = 0

    local ok, err = pcall(function()
      fs.repo_root = function(start)
        repo_calls = repo_calls + 1
        assert.equals("/tmp/repo/src", start)
        return "/tmp/repo"
      end

      build_model({
        config = {
          ui = {
            path = {
              base = "repo",
            },
          },
        },
        repo_root_cache = {},
        items = {
          popup(1, { location = location_for("/tmp/repo/src/a.lua", 0, 0) }),
          popup(2, { location = location_for("/tmp/repo/src/b.lua", 0, 0) }),
        },
      })

      assert.equals(1, repo_calls)
    end)
    fs.repo_root = original_repo_root

    if not ok then
      error(err)
    end
  end)

  it("skips line updates when rendered content is unchanged", function()
    local target_bufnr = new_target_buffer()
    local preview_cache = {}
    local model = build_model({
      items = {
        popup(1, { title = "Alpha" }),
        popup(2, { title = "Beta" }),
      },
    })

    local old_keys = diff.apply(target_bufnr, {}, model, preview_cache)

    local original_set_lines = vim.api.nvim_buf_set_lines
    local calls = 0
    local ok, err = pcall(function()
      vim.api.nvim_buf_set_lines = function(...)
        calls = calls + 1
        return original_set_lines(...)
      end

      diff.apply(target_bufnr, old_keys, model, preview_cache)
      assert.equals(0, calls)
    end)
    vim.api.nvim_buf_set_lines = original_set_lines

    if not ok then
      error(err)
    end
  end)

  it("updates only the changed line range when one entry changes", function()
    local target_bufnr = new_target_buffer()
    local preview_cache = {}

    local model_before = build_model({
      items = {
        popup(1, { title = "Alpha" }),
        popup(2, { title = "Beta" }),
      },
    })
    local old_keys = diff.apply(target_bufnr, {}, model_before, preview_cache)

    local model_after = build_model({
      items = {
        popup(1, { title = "Alpha" }),
        popup(2, { title = "Beta updated" }),
      },
    })

    local original_set_lines = vim.api.nvim_buf_set_lines
    local calls = {}
    local ok, err = pcall(function()
      vim.api.nvim_buf_set_lines = function(bufnr, start, finish, strict_indexing, replacement)
        table.insert(calls, {
          start = start,
          finish = finish,
          count = #replacement,
        })
        return original_set_lines(bufnr, start, finish, strict_indexing, replacement)
      end

      diff.apply(target_bufnr, old_keys, model_after, preview_cache)

      assert.equals(1, #calls)
      assert.equals(2, calls[1].start)
      assert.equals(3, calls[1].finish)
      assert.equals(1, calls[1].count)
    end)
    vim.api.nvim_buf_set_lines = original_set_lines

    if not ok then
      error(err)
    end
  end)

  it("renders the empty state with a header", function()
    local model = build_model({ items = {} })
    local joined = table.concat(model.lines, "\n")

    assert.is_true(joined:find("Stack: 0", 1, true) ~= nil)
    assert.is_true(joined:find("No stack entries", 1, true) ~= nil)
  end)

  it("renders a pin badge for pinned items", function()
    local model = build_model({
      items = {
        popup(1, { title = "Alpha", pinned = true }),
      },
    })

    assert.is_true(model.lines[2]:find("• ", 1, true) ~= nil)
  end)

  it("renders tree guides for visible parent-child chains", function()
    local model = build_model({
      items = {
        popup(1, { title = "Parent" }),
        popup(2, { title = "Child", parent_popup_id = 1 }),
      },
    })

    local joined = table.concat(model.lines, "\n")
    assert.is_true(joined:find("└ ", 1, true) ~= nil)
  end)

  it("does not render a tree guide when the parent is filtered out", function()
    local model = build_model({
      items = {
        popup(1, { title = "Parent only" }),
        popup(2, { title = "Child only", parent_popup_id = 1 }),
      },
      filter = "child",
    })

    local child_line = model.lines[2] or ""
    assert.is_true(child_line:find("└ ", 1, true) == nil)
  end)

  it("renders nested and continuation guides based on display order", function()
    local model = build_model({
      items = {
        popup(1, { title = "Root" }),
        popup(2, { title = "First", parent_popup_id = 1 }),
        popup(3, { title = "Second", parent_popup_id = 1 }),
        popup(4, { title = "Second child", parent_popup_id = 3 }),
        popup(5, { title = "Third", parent_popup_id = 1 }),
      },
    })

    local line_by_id = {}
    for line_nr, id in pairs(model.line_to_id) do
      line_by_id[id] = line_nr
    end

    assert.is_true((model.lines[line_by_id[4]] or ""):find("│ └ ", 1, true) ~= nil)
  end)

  it("sorts items in tree order so children follow their parent", function()
    local model = build_model({
      items = {
        popup(1, { title = "Root" }),
        popup(2, { title = "ChildA", parent_popup_id = 1 }),
        popup(3, { title = "ChildB", parent_popup_id = 1 }),
        popup(4, { title = "Grandchild", parent_popup_id = 2 }),
      },
    })

    local line_by_id = {}
    for line_nr, id in pairs(model.line_to_id) do
      line_by_id[id] = line_nr
    end

    assert.is_true(line_by_id[2] < line_by_id[4])
    assert.is_true(line_by_id[4] < line_by_id[3])
  end)

  it("keeps entries visible when parent links are cyclic", function()
    local model = build_model({
      items = {
        popup(1, { title = "Cycle A", parent_popup_id = 2 }),
        popup(2, { title = "Cycle B", parent_popup_id = 1 }),
      },
    })

    local joined = table.concat(model.lines, "\n")
    assert.is_true(joined:find("Cycle A", 1, true) ~= nil)
    assert.is_true(joined:find("Cycle B", 1, true) ~= nil)
  end)

  it("truncates long titles in the render pipeline", function()
    local model = build_model({
      config = {
        ui = {
          path = {
            max_width = 10,
          },
        },
      },
      items = {
        popup(1, { title = "a-very-very-long-title" }),
      },
    })

    local joined = table.concat(model.lines, "\n")
    assert.is_true(joined:find("...", 1, true) ~= nil)
  end)

  it("shows the focus marker only on the focused popup", function()
    local model = build_model({
      items = {
        popup(1, { title = "Alpha" }),
        popup(2, { title = "Beta" }),
      },
      focused_id = 2,
    })

    local focused_count = 0
    for _, line in ipairs(model.lines) do
      if line:find("▶", 1, true) then
        focused_count = focused_count + 1
      end
    end

    assert.equals(1, focused_count)
    assert.is_true((model.lines[3] or ""):find("▶", 1, true) ~= nil)
  end)

  it("renders preview lines with source code and maps them to the popup id", function()
    local source_bufnr = new_source_buffer({ "local x = 42" }, "lua")
    local model = build_model({
      items = {
        popup(1, {
          title = "Alpha",
          source_bufnr = source_bufnr,
          bufnr = source_bufnr,
          location = location_for("/tmp/alpha.lua", 0, 0),
        }),
      },
      focused_id = 1,
    })

    local joined = table.concat(model.lines, "\n")
    assert.is_true(joined:find("local x = 42", 1, true) ~= nil)

    local mapped_lines = {}
    for line_nr, id in pairs(model.line_to_id) do
      if id == 1 then
        table.insert(mapped_lines, line_nr)
      end
    end
    assert.is_true(#mapped_lines >= 2)
  end)

  it("aligns the preview marker with the entry prefix width", function()
    local source_bufnr = new_source_buffer({ "local value = 42" }, "lua")
    local model = build_model({
      items = {
        popup(1, {
          title = "Alpha",
          source_bufnr = source_bufnr,
          bufnr = source_bufnr,
          location = location_for("/tmp/alpha.lua", 0, 0),
        }),
      },
      focused_id = 1,
    })

    local entry_line = model.lines[2]
    local preview_line = model.lines[3]
    assert.is_not_nil(entry_line)
    assert.is_not_nil(preview_line)

    local label_pos = entry_line:find("Alpha", 1, true)
    local marker_pos = preview_line:find("│", 1, true)
    assert.is_not_nil(label_pos)
    assert.is_not_nil(marker_pos)

    local entry_prefix = entry_line:sub(1, label_pos - 1)
    local preview_indent = preview_line:sub(1, marker_pos - 1)
    assert.equals(vim.fn.strdisplaywidth(entry_prefix), vim.fn.strdisplaywidth(preview_indent))
    assert.is_true(preview_line:find("│ local value = 42", 1, true) ~= nil)
  end)

  it("does not crash when the source buffer is invalid for preview rendering", function()
    assert.has_no.errors(function()
      build_model({
        items = {
          popup(1, {
            title = "Alpha",
            source_bufnr = -1,
            bufnr = -1,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
        },
        focused_id = 1,
      })
    end)
  end)

  it("applies treesitter highlights to preview lines when available", function()
    local source_bufnr = new_source_buffer({ "local value = 42" }, "lua")
    local target_bufnr = new_target_buffer()
    local ns = vim.api.nvim_create_namespace("PeekstackStackView")

    local original_get_parser = vim.treesitter.get_parser
    local original_query_get = vim.treesitter.query.get
    local ok, err = pcall(function()
      vim.api.nvim_set_hl(0, "@keyword.peekstack_test_ts", { link = "Keyword" })

      local fake_node = {
        range = function()
          return 0, 0, 0, 5
        end,
      }
      local fake_root = {
        range = function()
          return 0, 0, 0, 20
        end,
      }
      local fake_tree = {
        root = function()
          return fake_root
        end,
        lang = function()
          return "peekstack_test_ts"
        end,
      }
      local fake_query = {
        captures = { "keyword" },
      }
      fake_query.iter_captures = function(_self, _root, _bufnr, _start_row, _end_row)
        local emitted = false
        return function()
          if emitted then
            return nil
          end
          emitted = true
          return 1, fake_node
        end
      end

      vim.treesitter.get_parser = function(_bufnr)
        return {
          parse = function() end,
          trees = function()
            return { fake_tree }
          end,
        }
      end
      vim.treesitter.query.get = function(_lang, _query_name)
        return fake_query
      end

      local model = build_model({
        items = {
          popup(1, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
        },
      })

      diff.apply(target_bufnr, {}, model, {})

      local lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
      local preview_line_nr = nil
      for idx, line in ipairs(lines) do
        if line:find("local value = 42", 1, true) then
          preview_line_nr = idx
          break
        end
      end
      assert.is_not_nil(preview_line_nr)

      local extmarks = vim.api.nvim_buf_get_extmarks(target_bufnr, ns, 0, -1, { details = true })
      local found = false
      for _, mark in ipairs(extmarks) do
        local row = mark[2]
        local details = mark[4] or {}
        if row == preview_line_nr - 1 and details.hl_group == "@keyword.peekstack_test_ts" then
          found = true
          break
        end
      end
      assert.is_true(found, "treesitter highlight should be applied to preview line")
    end)

    vim.treesitter.get_parser = original_get_parser
    vim.treesitter.query.get = original_query_get
    if not ok then
      error(err)
    end
  end)

  it("reuses one parser per source buffer while rendering previews", function()
    local source_bufnr = new_source_buffer({ "local first = 1", "local second = 2" }, "lua")
    local target_bufnr = new_target_buffer()

    local original_get_parser = vim.treesitter.get_parser
    local original_query_get = vim.treesitter.query.get
    local parser_calls = 0
    local parse_calls = 0

    local ok, err = pcall(function()
      vim.api.nvim_set_hl(0, "@keyword.peekstack_test_cache", { link = "Keyword" })

      local fake_node = {
        range = function()
          return 0, 0, 0, 5
        end,
      }
      local fake_root = {
        range = function()
          return 0, 0, 10, 20
        end,
      }
      local fake_tree = {
        root = function()
          return fake_root
        end,
        lang = function()
          return "peekstack_test_cache"
        end,
      }
      local fake_query = {
        captures = { "keyword" },
      }
      fake_query.iter_captures = function(_self, _root, _bufnr, _start_row, _end_row)
        local emitted = false
        return function()
          if emitted then
            return nil
          end
          emitted = true
          return 1, fake_node
        end
      end

      vim.treesitter.get_parser = function(_bufnr)
        parser_calls = parser_calls + 1
        return {
          parse = function()
            parse_calls = parse_calls + 1
          end,
          trees = function()
            return { fake_tree }
          end,
        }
      end
      vim.treesitter.query.get = function(_lang, _query_name)
        return fake_query
      end

      local model = build_model({
        items = {
          popup(1, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
          popup(2, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 1, 0),
          }),
        },
      })

      diff.apply(target_bufnr, {}, model, {})

      assert.equals(1, parser_calls)
      assert.equals(1, parse_calls)
    end)

    vim.treesitter.get_parser = original_get_parser
    vim.treesitter.query.get = original_query_get
    if not ok then
      error(err)
    end
  end)

  it("reuses cached treesitter captures across forced rerenders", function()
    local source_bufnr = new_source_buffer({ "local value = 42" }, "lua")
    local target_bufnr = new_target_buffer()

    local original_get_parser = vim.treesitter.get_parser
    local original_query_get = vim.treesitter.query.get
    local parser_calls = 0
    local capture_calls = 0

    local ok, err = pcall(function()
      vim.api.nvim_set_hl(0, "@keyword.peekstack_test_render_cache", { link = "Keyword" })

      local fake_node = {
        range = function()
          return 0, 0, 0, 5
        end,
      }
      local fake_root = {
        range = function()
          return 0, 0, 0, 20
        end,
      }
      local fake_tree = {
        root = function()
          return fake_root
        end,
        lang = function()
          return "peekstack_test_render_cache"
        end,
      }
      local fake_query = {
        captures = { "keyword" },
      }
      fake_query.iter_captures = function(_self, _root, _bufnr, _start_row, _end_row)
        capture_calls = capture_calls + 1
        local emitted = false
        return function()
          if emitted then
            return nil
          end
          emitted = true
          return 1, fake_node
        end
      end

      vim.treesitter.get_parser = function(_bufnr)
        parser_calls = parser_calls + 1
        return {
          parse = function() end,
          trees = function()
            return { fake_tree }
          end,
        }
      end
      vim.treesitter.query.get = function(_lang, _query_name)
        return fake_query
      end

      local model = build_model({
        items = {
          popup(1, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
        },
      })
      local preview_cache = {}

      diff.apply(target_bufnr, {}, model, preview_cache)
      diff.apply(target_bufnr, {}, model, preview_cache)

      assert.equals(1, parser_calls)
      assert.equals(1, capture_calls)
    end)

    vim.treesitter.get_parser = original_get_parser
    vim.treesitter.query.get = original_query_get
    if not ok then
      error(err)
    end
  end)

  it("skips noisy treesitter captures for preview lines", function()
    local source_bufnr = new_source_buffer({ "local value = 42" }, "lua")
    local target_bufnr = new_target_buffer()
    local ns = vim.api.nvim_create_namespace("PeekstackStackView")

    local original_get_parser = vim.treesitter.get_parser
    local original_query_get = vim.treesitter.query.get
    local ok, err = pcall(function()
      vim.api.nvim_set_hl(0, "@operator.peekstack_test_ts_skip", { link = "Operator" })
      vim.api.nvim_set_hl(0, "@keyword.peekstack_test_ts_skip", { link = "Keyword" })

      local fake_keyword_node = {
        range = function()
          return 0, 0, 0, 5
        end,
      }
      local fake_operator_node = {
        range = function()
          return 0, 12, 0, 13
        end,
      }
      local fake_root = {
        range = function()
          return 0, 0, 0, 20
        end,
      }
      local fake_tree = {
        root = function()
          return fake_root
        end,
        lang = function()
          return "peekstack_test_ts_skip"
        end,
      }
      local fake_query = {
        captures = { "operator", "keyword" },
      }
      fake_query.iter_captures = function(_self, _root, _bufnr, _start_row, _end_row)
        local step = 0
        return function()
          step = step + 1
          if step == 1 then
            return 1, fake_operator_node
          end
          if step == 2 then
            return 2, fake_keyword_node
          end
          return nil
        end
      end

      vim.treesitter.get_parser = function(_bufnr)
        return {
          parse = function() end,
          trees = function()
            return { fake_tree }
          end,
        }
      end
      vim.treesitter.query.get = function(_lang, _query_name)
        return fake_query
      end

      local model = build_model({
        items = {
          popup(1, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
        },
      })

      diff.apply(target_bufnr, {}, model, {})

      local lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
      local preview_line_nr = nil
      for idx, line in ipairs(lines) do
        if line:find("local value = 42", 1, true) then
          preview_line_nr = idx
          break
        end
      end
      assert.is_not_nil(preview_line_nr)

      local extmarks = vim.api.nvim_buf_get_extmarks(target_bufnr, ns, 0, -1, { details = true })
      local has_keyword = false
      local has_operator = false
      for _, mark in ipairs(extmarks) do
        local row = mark[2]
        local details = mark[4] or {}
        if row == preview_line_nr - 1 and details.hl_group == "@keyword.peekstack_test_ts_skip" then
          has_keyword = true
        end
        if row == preview_line_nr - 1 and details.hl_group == "@operator.peekstack_test_ts_skip" then
          has_operator = true
        end
      end

      assert.is_true(has_keyword, "keyword capture should be applied")
      assert.is_false(has_operator, "operator capture should be skipped for preview")
    end)

    vim.treesitter.get_parser = original_get_parser
    vim.treesitter.query.get = original_query_get
    if not ok then
      error(err)
    end
  end)

  it("keeps the default preview highlight when treesitter parsing fails", function()
    local source_bufnr = new_source_buffer({ "local x = 42" }, "lua")
    local target_bufnr = new_target_buffer()
    local ns = vim.api.nvim_create_namespace("PeekstackStackView")

    local original_get_parser = vim.treesitter.get_parser
    local ok, err = pcall(function()
      vim.treesitter.get_parser = function(_bufnr)
        error("parser unavailable")
      end

      local model = build_model({
        items = {
          popup(1, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
        },
      })

      diff.apply(target_bufnr, {}, model, {})

      local lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
      local preview_line_nr = nil
      for idx, line in ipairs(lines) do
        if line:find("local x = 42", 1, true) then
          preview_line_nr = idx
          break
        end
      end
      assert.is_not_nil(preview_line_nr)

      local extmarks = vim.api.nvim_buf_get_extmarks(target_bufnr, ns, 0, -1, { details = true })
      local found = false
      for _, mark in ipairs(extmarks) do
        local row = mark[2]
        local details = mark[4] or {}
        if row == preview_line_nr - 1 and details.hl_group == "PeekstackStackViewPreview" then
          found = true
          break
        end
      end
      assert.is_true(found, "default preview highlight should remain when treesitter fails")
    end)

    vim.treesitter.get_parser = original_get_parser
    if not ok then
      error(err)
    end
  end)

  it("clamps treesitter highlight ranges on truncated preview lines", function()
    local source_bufnr = new_source_buffer({ string.rep("a", 400) }, "lua")
    local target_bufnr = new_target_buffer()
    local ns = vim.api.nvim_create_namespace("PeekstackStackView")

    local original_get_parser = vim.treesitter.get_parser
    local original_query_get = vim.treesitter.query.get
    local ok, err = pcall(function()
      vim.api.nvim_set_hl(0, "@string.peekstack_test_trunc", { link = "String" })

      local fake_node = {
        range = function()
          return 0, 0, 0, 400
        end,
      }
      local fake_root = {
        range = function()
          return 0, 0, 0, 400
        end,
      }
      local fake_tree = {
        root = function()
          return fake_root
        end,
        lang = function()
          return "peekstack_test_trunc"
        end,
      }
      local fake_query = {
        captures = { "string" },
      }
      fake_query.iter_captures = function(_self, _root, _bufnr, _start_row, _end_row)
        local emitted = false
        return function()
          if emitted then
            return nil
          end
          emitted = true
          return 1, fake_node
        end
      end

      vim.treesitter.get_parser = function(_bufnr)
        return {
          parse = function() end,
          trees = function()
            return { fake_tree }
          end,
        }
      end
      vim.treesitter.query.get = function(_lang, _query_name)
        return fake_query
      end

      local model = build_model({
        items = {
          popup(1, {
            source_bufnr = source_bufnr,
            bufnr = source_bufnr,
            location = location_for("/tmp/alpha.lua", 0, 0),
          }),
        },
        win_width = 40,
      })

      diff.apply(target_bufnr, {}, model, {})

      local lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
      local preview_line_nr = nil
      for idx, line in ipairs(lines) do
        if line:find("│ a", 1, true) then
          preview_line_nr = idx
          break
        end
      end
      assert.is_not_nil(preview_line_nr)
      local preview_len = #lines[preview_line_nr]

      local extmarks = vim.api.nvim_buf_get_extmarks(target_bufnr, ns, 0, -1, { details = true })
      for _, mark in ipairs(extmarks) do
        local row = mark[2]
        local details = mark[4] or {}
        if row == preview_line_nr - 1 and details.hl_group == "@string.peekstack_test_trunc" then
          assert.is_true((details.end_col or 0) <= preview_len)
        end
      end
    end)

    vim.treesitter.get_parser = original_get_parser
    vim.treesitter.query.get = original_query_get
    if not ok then
      error(err)
    end
  end)
end)
