local config = require("peekstack.config")
local picker_util = require("peekstack.util.picker")

describe("peekstack.util.picker", function()
  before_each(function()
    config.setup({
      ui = {
        path = {
          base = "absolute",
          max_width = 200,
        },
      },
    })
  end)

  it("builds symbol-first label when preview lines are enabled", function()
    local location = {
      uri = "file:///tmp/sample.lua",
      range = {
        start = { line = 2, character = 4 },
        ["end"] = { line = 2, character = 4 },
      },
      text = "MyFunc\nDetail\tInfo",
      provider = "test",
    }

    local items = picker_util.build_external_items({ location }, 1)
    assert.equals("MyFunc Detail Info - /tmp/sample.lua:3:5", items[1].label)
    assert.equals("MyFunc Detail Info", items[1].symbol)
    assert.equals("/tmp/sample.lua", items[1].path)
    assert.equals(3, items[1].display_lnum)
    assert.equals(5, items[1].display_col)
  end)

  it("falls back to path label when preview lines are disabled", function()
    local location = {
      uri = "file:///tmp/sample.lua",
      range = {
        start = { line = 4, character = 1 },
        ["end"] = { line = 4, character = 1 },
      },
      text = "Hidden",
      provider = "test",
    }

    local items = picker_util.build_items({ location }, 0)
    assert.equals("/tmp/sample.lua:5:2", items[1].label)
  end)

  it("falls back to path label when text is blank", function()
    local location = {
      uri = "file:///tmp/sample.lua",
      range = {
        start = { line = 7, character = 0 },
        ["end"] = { line = 7, character = 0 },
      },
      text = " \n\t ",
      provider = "test",
    }

    local items = picker_util.build_external_items({ location }, 1)
    assert.equals("/tmp/sample.lua:8:1", items[1].label)
    assert.equals("", items[1].symbol)
    assert.equals("/tmp/sample.lua", items[1].path)
    assert.equals(8, items[1].display_lnum)
    assert.equals(1, items[1].display_col)
  end)

  it("keeps r characters when normalizing text", function()
    local location = {
      uri = "file:///tmp/sample.lua",
      range = {
        start = { line = 9, character = 2 },
        ["end"] = { line = 9, character = 2 },
      },
      text = "errMsgFailedToStartServer",
      provider = "test",
    }

    local items = picker_util.build_external_items({ location }, 1)
    assert.equals("errMsgFailedToStartServer - /tmp/sample.lua:10:3", items[1].label)
  end)
end)
