describe("peekstack.providers.grep", function()
  local grep = require("peekstack.providers.grep")

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
end)
