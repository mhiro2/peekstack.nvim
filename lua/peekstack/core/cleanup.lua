local config = require("peekstack.config")
local stack = require("peekstack.core.stack")
local timer_util = require("peekstack.util.timer")

local M = {}

---@type uv.uv_timer_t?
local timer = nil

---Scan all stacks for stale popups and close them
---@param now_ms integer
function M.scan(now_ms)
  local cfg = config.get()
  local auto_close = cfg.ui.popup.auto_close
  if not auto_close or not auto_close.enabled then
    return
  end

  now_ms = now_ms or vim.uv.now()
  local auto_close_cfg = {
    idle_ms = auto_close.idle_ms or 300000,
    ignore_pinned = auto_close.ignore_pinned ~= false,
  }

  -- Close stale popups
  stack.close_stale(now_ms, auto_close_cfg)

  -- Close popups with invalid origin buffers
  -- Collect targets first to avoid modifying the table during iteration
  local to_close = {}
  for root_winid, stk in pairs(stack._all_stacks()) do
    for _, item in ipairs(stk.popups) do
      if item.origin and item.origin.bufnr and not vim.api.nvim_buf_is_valid(item.origin.bufnr) then
        table.insert(to_close, { id = item.id, root = root_winid })
      end
    end
  end
  for _, entry in ipairs(to_close) do
    stack.close(entry.id, entry.root)
  end
end

---Start the cleanup timer
function M.start()
  local cfg = config.get()
  local auto_close = cfg.ui.popup.auto_close
  if not auto_close or not auto_close.enabled then
    return
  end

  local interval_ms = auto_close.check_interval_ms or 60000

  local store = timer_util.get_store()
  timer_util.close(store.cleanup)
  timer_util.close(timer)
  timer = vim.uv.new_timer()
  store.cleanup = timer

  timer:start(interval_ms, interval_ms, function()
    vim.schedule(function()
      M.scan()
    end)
  end)
end

---Stop the cleanup timer
function M.stop()
  local store = timer_util.get_store()
  timer_util.close(timer)
  if store.cleanup and store.cleanup ~= timer then
    timer_util.close(store.cleanup)
  end
  timer = nil
  store.cleanup = nil
end

return M
