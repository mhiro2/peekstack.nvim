local config = require("peekstack.config")
local fs = require("peekstack.util.fs")
local persist = require("peekstack.persist")
local stack = require("peekstack.core.stack")
local timer_util = require("peekstack.util.timer")

local M = {}

---@type uv.uv_timer_t?
local save_timer = nil
---@type integer?
local pending_root_winid = nil
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

---@param winid? integer
---@return integer?
local function normalize_root_winid(winid)
  if winid and type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
  return nil
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

---@param root_winid? integer
---@return boolean
local function save_session(root_winid)
  if not is_enabled() then
    return false
  end
  if not fs.repo_root() then
    return false
  end
  persist.save_current(resolve_session_name(), {
    scope = "repo",
    root_winid = normalize_root_winid(root_winid),
    silent = true,
  })
  return true
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
  persist.restore(resolve_session_name(), { scope = "repo", silent = true })
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

  if not fs.repo_root() then
    return false
  end

  local debounce_ms = tonumber(cfg.persist.auto.debounce_ms) or 1000
  local root_winid = normalize_root_winid(opts and opts.root_winid or nil)
  if root_winid then
    pending_root_winid = root_winid
  end

  if save_timer then
    save_timer:stop()
  else
    save_timer = vim.uv.new_timer()
    timer_util.get_store().persist_auto = save_timer
  end

  save_timer:start(debounce_ms, 0, function()
    save_timer:stop()
    local target_winid = pending_root_winid
    pending_root_winid = nil
    vim.schedule(function()
      save_session(target_winid)
    end)
  end)

  return true
end

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

  local root_winid = normalize_root_winid(opts and opts.root_winid or nil) or pending_root_winid
  pending_root_winid = nil

  if save_timer then
    save_timer:stop()
  end

  return save_session(root_winid)
end

function M.setup()
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
  pending_root_winid = nil
  timer_util.close(save_timer)
  timer_util.get_store().persist_auto = nil
  save_timer = nil
end

return M
