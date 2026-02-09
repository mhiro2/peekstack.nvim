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
    local mapped_confirm = nil

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
            spec.attach_mappings(nil, function(mode, key, fn)
              captured.mode = mode
              captured.key = key
              mapped_confirm = fn
            end)
            captured.selected = captured.finder.results[2]
            mapped_confirm(13)
          end,
        }
      end,
    }

    local loc1 = {
      uri = "file:///tmp/a.lua",
      range = { start = { line = 1, character = 2 }, ["end"] = { line = 1, character = 2 } },
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
    assert.equals("/tmp/a.lua", captured.finder.results[1].filename)
    assert.equals(2, captured.finder.results[1].lnum)
    assert.equals(3, captured.finder.results[1].col)
    assert.equals("i", captured.mode)
    assert.equals("<CR>", captured.key)
    assert.equals(13, captured.closed_bufnr)
    assert.are.same(loc2, picked)
  end)
end)
