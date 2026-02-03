describe("peekstack.picker.fzf_lua", function()
  local picker = require("peekstack.picker.fzf_lua")

  it("should select the correct item when labels collide", function()
    local original = package.loaded["fzf-lua"]
    local picked = nil

    package.loaded["fzf-lua"] = {
      fzf_exec = function(source, opts)
        local lines = source()
        assert.is_true(lines[1]:match("^1\t") ~= nil)
        assert.is_true(lines[2]:match("^2\t") ~= nil)
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

    package.loaded["fzf-lua"] = original
  end)
end)
