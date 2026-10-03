describe("peekstack.picker.telescope", function()
  local picker = require("peekstack.picker.telescope")
  local original_modules = {}

  local function save_module(name)
    original_modules[name] = package.loaded[name]
  end

  local function restore_modules()
    for name, mod in pairs(original_modules) do
      package.loaded[name] = mod
    end
    original_modules = {}
  end

  before_each(function()
    save_module("telescope.pickers")
    save_module("telescope.finders")
    save_module("telescope.config")
    save_module("telescope.actions")
    save_module("telescope.actions.state")
  end)

  after_each(function()
    restore_modules()
  end)

  it("sets preview metadata and returns selected location", function()
    local captured = {}
    local picked = nil

    package.loaded["telescope.config"] = {
      values = {
        generic_sorter = function()
          return "sorter"
        end,
        grep_previewer = function()
          return "previewer"
        end,
      },
    }
    package.loaded["telescope.finders"] = {
      new_table = function(opts)
        captured.finder = opts
        return opts
      end,
    }
    package.loaded["telescope.actions"] = {
      close = function(bufnr)
        captured.closed_bufnr = bufnr
      end,
    }
    package.loaded["telescope.actions.state"] = {
      get_selected_entry = function()
        return captured.selected
      end,
    }
    package.loaded["telescope.pickers"] = {
      new = function(_, spec)
        captured.spec = spec
        return {
          find = function()
            captured.mappings = {}
            spec.attach_mappings(nil, function(mode, key, fn)
              captured.mappings[mode .. key] = fn
            end)
            captured.selected = captured.finder.results[2]
            captured.mappings["i<CR>"](13)
          end,
        }
      end,
    }

    local loc1 = {
      uri = "file:///tmp/a.lua",
      range = { start = { line = 1, character = 2 }, ["end"] = { line = 1, character = 2 } },
      text = "Alpha",
      provider = "test",
    }
    local loc2 = {
      uri = "file:///tmp/b.lua",
      range = { start = { line = 4, character = 0 }, ["end"] = { line = 4, character = 0 } },
      provider = "test",
    }

    picker.pick({ loc1, loc2 }, nil, function(choice)
      picked = choice
    end)

    assert.equals("sorter", captured.spec.sorter)
    assert.equals("previewer", captured.spec.previewer)
    local display, highlights = captured.finder.results[1].display()
    assert.equals("Alpha - /tmp/a.lua:2:3", display)
    assert.same({
      { { 0, 5 }, "Function" },
      { { 5, 8 }, "Comment" },
      { { 8, 13 }, "Comment" },
      { { 13, 18 }, "Directory" },
      { { 18, 19 }, "Comment" },
      { { 19, 20 }, "Number" },
      { { 20, 21 }, "Comment" },
      { { 21, 22 }, "Number" },
    }, highlights)
    assert.equals("Alpha - /tmp/a.lua:2:3 /tmp/a.lua", captured.finder.results[1].ordinal)
    assert.equals("/tmp/a.lua", captured.finder.results[1].filename)
    assert.equals(2, captured.finder.results[1].lnum)
    assert.equals(3, captured.finder.results[1].col)
    assert.equals(13, captured.closed_bufnr)
    assert.are.same(loc2, picked)

    picked = nil
    captured.selected = captured.finder.results[1]
    captured.mappings["n<CR>"](14)
    assert.equals(14, captured.closed_bufnr)
    assert.are.same(loc1, picked)
  end)
  ---@param display string
  ---@param highlights table
  ---@return string[]
  local function highlighted_texts(display, highlights)
    local texts = {}
    for _, block in ipairs(highlights) do
      texts[#texts + 1] = display:sub(block[1][1] + 1, block[1][2])
    end
    return texts
  end

  ---@param locations PeekstackLocation[]
  ---@return table[]
  local function collect_entries(locations)
    local results = nil
    package.loaded["telescope.config"] = {
      values = {
        generic_sorter = function() end,
        grep_previewer = function() end,
      },
    }
    package.loaded["telescope.finders"] = {
      new_table = function(opts)
        results = opts.results
        return opts
      end,
    }
    package.loaded["telescope.pickers"] = {
      new = function()
        return { find = function() end }
      end,
    }
    picker.pick(locations, nil, function() end)
    return results
  end

  it("shows the file name, line and column without a symbol", function()
    local entries = collect_entries({
      {
        uri = "file:///tmp/dir/b.lua",
        range = { start = { line = 4, character = 0 }, ["end"] = { line = 4, character = 0 } },
        provider = "test",
      },
    })

    local display, highlights = entries[1].display()
    assert.equals("/tmp/dir/b.lua:5:1", display)
    assert.same({ "/tmp/dir/", "b.lua", ":", "5", ":", "1" }, highlighted_texts(display, highlights))
  end)

  it("uses byte offsets for multibyte symbols and paths", function()
    local entries = collect_entries({
      {
        uri = "file:///tmp/日本/語.lua",
        range = { start = { line = 0, character = 3 }, ["end"] = { line = 0, character = 3 } },
        text = "関数",
        provider = "test",
      },
    })

    local display, highlights = entries[1].display()
    assert.equals("関数 - /tmp/日本/語.lua:1:4", display)
    assert.same(
      { "関数", " - ", "/tmp/日本/", "語.lua", ":", "1", ":", "4" },
      highlighted_texts(display, highlights)
    )
    assert.equals(#display, highlights[#highlights][1][2])
  end)
end)
