local config = require("peekstack.config")
local fs = require("peekstack.util.fs")
local orchestrator = require("peekstack.persist.orchestrator")
local persist = require("peekstack.persist")
local stack = require("peekstack.core.stack")
local timer_util = require("peekstack.util.timer")

local M = {}

---A stack together with the store file it is saved to. Both are fixed when
---the change is observed, so neither a `:cd` nor a window switch before the
---save runs can redirect it.
---@class PeekstackAutoSaveTarget
---@field root_winid integer
---@field store_path string

---@type uv.uv_timer_t?
local save_timer = nil
---Target whose debounced save has not run yet.
---@type PeekstackAutoSaveTarget?
local pending_target = nil
---The auto session mirrors a single stack: the one changed most recently.
---Kept apart from `pending_target` so the leave-time save still knows which
---stack to write after the debounced save has already run.
---@type PeekstackAutoSaveTarget?
local tracked_target = nil
---@type string?
local last_restored_repo = nil

---@return boolean
local function is_enabled()
  local cfg = config.get()
  if type(cfg.persist.auto) ~= "table" then
    return false
  end
  return cfg.persist.enabled and cfg.persist.auto.enabled or false
end

---@return string
local function resolve_session_name()
  local cfg = config.get()
  if type(cfg.persist.auto) == "table" and cfg.persist.auto.session_name then
    return cfg.persist.auto.session_name
  end
  return "auto"
end

---@return integer
local function resolve_root_winid()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if vim.bo[bufnr].filetype == "peekstack-stack" then
    local ok, root_winid = pcall(vim.api.nvim_win_get_var, winid, "peekstack_root_winid")
    if ok and type(root_winid) == "number" and vim.api.nvim_win_is_valid(root_winid) then
      return root_winid
    end
  end
  return winid
end

---Capture the stack to save and the store it belongs to.
---An explicit `root_winid` that no longer exists yields nil instead of falling
---back to the current window, which holds an unrelated stack.
---@param root_winid? integer
---@return PeekstackAutoSaveTarget?
local function capture_target(root_winid)
  if not fs.repo_root() then
    return nil
  end
  if root_winid == nil then
    root_winid = resolve_root_winid()
  elseif type(root_winid) ~= "number" or not vim.api.nvim_win_is_valid(root_winid) then
    return nil
  end
  return {
    root_winid = stack.get_root_winid(root_winid),
    store_path = orchestrator.store_path(),
  }
end

---@param a PeekstackAutoSaveTarget
---@param b PeekstackAutoSaveTarget
---@return boolean
local function same_target(a, b)
  return a.root_winid == b.root_winid and a.store_path == b.store_path
end

---@param target PeekstackAutoSaveTarget
---@param opts? { sync?: boolean }
---@return boolean
local function save_session(target, opts)
  if not is_enabled() then
    return false
  end
  -- Once the root window is gone its stack is too; saving now would collect
  -- the current window's stack and overwrite the session with it.
  if not vim.api.nvim_win_is_valid(target.root_winid) then
    return false
  end
  persist.save_current(resolve_session_name(), {
    root_winid = target.root_winid,
    store_path = target.store_path,
    silent = true,
    sync = opts and opts.sync or false,
  })
  return true
end

local function flush_pending()
  local target = pending_target
  pending_target = nil
  if target then
    save_session(target)
  end
end

---@return boolean
function M.maybe_restore()
  if not is_enabled() then
    return false
  end

  local cfg = config.get()
  if not cfg.persist.auto.restore then
    return false
  end

  local repo_root = fs.repo_root()
  if not repo_root then
    return false
  end

  if last_restored_repo == repo_root then
    return false
  end

  if cfg.persist.auto.restore_if_empty then
    local root_winid = resolve_root_winid()
    if #stack.list(root_winid) > 0 then
      return false
    end
  end

  last_restored_repo = repo_root
  persist.restore(resolve_session_name(), { silent = true })
  return true
end

---@param opts? { root_winid?: integer }
---@return boolean
function M.schedule_save(opts)
  if not is_enabled() then
    return false
  end

  local cfg = config.get()
  if not cfg.persist.auto.save then
    return false
  end

  local target = capture_target(opts and opts.root_winid or nil)
  if not target then
    return false
  end

  -- A debounced save for another stack or store must not be swallowed by
  -- this one: write it out now instead of letting the new target replace it.
  if pending_target and not same_target(pending_target, target) then
    if save_timer then
      save_timer:stop()
    end
    flush_pending()
  end
  pending_target = target
  tracked_target = target

  local debounce_ms = tonumber(cfg.persist.auto.debounce_ms) or 1000
  if save_timer then
    save_timer:stop()
  else
    save_timer = vim.uv.new_timer()
    timer_util.get_store().persist_auto = save_timer
  end

  save_timer:start(debounce_ms, 0, function()
    save_timer:stop()
    -- Bind to the target this timer debounced: a schedule_save() that runs
    -- before the scheduled callback replaces pending_target, and that newer
    -- target must wait for its own timer.
    local fired = pending_target
    vim.schedule(function()
      if fired and pending_target == fired then
        flush_pending()
      end
    end)
  end)

  return true
end

---Without an explicit `root_winid` this saves the stack auto save last
---tracked, not the current window's, which may be an unrelated split.
---Nothing is written when no stack changed during the session.
---@param opts? { root_winid?: integer }
---@return boolean
function M.save_on_leave(opts)
  if not is_enabled() then
    return false
  end

  local cfg = config.get()
  if not cfg.persist.auto.save_on_leave then
    return false
  end

  local target
  if opts and opts.root_winid then
    target = capture_target(opts.root_winid)
  else
    target = pending_target or tracked_target
  end
  pending_target = nil

  if save_timer then
    save_timer:stop()
  end

  if not target then
    return false
  end
  return save_session(target, { sync = true })
end

function M.setup()
  timer_util.close(save_timer)
  timer_util.get_store().persist_auto = nil
  save_timer = nil
  pending_target = nil
  tracked_target = nil

  local group = vim.api.nvim_create_augroup("PeekstackPersistAuto", { clear = true })

  if not is_enabled() then
    return
  end

  local cfg = config.get()

  if cfg.persist.auto.restore then
    vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
      group = group,
      callback = function()
        M.maybe_restore()
      end,
    })
  end

  if cfg.persist.auto.save then
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = { "PeekstackPush", "PeekstackClose", "PeekstackRestorePopup" },
      callback = function(args)
        local root_winid = args.data and args.data.root_winid or nil
        M.schedule_save({ root_winid = root_winid })
      end,
    })
  end

  if cfg.persist.auto.save_on_leave then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        M.save_on_leave()
      end,
    })
  end
end

---Reset internal state (for testing).
function M._reset()
  last_restored_repo = nil
  pending_target = nil
  tracked_target = nil
  timer_util.close(save_timer)
  timer_util.get_store().persist_auto = nil
  save_timer = nil
end

return M
