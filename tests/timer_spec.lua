local timer = require("peekstack.util.timer")

describe("peekstack.util.timer", function()
  it("is a no-op when handle is nil", function()
    timer.close(nil)
  end)

  it("closes handle when it is not closing", function()
    local stop_calls = 0
    local close_calls = 0
    local handle = {
      stop = function()
        stop_calls = stop_calls + 1
      end,
      is_closing = function()
        return false
      end,
      close = function()
        close_calls = close_calls + 1
      end,
    }

    timer.close(handle)

    assert.equals(1, stop_calls)
    assert.equals(1, close_calls)
  end)

  it("skips close when handle is already closing", function()
    local stop_calls = 0
    local close_calls = 0
    local handle = {
      stop = function()
        stop_calls = stop_calls + 1
      end,
      is_closing = function()
        return true
      end,
      close = function()
        close_calls = close_calls + 1
      end,
    }

    timer.close(handle)

    assert.equals(1, stop_calls)
    assert.equals(0, close_calls)
  end)

  it("still attempts close when is_closing check fails", function()
    local close_calls = 0
    local handle = {
      stop = function() end,
      is_closing = function()
        error("unsupported")
      end,
      close = function()
        close_calls = close_calls + 1
      end,
    }

    timer.close(handle)

    assert.equals(1, close_calls)
  end)
end)
