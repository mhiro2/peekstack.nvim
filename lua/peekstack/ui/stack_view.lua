local config = require("peekstack.config")
local location = require("peekstack.core.location")
local str = require("peekstack.util.str")

local M = {}

local NS = vim.api.nvim_create_namespace("PeekstackStackView")

---@class PeekstackStackViewState
---@field bufnr integer?
---@field winid integer?
---@field root_winid integer?
---@field line_to_id table<integer, integer>
---@field filter string?
---@field header_lines integer
---@field help_bufnr integer?
---@field help_winid integer?
---@field help_augroup integer?
---@field autoclose_group integer?
---@field autoclose_suspended integer

---@type table<integer, PeekstackStackViewState>
local states = {}

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

do
  local group = vim.api.nvim_create_augroup("PeekstackStackViewTabCleanup", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
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

---@param s table
---@return boolean
local function is_ready(s)
  return s.bufnr ~= nil and s.winid ~= nil and vim.api.nvim_buf_is_valid(s.bufnr) and vim.api.nvim_win_is_valid(s.winid)
end

---@param s table
local function focus_stack_view(s)
  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    vim.api.nvim_set_current_win(s.winid)
  end
end

---@param s table
local function suspend_autoclose(s)
  s.autoclose_suspended = (s.autoclose_suspended or 0) + 1
end

---@param s table
local function resume_autoclose(s)
  if s.autoclose_suspended then
    s.autoclose_suspended = math.max(s.autoclose_suspended - 1, 0)
  end
end

---@param s table
local function focus_root_win(s)
  if s.root_winid and vim.api.nvim_win_is_valid(s.root_winid) then
    vim.api.nvim_set_current_win(s.root_winid)
  end
end

---@param s table
local function refocus_and_resume(s)
  focus_stack_view(s)
  resume_autoclose(s)
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

---@param s table
---@param opts? { refocus: boolean }
local function close_help(s, opts)
  local had_help = s.help_winid and vim.api.nvim_win_is_valid(s.help_winid)
  local refocus = true
  if opts and opts.refocus == false then
    refocus = false
  end
  if had_help then
    vim.api.nvim_win_close(s.help_winid, true)
  end
  s.help_winid = nil
  s.help_bufnr = nil
  if s.help_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, s.help_augroup)
    s.help_augroup = nil
  end
  if had_help then
    if refocus then
      focus_stack_view(s)
    end
    resume_autoclose(s)
  end
end

---@param label string
---@param filter? string
---@return boolean
local function matches_filter(label, filter)
  if not filter or filter == "" then
    return true
  end
  return label:lower():find(filter:lower(), 1, true) ~= nil
end

---@class PeekstackStackViewHighlight
---@field col_start integer
---@field col_end integer
---@field hl_group string

---Render the stack view list
---@param s table
local function render(s)
  if not is_ready(s) then
    return
  end
  local stack = require("peekstack.core.stack")
  local items = stack.list(s.root_winid)
  local ui_path = config.get().ui.path or {}
  local win_width = vim.api.nvim_win_get_width(s.winid)
  if win_width <= 0 then
    win_width = vim.o.columns
  end
  local lines = {}
  ---@type PeekstackStackViewHighlight[][]
  local highlights = {}
  s.line_to_id = {}
  s.header_lines = 0

  local visible = {}
  for _, popup in ipairs(items) do
    local filter_label = popup.title
      or location.display_text(popup.location, 0, {
        path_base = ui_path.base,
      })
    if matches_filter(filter_label, s.filter) then
      table.insert(visible, popup)
    end
  end

  if s.filter and s.filter ~= "" then
    local header = string.format("Filter: %s (%d/%d)", s.filter, #visible, #items)
    table.insert(lines, header)
    table.insert(highlights, { { col_start = 0, col_end = #header, hl_group = "PeekstackStackViewFilter" } })
    s.header_lines = 1
    if #visible == 0 then
      table.insert(lines, "No matches")
      table.insert(highlights, {})
    end
  end

  for idx, popup in ipairs(visible) do
    local pinned = popup.pinned and "[p] " or ""
    local index_str = string.format("%d. ", idx)
    local prefix = index_str .. pinned
    local max_label_width = math.max(win_width - vim.fn.strdisplaywidth(prefix), 0)
    if ui_path.max_width and ui_path.max_width > 0 then
      max_label_width = math.min(max_label_width, ui_path.max_width)
    end
    local label = popup.title and str.truncate_middle(popup.title, max_label_width)
      or location.display_text(popup.location, 0, {
        path_base = ui_path.base,
        max_width = max_label_width,
      })
    local line = prefix .. label
    table.insert(lines, line)

    local line_hls = {}
    -- Index number highlight
    table.insert(line_hls, { col_start = 0, col_end = #index_str, hl_group = "PeekstackStackViewIndex" })
    -- Pinned badge highlight
    if popup.pinned then
      table.insert(line_hls, {
        col_start = #index_str,
        col_end = #index_str + #pinned,
        hl_group = "PeekstackStackViewPinned",
      })
    end
    -- Provider highlight (if label contains " · ")
    local label_start = #index_str + #pinned
    local sep = label:find(" · ", 1, true)
    if sep then
      table.insert(line_hls, {
        col_start = label_start,
        col_end = label_start + sep - 1,
        hl_group = "PeekstackStackViewProvider",
      })
      table.insert(line_hls, {
        col_start = label_start + sep + 4,
        col_end = #line,
        hl_group = "PeekstackStackViewPath",
      })
    end
    table.insert(highlights, line_hls)

    s.line_to_id[idx + s.header_lines] = popup.id
  end
  if #lines == 0 then
    table.insert(lines, "No stack entries")
    table.insert(highlights, {})
  end

  vim.bo[s.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(s.bufnr, 0, -1, false, lines)
  vim.bo[s.bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(s.bufnr, NS, 0, -1)
  for line_idx, line_hls in ipairs(highlights) do
    for _, hl in ipairs(line_hls) do
      vim.api.nvim_buf_set_extmark(s.bufnr, NS, line_idx - 1, hl.col_start, {
        end_col = hl.col_end,
        hl_group = hl.hl_group,
      })
    end
  end
end

---@param s table
---@param id integer
local function move_cursor_to_id(s, id)
  if not s.winid or not vim.api.nvim_win_is_valid(s.winid) then
    return
  end
  for line, entry_id in pairs(s.line_to_id) do
    if entry_id == id then
      vim.api.nvim_win_set_cursor(s.winid, { line, 0 })
      return
    end
  end
end

---@param s table
local function toggle_help(s)
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) then
    close_help(s)
    return
  end
  suspend_autoclose(s)
  local lines = {
    "Peekstack Stack View",
    "",
    "<CR>  Focus selected popup",
    "dd    Close selected popup",
    "u     Undo close (restore last)",
    "U     Restore all closed popups",
    "H     History list (select to restore)",
    "r     Rename selected popup",
    "p     Toggle pin (skip auto-close)",
    "/     Filter list",
    "J/K   Move item down/up",
    "q     Close stack view",
    "?     Toggle this help",
  }
  s.help_bufnr = vim.api.nvim_create_buf(false, true)
  local fs = require("peekstack.util.fs")
  fs.configure_buffer(s.help_bufnr)
  vim.bo[s.help_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(s.help_bufnr, 0, -1, false, lines)
  vim.bo[s.help_bufnr].modifiable = false
  vim.bo[s.help_bufnr].filetype = "peekstack-stack-help"

  local win_width = vim.api.nvim_win_get_width(s.winid)
  local win_height = vim.api.nvim_win_get_height(s.winid)
  local max_len = 0
  for _, line in ipairs(lines) do
    if #line > max_len then
      max_len = #line
    end
  end
  local width = math.min(max_len + 2, math.max(20, win_width - 4))
  local height = math.min(#lines, math.max(4, win_height - 4))
  local row = math.max(1, math.floor((win_height - height) / 2))
  local col = math.max(1, math.floor((win_width - width) / 2))
  local parent_cfg = vim.api.nvim_win_get_config(s.winid)
  local base_z = 100
  if type(parent_cfg.zindex) == "number" then
    base_z = parent_cfg.zindex
  end
  s.help_winid = vim.api.nvim_open_win(s.help_bufnr, true, {
    relative = "win",
    win = s.winid,
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = base_z + 1,
  })
  local help_group =
    vim.api.nvim_create_augroup(string.format("PeekstackStackViewHelp_%d", vim.api.nvim_get_current_tabpage()), {
      clear = true,
    })
  s.help_augroup = help_group
  vim.api.nvim_create_autocmd("WinLeave", {
    group = help_group,
    buffer = s.help_bufnr,
    callback = function()
      vim.schedule(function()
        if not (s.help_winid and vim.api.nvim_win_is_valid(s.help_winid)) then
          return
        end
        close_help(s, { refocus = false })
        if is_open(s) and vim.api.nvim_get_current_win() ~= s.winid then
          M.toggle()
        end
      end)
    end,
  })
  vim.keymap.set("n", "q", function()
    close_help(s)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    close_help(s)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "?", function()
    close_help(s)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
end

---@param s table
local function apply_keymaps(s)
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if id then
      local stack = require("peekstack.core.stack")
      stack.focus_by_id(id, s.root_winid)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "dd", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if id then
      local stack = require("peekstack.core.stack")
      stack.close_by_id(id, s.root_winid)
      render(s)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "u", function()
    suspend_autoclose(s)
    local stack = require("peekstack.core.stack")
    focus_root_win(s)
    local restored = stack.restore_last(s.root_winid)
    if restored then
      render(s)
    else
      if #stack.history_list(s.root_winid) > 0 then
        vim.notify("Failed to restore popup", vim.log.levels.WARN)
      else
        vim.notify("No closed popups to restore", vim.log.levels.INFO)
      end
    end
    refocus_and_resume(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "r", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if not id then
      return
    end
    suspend_autoclose(s)
    vim.ui.input({ prompt = "Rename" }, function(input)
      if not input or input == "" then
        refocus_and_resume(s)
        return
      end
      local stack = require("peekstack.core.stack")
      stack.rename_by_id(id, input, s.root_winid)
      render(s)
      refocus_and_resume(s)
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "p", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if not id then
      return
    end
    local stack = require("peekstack.core.stack")
    stack.toggle_pin_by_id(id, s.root_winid)
    render(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "/", function()
    suspend_autoclose(s)
    vim.ui.input({ prompt = "Filter" }, function(input)
      if input == nil then
        refocus_and_resume(s)
        return
      end
      if input == "" then
        s.filter = nil
      else
        s.filter = input
      end
      render(s)
      refocus_and_resume(s)
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "J", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    local stack = require("peekstack.core.stack")
    if id and stack.move_by_id(id, 1, s.root_winid) then
      render(s)
      move_cursor_to_id(s, id)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "K", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    local stack = require("peekstack.core.stack")
    if id and stack.move_by_id(id, -1, s.root_winid) then
      render(s)
      move_cursor_to_id(s, id)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "U", function()
    suspend_autoclose(s)
    local stack = require("peekstack.core.stack")
    focus_root_win(s)
    local restored = stack.restore_all(s.root_winid)
    if #restored > 0 then
      render(s)
    end
    local remaining = stack.history_list(s.root_winid)
    if #remaining > 0 then
      vim.notify("Some popups could not be restored", vim.log.levels.WARN)
    elseif #restored == 0 then
      vim.notify("No closed popups to restore", vim.log.levels.INFO)
    end
    refocus_and_resume(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "H", function()
    local stack = require("peekstack.core.stack")
    local history = stack.history_list(s.root_winid)
    if #history == 0 then
      vim.notify("No history entries", vim.log.levels.INFO)
      return
    end
    suspend_autoclose(s)
    local ui_path = config.get().ui.path or {}
    local max_width = ui_path.max_width or 0
    if max_width == 0 then
      max_width = math.floor(vim.o.columns * 0.7)
    end
    local items = {}
    for i = #history, 1, -1 do
      local entry = history[i]
      local label = entry.title and str.truncate_middle(entry.title, max_width)
        or location.display_text(entry.location, 0, {
          path_base = ui_path.base,
          max_width = max_width,
        })
      table.insert(items, { idx = i, label = label, entry = entry })
    end
    vim.ui.select(items, {
      prompt = "History",
      format_item = function(item)
        return item.label
      end,
    }, function(selected, idx)
      if selected or idx then
        local restore_idx = nil
        if type(selected) == "table" and selected.idx then
          restore_idx = selected.idx
        elseif type(idx) == "number" and items[idx] then
          restore_idx = items[idx].idx
        elseif type(selected) == "string" then
          for _, item in ipairs(items) do
            if item.label == selected then
              restore_idx = item.idx
              break
            end
          end
        end
        if restore_idx then
          focus_root_win(s)
          local restored = stack.restore_from_history(restore_idx, s.root_winid)
          if restored then
            render(s)
          else
            vim.notify("Failed to restore history entry", vim.log.levels.WARN)
          end
        else
          vim.notify("Failed to restore history entry", vim.log.levels.WARN)
        end
      end
      refocus_and_resume(s)
      if not selected then
        return
      end
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "?", function()
    toggle_help(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "q", function()
    M.toggle()
  end, { buffer = s.bufnr, nowait = true, silent = true })
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

---Compute floating window config for the stack view (right-side panel).
---@return table
local function stack_view_win_config()
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local width = math.max(30, math.floor(columns * 0.3))
  local height = math.max(6, lines - 2)
  return {
    relative = "editor",
    row = 0,
    col = columns - width,
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

---Open the stack view
function M.open()
  local s = get_state()
  if is_open(s) then
    vim.api.nvim_set_current_win(s.winid)
    render(s)
    return
  end

  s.autoclose_suspended = 0
  s.root_winid = find_root_winid()
  s.bufnr = vim.api.nvim_create_buf(false, true)
  s.winid = vim.api.nvim_open_win(s.bufnr, true, stack_view_win_config())
  vim.api.nvim_win_set_var(s.winid, "peekstack_root_winid", s.root_winid)
  require("peekstack.core.stack")._register_stack_view_win(s.winid)

  local fs = require("peekstack.util.fs")
  fs.configure_buffer(s.bufnr)
  vim.bo[s.bufnr].modifiable = false
  vim.bo[s.bufnr].filetype = "peekstack-stack"

  -- Auto-close when focus leaves the stack view window
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
        close_help(s)
        vim.api.nvim_win_close(s.winid, true)
        s.winid = nil
        s.bufnr = nil
        s.root_winid = nil
        s.autoclose_suspended = 0
        s.help_augroup = nil
        if s.autoclose_group then
          pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
        end
        s.autoclose_group = nil
      end)
    end,
  })

  apply_keymaps(s)
  render(s)
end

---Toggle the stack view (open if closed, close if open)
function M.toggle()
  local s = get_state()
  if is_open(s) then
    close_help(s)
    if s.autoclose_group then
      pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
    end
    s.autoclose_group = nil
    vim.api.nvim_win_close(s.winid, true)
    s.winid = nil
    s.bufnr = nil
    s.root_winid = nil
    s.autoclose_suspended = 0
    s.help_augroup = nil
    return
  end
  M.open()
end

---Re-render all open stack views (called on push/close events).
function M.refresh_all()
  for _, s in pairs(states) do
    if is_open(s) and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
      render(s)
    end
  end
end

---Get stack view state (for testing).
---@return table
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
---@param s table
function M._render(s)
  render(s)
end

return M
