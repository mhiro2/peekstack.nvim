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

  it("parses vimgrep output with Unix paths", function()
    local output = "/tmp/sample.lua:3:5:hello"
    local items = grep._parse_output(output)

    assert.equals(1, #items)
    assert.equals("grep.search", items[1].provider)
    assert.equals(2, items[1].range.start.line)
    assert.equals(4, items[1].range.start.character)
    assert.equals("hello", items[1].text)
  end)

  it("parses vimgrep output with Windows drive paths", function()
    local output = "C:\\Users\\dev\\sample.lua:12:34:hit"
    local items = grep._parse_output(output)

    assert.equals(1, #items)
    assert.equals("grep.search", items[1].provider)
    assert.equals(11, items[1].range.start.line)
    assert.equals(33, items[1].range.start.character)
    assert.equals("hit", items[1].text)
    assert.is_true(items[1].uri:find("sample.lua", 1, true) ~= nil)
  end)

  it("prefers the actual file path when text also contains colon-separated numbers", function()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    local target = tmpdir .. "/sample:12:34.lua"
    vim.fn.writefile({ "first", "second", "third" }, target)

    local output = target .. ":2:6:match:9:8:payload"
    local items = grep._parse_output(output)

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

    assert.equals(0, #items)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.WARN, notifications[1].level)
    assert.is_true(notifications[1].msg:find("check .gitignore/.ignore patterns or encoding", 1, true) ~= nil)
  end)
end)
