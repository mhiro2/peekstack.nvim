local config = require("peekstack.config")
local promote = require("peekstack.core.promote")
local stack_view = require("peekstack.ui.stack_view")
local keymap_spec = require("peekstack.ui.keymap_spec")

local M = {}

---@class PeekstackSourcePopupMapState
---@field winid integer
---@field bufnr integer
---@field lhs string[]
---@field original table<string, vim.api.keyset.get_keymap?>

--- Buffer-local keymaps temporarily installed for the currently focused
--- source-mode popup window. They are restored on WinLeave/close so the
--- shared source buffer keeps its original mappings in normal editing.
---@type PeekstackSourcePopupMapState?
local active_source_maps = nil

--- Navigate from a popup to an adjacent split window.
--- Moves focus back to the root (non-floating) window first, then executes
--- wincmd in the given direction.
---@param direction string  one of "h", "j", "k", "l"
local function nav_to_split(direction)
  local stack = require("peekstack.core.stack")
  local root = stack.get_root_winid()
  if root and vim.api.nvim_win_is_valid(root) then
    vim.api.nvim_set_current_win(root)
  end
  vim.api.nvim_cmd({ cmd = "wincmd", args = { direction } }, {})
end

--- Resolve the popup in the current window.
---@return PeekstackPopupModel?
local function resolve_current_popup()
  local winid = vim.api.nvim_get_current_win()
  if vim.w[winid].peekstack_popup_id == nil then
    return nil
  end
  local stack = require("peekstack.core.stack")
  local _, popup = stack.find_by_winid(winid)
  return popup
end

---@return PeekstackKeymapSpec[]
local function mapping_specs()
  local keys = config.get().ui.keys
  ---@type PeekstackKeymapSpec[]
  local raw = {
    {
      lhs = keys.close,
      rhs = function()
        local stack = require("peekstack.core.stack")
        local popup = resolve_current_popup()
        if not popup then
          return
        end
        if
          popup.buffer_mode == "source"
          and vim.api.nvim_buf_is_valid(popup.bufnr)
          and vim.bo[popup.bufnr].modified
          and config.get().ui.popup.source.confirm_on_close
        then
          vim.ui.input({ prompt = "Buffer has unsaved changes. Close? (y/n) " }, function(input)
            if input and (input == "y" or input == "Y") then
              stack.close(popup.id)
            end
          end)
          return
        end
        stack.close(popup.id)
      end,
      desc = "Peekstack close",
    },
    {
      lhs = keys.focus_next,
      rhs = function()
        local stack = require("peekstack.core.stack")
        stack.focus_next()
      end,
      desc = "Peekstack focus next",
    },
    {
      lhs = keys.focus_prev,
      rhs = function()
        local stack = require("peekstack.core.stack")
        stack.focus_prev()
      end,
      desc = "Peekstack focus prev",
    },
    {
      lhs = keys.promote_split,
      rhs = function()
        local popup = resolve_current_popup()
        if popup then
          promote.split(popup)
        end
      end,
      desc = "Peekstack promote split",
    },
    {
      lhs = keys.promote_vsplit,
      rhs = function()
        local popup = resolve_current_popup()
        if popup then
          promote.vsplit(popup)
        end
      end,
      desc = "Peekstack promote vsplit",
    },
    {
      lhs = keys.promote_tab,
      rhs = function()
        local popup = resolve_current_popup()
        if popup then
          promote.tab(popup)
        end
      end,
      desc = "Peekstack promote tab",
    },
    {
      lhs = keys.toggle_stack_view,
      rhs = function()
        stack_view.toggle()
      end,
      desc = "Peekstack stack view",
    },
    {
      lhs = keys.zoom,
      rhs = function()
        local stack = require("peekstack.core.stack")
        stack.toggle_zoom()
      end,
      desc = "Peekstack zoom",
    },
    {
      lhs = "<C-w>h",
      rhs = function()
        nav_to_split("h")
      end,
      desc = "Peekstack navigate left",
    },
    {
      lhs = "<C-w>j",
      rhs = function()
        nav_to_split("j")
      end,
      desc = "Peekstack navigate down",
    },
    {
      lhs = "<C-w>k",
      rhs = function()
        nav_to_split("k")
      end,
      desc = "Peekstack navigate up",
    },
    {
      lhs = "<C-w>l",
      rhs = function()
        nav_to_split("l")
      end,
      desc = "Peekstack navigate right",
    },
  }

  return keymap_spec.normalize(raw)
end

---@param bufnr integer
---@param lhs string
---@return vim.api.keyset.get_keymap?
local function get_buffer_map(bufnr, lhs)
  for _, item in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if item.lhs == lhs then
      return item
    end
  end
  return nil
end

---@param bufnr integer
---@param item vim.api.keyset.get_keymap?
local function restore_buffer_map(bufnr, item)
  if not item or not item.lhs or item.lhs == "" then
    return
  end

  local opts = {
    buffer = bufnr,
    desc = item.desc ~= "" and item.desc or nil,
    expr = item.expr == 1,
    nowait = item.nowait == 1,
    remap = item.noremap == 0,
    script = item.script == 1,
    silent = item.silent == 1,
  }

  if item.callback ~= nil then
    vim.keymap.set("n", item.lhs, item.callback, opts)
    return
  end

  if type(item.rhs) == "string" then
    vim.keymap.set("n", item.lhs, item.rhs, opts)
  end
end

local function deactivate_active_source_popup()
  local active = active_source_maps
  if not active then
    return
  end
  active_source_maps = nil

  if not vim.api.nvim_buf_is_valid(active.bufnr) then
    return
  end

  for _, lhs in ipairs(active.lhs) do
    pcall(vim.keymap.del, "n", lhs, { buffer = active.bufnr })
    restore_buffer_map(active.bufnr, active.original[lhs])
  end
end

---@param popup PeekstackPopupModel
local function activate_source_popup(popup)
  if popup.buffer_mode ~= "source" then
    return
  end
  if active_source_maps and active_source_maps.winid == popup.winid then
    return
  end

  deactivate_active_source_popup()

  local specs = mapping_specs()
  ---@type table<string, vim.api.keyset.get_keymap?>
  local original = {}
  ---@type string[]
  local lhs_list = {}

  for _, spec in ipairs(specs) do
    original[spec.lhs] = get_buffer_map(popup.bufnr, spec.lhs)
    keymap_spec.set(popup.bufnr, spec)
    lhs_list[#lhs_list + 1] = spec.lhs
  end

  active_source_maps = {
    winid = popup.winid,
    bufnr = popup.bufnr,
    lhs = lhs_list,
    original = original,
  }
end

---@param popup table
function M.apply_popup(popup)
  if popup.buffer_mode == "source" then
    activate_source_popup(popup)
    return
  end

  keymap_spec.apply(popup.bufnr, mapping_specs())
end

---@param target integer|PeekstackPopupModel
function M.activate_source_popup(target)
  local popup = target
  if type(target) ~= "table" then
    local stack = require("peekstack.core.stack")
    local _, found = stack.find_by_winid(target)
    popup = found
  end
  if not popup then
    return
  end
  activate_source_popup(popup)
end

---@param target integer|PeekstackPopupModel
function M.deactivate_source_popup(target)
  if not active_source_maps then
    return
  end

  local winid = type(target) == "table" and target.winid or target
  if winid ~= active_source_maps.winid then
    return
  end

  deactivate_active_source_popup()
end

--- Remove active source-mode popup keymaps before the popup window closes.
---@param popup PeekstackPopupModel
function M.remove_popup(popup)
  M.deactivate_source_popup(popup)
end

return M
