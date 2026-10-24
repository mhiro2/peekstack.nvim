describe("peekstack.providers.grep", function()
  local grep = require("peekstack.providers.grep")
  local original_notify
  local original_system
  local original_input
  local original_executable
  local notifications

  before_each(function()
    original_notify = vim.notify
    original_system = vim.system
    original_input = vim.ui.input
    original_executable = vim.fn.executable
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
    vim.system = original_system
    vim.ui.input = original_input
    vim.fn.executable = original_executable
  end)

  ---Notifications emitted by peekstack itself. Neovim can deliver unrelated
  ---warnings (e.g. about its log file) through vim.notify at any time.
  ---@return { msg: string, level: integer }[]
  local function peekstack_notifications()
    local own = {}
    for _, item in ipairs(notifications) do
      if type(item.msg) == "string" and vim.startswith(item.msg, "[peekstack] ") then
        table.insert(own, item)
      end
    end
    return own
  end

  it("parses vimgrep output with Unix paths", function()
    local output = "/tmp/sample.lua:3:5:hello"
    local items = grep._parse_output(output, vim.fn.getcwd())

    assert.equals(1, #items)
    assert.equals("grep.search", items[1].provider)
    assert.equals(2, items[1].range.start.line)
    assert.equals(4, items[1].range.start.character)
    assert.equals("hello", items[1].text)
  end)

  it("parses vimgrep output with Windows drive paths using the host path rules", function()
    local output = "C:\\Users\\dev\\sample.lua:12:34:hit"
    local items = grep._parse_output(output, "/work/project")

    assert.equals(1, #items)
    assert.equals("grep.search", items[1].provider)
    assert.equals(11, items[1].range.start.line)
    assert.equals(33, items[1].range.start.character)
    assert.equals("hit", items[1].text)
    if vim.fn.has("win32") == 1 then
      -- An absolute drive path keeps its drive and directories.
      assert.equals(vim.uri_from_fname("C:/Users/dev/sample.lua"), items[1].uri)
    else
      -- Elsewhere a drive prefix is not absolute: the whole name, drive colon
      -- and backslashes included, is a file inside the search directory.
      assert.equals("file:///work/project/C:%5cUsers%5cdev%5csample.lua", items[1].uri)
    end
  end)

  it("prefers the actual file path when text also contains colon-separated numbers", function()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    local target = tmpdir .. "/sample:12:34.lua"
    vim.fn.writefile({ "first", "second", "third" }, target)

    local output = target .. ":2:6:match:9:8:payload"
    local items = grep._parse_output(output, vim.fn.getcwd())

    assert.equals(1, #items)
    assert.equals("grep.search", items[1].provider)
    assert.equals(1, items[1].range.start.line)
    assert.equals(5, items[1].range.start.character)
    assert.equals("match:9:8:payload", items[1].text)

    vim.fn.delete(tmpdir, "rf")
  end)

  it("formats ignore-file failures with a targeted hint", function()
    local message = grep._format_failure_message("error reading .gitignore: invalid UTF-8")

    assert.equals(
      "rg failed; check .gitignore/.ignore patterns or encoding: error reading .gitignore: invalid UTF-8",
      message
    )
  end)

  it("warns with the ignore hint when rg reports ignore file issues", function()
    local items = nil

    vim.ui.input = function(_, cb)
      cb("sample")
    end
    vim.fn.executable = function(_)
      return 1
    end
    vim.system = function(_, _, cb)
      cb({
        code = 2,
        stdout = "",
        stderr = "error reading .ignore: invalid UTF-8",
      })
    end

    grep.search({}, function(result)
      items = result
    end)

    vim.wait(100, function()
      return items ~= nil
    end)

    assert.same({}, items)
    assert.same({
      {
        msg = "[peekstack] rg failed; check .gitignore/.ignore patterns or encoding: error reading .ignore: invalid UTF-8",
        level = vim.log.levels.WARN,
      },
    }, peekstack_notifications())
  end)

  it("warns and returns no results without prompting when rg is missing", function()
    local prompted = false
    local ran = false
    local items = nil

    vim.fn.executable = function(name)
      assert.equals("rg", name)
      return 0
    end
    vim.ui.input = function()
      prompted = true
    end
    vim.system = function()
      ran = true
    end

    grep.search({}, function(result)
      items = result
    end)

    assert.same({}, items)
    assert.is_false(prompted)
    assert.is_false(ran)
    assert.same(
      { { msg = "[peekstack] rg not found in PATH", level = vim.log.levels.WARN } },
      peekstack_notifications()
    )
  end)

  it("returns no results without running rg when the prompt is cancelled or empty", function()
    vim.fn.executable = function(_)
      return 1
    end
    local ran = false
    vim.system = function()
      ran = true
    end

    -- A cancelled prompt answers nil; an accepted blank prompt answers "".
    for _, case in ipairs({ { answer = nil }, { answer = "" } }) do
      local items = nil
      vim.ui.input = function(opts, cb)
        assert.equals("rg > ", opts.prompt)
        cb(case.answer)
      end

      grep.search({}, function(result)
        items = result
      end)

      assert.same({}, items)
    end

    assert.is_false(ran)
    assert.same({}, peekstack_notifications())
  end)

  describe("working directory", function()
    -- Every Neovim cd path expands the "$HOME" in the directory names, so
    -- change the process directory directly like starting nvim there would.
    local cd = vim.uv.chdir

    local original_cwd
    local dir_a
    local dir_b

    before_each(function()
      original_cwd = vim.fn.getcwd()
      -- "$HOME" checks that the directory name is not expanded as a variable.
      local root = vim.fn.resolve(vim.fn.tempname())
      dir_a = root .. "/$HOME/a"
      dir_b = root .. "/b"
      vim.fn.mkdir(dir_a, "p")
      vim.fn.mkdir(dir_b, "p")
      vim.fn.writefile({ "needle" }, dir_a .. "/same.lua")
      vim.fn.writefile({ "needle" }, dir_b .. "/same.lua")
      vim.fn.executable = function(_)
        return 1
      end
    end)

    after_each(function()
      cd(original_cwd)
      vim.fn.delete(vim.fs.dirname(dir_b), "rf")
    end)

    local function run_search(on_input, on_system)
      local items = nil
      local system_opts = nil
      vim.ui.input = function(_, cb)
        on_input()
        cb("needle")
      end
      vim.system = function(_, opts, cb)
        system_opts = opts
        on_system()
        cb({ code = 0, stdout = "same.lua:1:1:needle\n", stderr = "" })
      end

      grep.search({}, function(result)
        items = result
      end)
      vim.wait(100, function()
        return items ~= nil
      end)
      return items, system_opts
    end

    it("keeps the directory the search started in when cwd changes during input", function()
      cd(dir_a)
      local items, system_opts = run_search(function()
        cd(dir_b)
      end, function() end)

      assert.equals(dir_a, system_opts.cwd)
      assert.equals(1, #items)
      assert.equals(vim.uri_from_fname(dir_a .. "/same.lua"), items[1].uri)
    end)

    it("resolves results against the search directory when cwd changes while rg runs", function()
      cd(dir_a)
      local items, system_opts = run_search(function() end, function()
        cd(dir_b)
      end)

      assert.equals(dir_a, system_opts.cwd)
      assert.equals(1, #items)
      assert.equals(vim.uri_from_fname(dir_a .. "/same.lua"), items[1].uri)
    end)
  end)
end)
