local config = require("peekstack.config")
local state = require("peekstack.ui.stack_view.state")

local M = {}

---@class PeekstackStackViewWindowDeps
---@field before_close fun(opts?: { refocus: boolean })
---@field ensure_non_header_cursor fun()

---@param s PeekstackStackViewState
---@return boolean
function M.is_open(s)
  return s.winid ~= nil and vim.api.nvim_win_is_valid(s.winid)
end

---@param s PeekstackStackViewState
---@return boolean
function M.is_ready(s)
  return s.bufnr ~= nil and s.winid ~= nil and vim.api.nvim_buf_is_valid(s.bufnr) and vim.api.nvim_win_is_valid(s.winid)
end

---@param s PeekstackStackViewState
function M.focus(s)
  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    vim.api.nvim_set_current_win(s.winid)
  end
end

---@param s PeekstackStackViewState
---@return boolean
function M.should_autoclose(s)
  if s.autoclose_suspended and s.autoclose_suspended > 0 then
    return false
  end
  if not M.is_open(s) then
    return false
  end

  local current = vim.api.nvim_get_current_win()
  if s.winid and current == s.winid then
    return false
  end
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) and current == s.help_winid then
    return false
  end

  return true
end

---@return integer
function M.find_root_winid()
  return require("peekstack.core.stack").get_root_winid(vim.api.nvim_get_current_win())
end

---@return integer
local function editor_lines()
  return math.max(vim.o.lines - vim.o.cmdheight, 1)
end

---@return PeekstackRenderWinOpts
function M.win_config()
  local columns = vim.o.columns
  local lines = editor_lines()
  local position = config.get().ui.stack_view.position or "right"

  local width = math.max(30, math.floor(columns * 0.3))
  width = math.min(width, columns)

  local height = math.max(6, lines - 2)
  height = math.min(height, lines)

  local row = 0
  local col = math.max(columns - width, 0)

  if position == "left" then
    col = 0
  elseif position == "bottom" then
    width = columns
    height = math.max(6, math.floor(lines * 0.3))
    height = math.min(height, lines)
    row = math.max(lines - height, 0)
    col = 0
  end

  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = 100,
    title = "Stack View",
    title_pos = "center",
  }
end

---@param s PeekstackStackViewState
---@param deps PeekstackStackViewWindowDeps
function M.open(s, deps)
  s.autoclose_suspended = 0
  s.root_winid = M.find_root_winid()
  s.bufnr = vim.api.nvim_create_buf(false, true)
  s.winid = vim.api.nvim_open_win(s.bufnr, true, M.win_config())
  s.render_keys = {}

  vim.wo[s.winid].cursorline = true
  vim.wo[s.winid].winhighlight = "CursorLine:PeekstackStackViewCursorLine"
  vim.api.nvim_win_set_var(s.winid, "peekstack_root_winid", s.root_winid)
  require("peekstack.core.stack")._register_stack_view_win(s.winid)

  local fs = require("peekstack.util.fs")
  fs.configure_buffer(s.bufnr)
  vim.bo[s.bufnr].modifiable = false
  vim.bo[s.bufnr].filetype = "peekstack-stack"

  local group_name = string.format("PeekstackStackViewAutoClose:%d", s.bufnr)
  local au_group = vim.api.nvim_create_augroup(group_name, { clear = true })
  s.autoclose_group = au_group

  vim.api.nvim_create_autocmd("WinLeave", {
    group = au_group,
    buffer = s.bufnr,
    callback = function()
      vim.schedule(function()
        if not M.should_autoclose(s) then
          return
        end
        deps.before_close({ refocus = false })
        M.close(s)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = au_group,
    buffer = s.bufnr,
    callback = deps.ensure_non_header_cursor,
  })
end

---@param s PeekstackStackViewState
function M.close(s)
  if s.autoclose_group then
    pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
  end
  s.autoclose_group = nil

  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    pcall(vim.api.nvim_win_close, s.winid, true)
  end

  state.reset_open_state(s)
end

---@param s PeekstackStackViewState
function M.resize(s)
  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    pcall(vim.api.nvim_win_set_config, s.winid, M.win_config())
  end
end

return M
