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
      require("peekstack.ui.stack_view").resize_all()
    end)
  end)
end

---Close ephemeral popups that belong to the current root window.
local function close_ephemeral_popups()
  stack.close_ephemerals(vim.api.nvim_get_current_win())
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
  local keymaps = require("peekstack.ui.keymaps")

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

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      stack.handle_buf_win_enter(vim.api.nvim_get_current_win(), args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = debounced_reflow,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      keymaps.activate_source_popup(winid)
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

  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      keymaps.deactivate_source_popup(vim.api.nvim_get_current_win())
    end,
  })

  -- Registered globally rather than per popup buffer: the first WinEnter
  -- of a popup fires before the popup is registered, so a per-buffer hook
  -- installed there would miss every popup that is never re-entered.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      if vim.w[winid].peekstack_popup_id ~= nil then
        stack.touch(winid)
      end
    end,
  })

  local current_winid = vim.api.nvim_get_current_win()
  if vim.w[current_winid].peekstack_popup_id ~= nil then
    keymaps.activate_source_popup(current_winid)
  end

  local cfg = config.get()
  local close_events = cfg.ui.quick_peek and cfg.ui.quick_peek.close_events
    or { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" }

  -- Merge all close events into a single autocmd for efficiency
  vim.api.nvim_create_autocmd(close_events, {
    group = group,
    callback = close_ephemeral_popups,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "PeekstackPush", "PeekstackClose" },
    callback = function()
      require("peekstack.ui.stack_view").refresh_all()
    end,
  })

  local cleanup = require("peekstack.core.cleanup")
  cleanup.stop()
  if cfg.ui.popup.auto_close and cfg.ui.popup.auto_close.enabled then
    cleanup.start()
  end
end

return M
