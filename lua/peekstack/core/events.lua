local config = require("peekstack.config")
local stack = require("peekstack.core.stack")
local timer_util = require("peekstack.util.timer")

local M = {}

---@type uv.uv_timer_t?
local reflow_timer = nil
local REFLOW_DEBOUNCE_MS = 80

local function reset_reflow_timer()
  local store = timer_util.get_store()
  timer_util.close(store.reflow)
  timer_util.close(reflow_timer)
  store.reflow = nil
  reflow_timer = nil
end

local function debounced_reflow()
  if reflow_timer then
    reflow_timer:stop()
  else
    reflow_timer = vim.uv.new_timer()
    timer_util.get_store().reflow = reflow_timer
  end
  reflow_timer:start(REFLOW_DEBOUNCE_MS, 0, function()
    reflow_timer:stop()
    vim.schedule(function()
      stack.reflow_all()
    end)
  end)
end

---Close all ephemeral popups across all stacks and reflow
local function close_ephemeral_popups()
  stack.close_ephemerals()
end

---Check if a window is a floating popup
---@param winid integer
---@return boolean
local function is_floating_window(winid)
  local win_cfg = vim.api.nvim_win_get_config(winid)
  return win_cfg.relative ~= ""
end

function M.setup()
  reset_reflow_timer()
  local group = vim.api.nvim_create_augroup("PeekstackEvents", { clear = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local winid = tonumber(args.match)
      if winid then
        stack.handle_win_closed(winid)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      stack.handle_buf_wipeout(args.buf)
      stack.handle_origin_wipeout(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = debounced_reflow,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      if vim.w[winid].peekstack_popup_id == nil then
        return
      end
      if is_floating_window(winid) then
        stack.touch(winid)
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      if is_floating_window(winid) then
        stack.touch(winid)
        local layout = require("peekstack.core.layout")
        local s, _ = stack.find_by_winid(winid)
        if s then
          layout.update_focus_zindex(s, winid)
        end
      end
    end,
  })

  local cfg = config.get()
  local close_events = cfg.ui.quick_peek and cfg.ui.quick_peek.close_events
    or { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" }

  for _, event in ipairs(close_events) do
    vim.api.nvim_create_autocmd(event, {
      group = group,
      callback = close_ephemeral_popups,
    })
  end

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "PeekstackPush", "PeekstackClose" },
    callback = function()
      require("peekstack.ui.stack_view").refresh_all()
    end,
  })

  if cfg.ui.popup.auto_close and cfg.ui.popup.auto_close.enabled then
    local cleanup = require("peekstack.core.cleanup")
    cleanup.start()
  end
end

return M
