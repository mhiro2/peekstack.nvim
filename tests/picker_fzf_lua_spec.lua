describe("peekstack.picker.fzf_lua", function()
  local picker = require("peekstack.picker.fzf_lua")

  it("should select the correct item when labels collide", function()
    local original = package.loaded["fzf-lua"]
    local picked = nil
    local captured_opts = nil

    package.loaded["fzf-lua"] = {
      fzf_exec = function(source, opts)
        captured_opts = opts
        local lines = source()
        assert.is_true(lines[1]:match("^/tmp/same.lua:1:1\t") ~= nil)
        assert.is_true(lines[2]:match("^/tmp/same.lua:1:1\t") ~= nil)
        assert.is_true(lines[1]:match("\t1$") ~= nil)
        assert.is_true(lines[2]:match("\t2$") ~= nil)
        opts.actions["default"]({ lines[2] })
      end,
    }

    local loc1 = {
      uri = "file:///tmp/same.lua",
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }
    local loc2 = {
      uri = "file:///tmp/same.lua",
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }

    picker.pick({ loc1, loc2 }, nil, function(choice)
      picked = choice
    end)

    assert.are.same(loc2, picked)
    assert.equals("builtin", captured_opts.previewer)
    assert.equals("Peekstack> ", captured_opts.prompt)
    assert.equals("\t", captured_opts.fzf_opts["--delimiter"])
    assert.equals("2", captured_opts.fzf_opts["--with-nth"])
    assert.equals("2", captured_opts.fzf_opts["--nth"])

    package.loaded["fzf-lua"] = original
  end)
end)
