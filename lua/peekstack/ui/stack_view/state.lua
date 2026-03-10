local M = {}

---@type table<integer, PeekstackStackViewState>
local states = {}
---@type integer?
local tab_cleanup_group = nil

---@return PeekstackStackViewState
local function new_state()
  return {
    bufnr = nil,
    winid = nil,
    root_winid = nil,
    line_to_id = {},
    render_keys = {},
    filter = nil,
    header_lines = 0,
    help_bufnr = nil,
    help_winid = nil,
    help_augroup = nil,
    autoclose_group = nil,
    autoclose_suspended = 0,
    preview_ts_cache = {},
  }
end

---@param s PeekstackStackViewState
function M.cleanup(s)
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

---@param s PeekstackStackViewState
function M.reset_open_state(s)
  s.bufnr = nil
  s.winid = nil
  s.root_winid = nil
  s.line_to_id = {}
  s.render_keys = {}
  s.header_lines = 0
  s.help_bufnr = nil
  s.help_winid = nil
  s.help_augroup = nil
  s.autoclose_group = nil
  s.autoclose_suspended = 0
  s.preview_ts_cache = {}
end

local function cleanup_invalid_states()
  for tabpage, s in pairs(states) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      M.cleanup(s)
      states[tabpage] = nil
    end
  end
end

function M.setup()
  if tab_cleanup_group then
    return
  end

  tab_cleanup_group = vim.api.nvim_create_augroup("PeekstackStackViewTabCleanup", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = tab_cleanup_group,
    callback = cleanup_invalid_states,
  })
end

---@return PeekstackStackViewState
function M.current()
  local tabpage = vim.api.nvim_get_current_tabpage()
  if not states[tabpage] then
    states[tabpage] = new_state()
  end
  return states[tabpage]
end

---@return table<integer, PeekstackStackViewState>
function M.all()
  return states
end

---@return integer
function M.count()
  local count = 0
  for _ in pairs(states) do
    count = count + 1
  end
  return count
end

return M
