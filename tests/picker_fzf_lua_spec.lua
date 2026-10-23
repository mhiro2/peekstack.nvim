describe("peekstack.picker.fzf_lua", function()
  local picker = require("peekstack.picker.fzf_lua")
  local original_fzf = nil
  local had_fzf = false
  local exec_calls = nil

  ---Collect candidate lines the way fzf-lua consumes `fzf_exec` contents:
  ---a table of strings is streamed as-is, and a function receives a write
  ---callback that must be called once per line and with no argument at EOF.
  ---@param contents any
  ---@return string[]
  local function read_contents(contents)
    if type(contents) == "table" then
      for _, line in ipairs(contents) do
        assert(type(line) == "string", "fzf_exec table contents must be strings")
      end
      return contents
    end
    assert(type(contents) == "function", "fzf_exec contents must be a table or a function")
    local lines = {}
    local finished = false
    local function fzf_cb(line)
      assert(not finished, "fzf_cb called after EOF")
      if line == nil then
        finished = true
        return
      end
      lines[#lines + 1] = tostring(line)
    end
    -- The return value is ignored by fzf-lua.
    contents(fzf_cb, fzf_cb)
    assert(finished, "function contents never signalled EOF")
    return lines
  end

  before_each(function()
    had_fzf = package.loaded["fzf-lua"] ~= nil
    original_fzf = package.loaded["fzf-lua"]
    exec_calls = {}
    package.loaded["fzf-lua"] = {
      fzf_exec = function(contents, opts)
        exec_calls[#exec_calls + 1] = { lines = read_contents(contents), opts = opts }
      end,
    }
  end)

  after_each(function()
    if had_fzf then
      package.loaded["fzf-lua"] = original_fzf
    else
      package.loaded["fzf-lua"] = nil
    end
  end)

  ---@param path string
  ---@param line? integer
  ---@param text? string
  ---@return PeekstackLocation
  local function make_location(path, line, text)
    return {
      uri = "file://" .. path,
      range = { start = { line = line or 0, character = 0 }, ["end"] = { line = line or 0, character = 0 } },
      text = text,
      provider = "test",
    }
  end

  ---@param line string
  ---@return string[]
  local function split_fields(line)
    return vim.split(line, "\t", { plain = true })
  end

  it("feeds one candidate line per location and returns the selected location object", function()
    local loc1 = make_location("/tmp/same.lua")
    local loc2 = make_location("/tmp/same.lua")
    local picked = {}

    picker.pick({ loc1, loc2 }, nil, function(choice)
      picked[#picked + 1] = choice
    end)

    assert.equals(1, #exec_calls)
    local lines = exec_calls[1].lines
    local opts = exec_calls[1].opts
    assert.equals(2, #lines)
    assert.same({ "/tmp/same.lua:1:1", "/tmp/same.lua:1:1", "1" }, split_fields(lines[1]))
    assert.same({ "/tmp/same.lua:1:1", "/tmp/same.lua:1:1", "2" }, split_fields(lines[2]))

    -- Identical labels must still resolve to the exact location object picked.
    opts.actions["default"]({ lines[2] })
    opts.actions["default"]({ lines[1] })
    assert.equals(2, #picked)
    assert.equals(loc2, picked[1])
    assert.equals(loc1, picked[2])

    assert.equals("builtin", opts.previewer)
    assert.equals("Peekstack> ", opts.prompt)
    assert.equals("\t", opts.fzf_opts["--delimiter"])
    assert.equals("2", opts.fzf_opts["--with-nth"])
    assert.equals("2", opts.fzf_opts["--nth"])
  end)

  it("ignores empty selections", function()
    local calls = 0
    picker.pick({ make_location("/tmp/a.lua") }, nil, function()
      calls = calls + 1
    end)

    exec_calls[1].opts.actions["default"]({})
    exec_calls[1].opts.actions["default"](nil)
    assert.equals(0, calls)
  end)

  it("replaces control characters in the visible fields but keeps other characters", function()
    -- The file name decodes to a path containing a tab, CR and LF, plus several
    -- letters "r" that must survive sanitizing.
    local loc = make_location("/tmp/car%09rier/ro%0Dut%0Aer.lua", 2, "render")
    local picked = nil

    picker.pick({ loc }, nil, function(choice)
      picked = choice
    end)

    local lines = exec_calls[1].lines
    assert.equals(1, #lines)
    assert.is_nil(lines[1]:find("[\r\n]"))
    local fields = split_fields(lines[1])
    assert.same({
      "/tmp/car rier/ro ut er.lua:3:1",
      "render - /tmp/car rier/ro ut er.lua:3:1",
      "1",
    }, fields)

    exec_calls[1].opts.actions["default"]({ lines[1] })
    assert.equals(loc, picked)
  end)
end)
