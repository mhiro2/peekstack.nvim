local config = require("peekstack.config")
local location = require("peekstack.core.location")
local str = require("peekstack.util.str")

local M = {}

---@class PeekstackStackViewKeymapDeps
---@field render fun(s: PeekstackStackViewState)
---@field toggle fun()
---@field is_open fun(s: PeekstackStackViewState): boolean
---@field focus_stack_view fun(s: PeekstackStackViewState)

---@param s PeekstackStackViewState
local function suspend_autoclose(s)
  s.autoclose_suspended = (s.autoclose_suspended or 0) + 1
end

---@param s PeekstackStackViewState
local function resume_autoclose(s)
  if s.autoclose_suspended then
    s.autoclose_suspended = math.max(s.autoclose_suspended - 1, 0)
  end
end

---@param s PeekstackStackViewState
local function focus_root_win(s)
  if s.root_winid and vim.api.nvim_win_is_valid(s.root_winid) then
    vim.api.nvim_set_current_win(s.root_winid)
  end
end

---@param s PeekstackStackViewState
---@param deps PeekstackStackViewKeymapDeps
local function refocus_and_resume(s, deps)
  deps.focus_stack_view(s)
  resume_autoclose(s)
end

---@param s PeekstackStackViewState
---@return integer[]
local function entry_lines(s)
  ---@type table<integer, integer>
  local id_to_line = {}
  for line, id in pairs(s.line_to_id or {}) do
    if line > (s.header_lines or 0) and (not id_to_line[id] or line < id_to_line[id]) then
      id_to_line[id] = line
    end
  end

  local lines = {}
  for _, line in pairs(id_to_line) do
    table.insert(lines, line)
  end
  table.sort(lines)
  return lines
end

---@param s PeekstackStackViewState
function M.ensure_non_header_cursor(s)
  if not (s.winid and vim.api.nvim_win_is_valid(s.winid) and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr)) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(s.bufnr)
  if line_count <= 0 then
    return
  end

  local min_line = math.min((s.header_lines or 0) + 1, line_count)
  local cursor = vim.api.nvim_win_get_cursor(s.winid)[1]
  if cursor < min_line then
    vim.api.nvim_win_set_cursor(s.winid, { min_line, 0 })
  end
end

---@param s PeekstackStackViewState
---@param step integer
local function move_cursor_by_stack_item(s, step)
  if not (s.winid and vim.api.nvim_win_is_valid(s.winid)) then
    return
  end

  local lines = entry_lines(s)
  if #lines == 0 then
    M.ensure_non_header_cursor(s)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(s.winid)[1]
  if cursor_line <= (s.header_lines or 0) then
    vim.api.nvim_win_set_cursor(s.winid, { lines[1], 0 })
    return
  end

  local current_id = s.line_to_id[cursor_line]
  local base_line = cursor_line
  if current_id then
    for line, id in pairs(s.line_to_id) do
      if id == current_id and line < base_line then
        base_line = line
      end
    end
  end

  local target_line = base_line
  if step > 0 then
    for _, line in ipairs(lines) do
      if line > base_line then
        target_line = line
        break
      end
    end
  else
    for idx = #lines, 1, -1 do
      local line = lines[idx]
      if line < base_line then
        target_line = line
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(s.winid, { target_line, 0 })
end

---@param lines string[]
---@return integer
local function max_display_width(lines)
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  return max_width
end

---@param s PeekstackStackViewState
---@param opts? { refocus: boolean }
---@param deps PeekstackStackViewKeymapDeps
function M.close_help(s, opts, deps)
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
      deps.focus_stack_view(s)
    end
    resume_autoclose(s)
  end
end

---@param s PeekstackStackViewState
---@param deps PeekstackStackViewKeymapDeps
local function toggle_help(s, deps)
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) then
    M.close_help(s, nil, deps)
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
    "gg/G  Jump to first/last stack item",
    "j/k   Move cursor by stack item",
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
  local width = math.min(max_display_width(lines) + 2, math.max(20, win_width - 4))
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
        M.close_help(s, { refocus = false }, deps)
        if deps.is_open(s) and vim.api.nvim_get_current_win() ~= s.winid then
          deps.toggle()
        end
      end)
    end,
  })

  vim.keymap.set("n", "q", function()
    M.close_help(s, nil, deps)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    M.close_help(s, nil, deps)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "?", function()
    M.close_help(s, nil, deps)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
end

---@param s PeekstackStackViewState
---@param deps PeekstackStackViewKeymapDeps
function M.apply(s, deps)
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
      deps.render(s)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "u", function()
    suspend_autoclose(s)
    local stack = require("peekstack.core.stack")
    focus_root_win(s)
    local restored = stack.restore_last(s.root_winid)
    if restored then
      deps.render(s)
    else
      if #stack.history_list(s.root_winid) > 0 then
        vim.notify("Failed to restore popup", vim.log.levels.WARN)
      else
        vim.notify("No closed popups to restore", vim.log.levels.INFO)
      end
    end
    refocus_and_resume(s, deps)
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
        refocus_and_resume(s, deps)
        return
      end
      local stack = require("peekstack.core.stack")
      stack.rename_by_id(id, input, s.root_winid)
      deps.render(s)
      refocus_and_resume(s, deps)
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
    deps.render(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "/", function()
    suspend_autoclose(s)
    vim.ui.input({ prompt = "Filter" }, function(input)
      if input == nil then
        refocus_and_resume(s, deps)
        return
      end
      if input == "" then
        s.filter = nil
      else
        s.filter = input
      end
      deps.render(s)
      refocus_and_resume(s, deps)
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "gg", function()
    local lines = entry_lines(s)
    if #lines == 0 then
      M.ensure_non_header_cursor(s)
      return
    end
    vim.api.nvim_win_set_cursor(s.winid, { lines[1], 0 })
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "G", function()
    local lines = entry_lines(s)
    if #lines == 0 then
      M.ensure_non_header_cursor(s)
      return
    end
    vim.api.nvim_win_set_cursor(s.winid, { lines[#lines], 0 })
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "j", function()
    local count = vim.v.count1
    for _ = 1, count do
      move_cursor_by_stack_item(s, 1)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "k", function()
    local count = vim.v.count1
    for _ = 1, count do
      move_cursor_by_stack_item(s, -1)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "U", function()
    suspend_autoclose(s)
    local stack = require("peekstack.core.stack")
    focus_root_win(s)
    local restored = stack.restore_all(s.root_winid)
    if #restored > 0 then
      deps.render(s)
    end
    local remaining = stack.history_list(s.root_winid)
    if #remaining > 0 then
      vim.notify("Some popups could not be restored", vim.log.levels.WARN)
    elseif #restored == 0 then
      vim.notify("No closed popups to restore", vim.log.levels.INFO)
    end
    refocus_and_resume(s, deps)
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
            deps.render(s)
          else
            vim.notify("Failed to restore history entry", vim.log.levels.WARN)
          end
        else
          vim.notify("Failed to restore history entry", vim.log.levels.WARN)
        end
      end

      refocus_and_resume(s, deps)
      if not selected then
        return
      end
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "?", function()
    toggle_help(s, deps)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "q", function()
    deps.toggle()
  end, { buffer = s.bufnr, nowait = true, silent = true })
end

return M
