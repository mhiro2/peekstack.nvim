describe("peekstack.picker.snacks", function()
  local picker = require("peekstack.picker.snacks")
  local original_snacks = nil
  local original_notify = nil

  before_each(function()
    original_snacks = package.loaded["snacks.picker"]
    original_notify = vim.notify
  end)

  after_each(function()
    package.loaded["snacks.picker"] = original_snacks
    vim.notify = original_notify
  end)

  it("warns when snacks.nvim is not available", function()
    package.loaded["snacks.picker"] = nil
    local warned = false
    vim.notify = function(msg)
      if msg == "snacks.nvim not available" then
        warned = true
      end
    end

    picker.pick({}, nil, function() end)

    assert.is_true(warned)
  end)

  it("passes file format items and confirms selected location", function()
    local picked = nil
    local closed = false
    local captured = nil
    package.loaded["snacks.picker"] = {
      pick = function(opts)
        captured = opts
        opts.confirm({
          close = function()
            closed = true
          end,
        }, opts.items[2])
      end,
    }

    local loc1 = {
      uri = "file:///tmp/a.lua",
      range = { start = { line = 3, character = 4 }, ["end"] = { line = 3, character = 4 } },
      provider = "test",
    }
    local loc2 = {
      uri = "file:///tmp/b.lua",
      range = { start = { line = 7, character = 2 }, ["end"] = { line = 7, character = 2 } },
      provider = "test",
    }

    picker.pick({ loc1, loc2 }, nil, function(choice)
      picked = choice
    end)

    assert.equals("Peekstack", captured.title)
    assert.equals("file", captured.format)
    assert.equals("/tmp/a.lua", captured.items[1].file)
    assert.equals(4, captured.items[1].row)
    assert.equals(5, captured.items[1].col)
    assert.same({ 4, 5 }, captured.items[1].pos)
    assert.are.same(loc2, picked)
    assert.is_true(closed)
  end)
end)
