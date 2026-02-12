local config = require("peekstack.config")
local keymaps = require("peekstack.ui.stack_view.keymaps")
local renderer = require("peekstack.ui.stack_view.render")

local M = {}

---@type table<integer, PeekstackStackViewState>
local states = {}
---@type integer?
local tab_cleanup_group = nil

---@param s PeekstackStackViewState
local function cleanup_state(s)
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) then
    pcall(vim.api.nvim_win_close, s.help_winid, true)
  end
  s.help_winid = nil
  s.help_bufnr = nil

  if s.help_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, s.help_augroup)
    s.help_augroup = nil
  end

  if s.autoclose_group then
    pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
    s.autoclose_group = nil
  end
end

local function cleanup_invalid_states()
  for tabpage, s in pairs(states) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      cleanup_state(s)
      states[tabpage] = nil
    end
  end
end

---Setup stack view autocmds.
function M.setup()
  if tab_cleanup_group then
    return
  end

  tab_cleanup_group = vim.api.nvim_create_augroup("PeekstackStackViewTabCleanup", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = tab_cleanup_group,
    callback = function()
      cleanup_invalid_states()
    end,
  })
end

---@return PeekstackStackViewState
local function get_state()
  local tabpage = vim.api.nvim_get_current_tabpage()
  if not states[tabpage] then
    states[tabpage] = {
      bufnr = nil,
      winid = nil,
      root_winid = nil,
      line_to_id = {},
      filter = nil,
      header_lines = 0,
      help_bufnr = nil,
      help_winid = nil,
      help_augroup = nil,
      autoclose_group = nil,
      autoclose_suspended = 0,
    }
  end
  return states[tabpage]
end

---@param s PeekstackStackViewState
---@return boolean
local function is_open(s)
  return s.winid ~= nil and vim.api.nvim_win_is_valid(s.winid)
end

---@param s PeekstackStackViewState
---@return boolean
local function is_ready(s)
  return s.bufnr ~= nil and s.winid ~= nil and vim.api.nvim_buf_is_valid(s.bufnr) and vim.api.nvim_win_is_valid(s.winid)
end

---@param s PeekstackStackViewState
local function focus_stack_view(s)
  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    vim.api.nvim_set_current_win(s.winid)
  end
end

---@param s PeekstackStackViewState
---@return boolean
local function should_autoclose(s)
  if s.autoclose_suspended and s.autoclose_suspended > 0 then
    return false
  end
  if not is_open(s) then
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

---@param s PeekstackStackViewState
local function render_state(s)
  renderer.render(s, is_ready)
end

---@return PeekstackStackViewKeymapDeps
local function keymap_deps()
  return {
    render = function(s)
      render_state(s)
    end,
    toggle = function()
      M.toggle()
    end,
    is_open = function(s)
      return is_open(s)
    end,
    focus_stack_view = function(s)
      focus_stack_view(s)
    end,
  }
end

---@param s PeekstackStackViewState
local function reset_open_state(s)
  if s.autoclose_group then
    pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
  end
  s.autoclose_group = nil

  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    pcall(vim.api.nvim_win_close, s.winid, true)
  end

  s.winid = nil
  s.bufnr = nil
  s.root_winid = nil
  s.autoclose_suspended = 0
  s.help_augroup = nil
end

---Find a non-floating window to use as root.
---@return integer
local function find_root_winid()
  local winid = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(winid)
  if cfg.relative == "" then
    return winid
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local c = vim.api.nvim_win_get_config(w)
    if c.relative == "" then
      return w
    end
  end
  return winid
end

---@return integer
local function editor_lines()
  return math.max(vim.o.lines - vim.o.cmdheight, 1)
end

---@return PeekstackRenderWinOpts
local function stack_view_win_config()
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

---Open the stack view.
function M.open()
  M.setup()

  local s = get_state()
  if is_open(s) then
    vim.api.nvim_set_current_win(s.winid)
    render_state(s)
    return
  end

  s.autoclose_suspended = 0
  s.root_winid = find_root_winid()
  s.bufnr = vim.api.nvim_create_buf(false, true)
  s.winid = vim.api.nvim_open_win(s.bufnr, true, stack_view_win_config())

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
        if not should_autoclose(s) then
          return
        end
        keymaps.close_help(s, nil, keymap_deps())
        reset_open_state(s)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = au_group,
    buffer = s.bufnr,
    callback = function()
      keymaps.ensure_non_header_cursor(s)
    end,
  })

  keymaps.apply(s, keymap_deps())
  render_state(s)
end

---Toggle the stack view (open if closed, close if open).
function M.toggle()
  local s = get_state()
  if is_open(s) then
    keymaps.close_help(s, nil, keymap_deps())
    reset_open_state(s)
    return
  end
  M.open()
end

---Re-render all open stack views (called on push/close events).
function M.refresh_all()
  for _, s in pairs(states) do
    if is_open(s) and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
      render_state(s)
    end
  end
end

---Get stack view state (for testing).
---@return PeekstackStackViewState
function M._get_state()
  return get_state()
end

---Get stack view state count (for testing).
---@return integer
function M._state_count()
  local count = 0
  for _ in pairs(states) do
    count = count + 1
  end
  return count
end

---Render stack view state (for testing).
---@param s PeekstackStackViewState
function M._render(s)
  render_state(s)
end

return M
