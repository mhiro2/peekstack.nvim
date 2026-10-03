local config = require("peekstack.config")
local promote = require("peekstack.core.promote")
local stack_view = require("peekstack.ui.stack_view")
local keymap_spec = require("peekstack.ui.keymap_spec")

local M = {}

---@class PeekstackSourcePopupMapState
---@field winid integer
---@field bufnr integer
---@field installed string[] lhs of the installed mappings, as resolved when they were set
---@field original table[] maparg() dicts of the buffer-local mappings that were shadowed

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

--- Snapshot the buffer-local normal-mode mapping that `lhs` resolves to.
--- `maparg()` applies the same key resolution as Neovim (`<C-j>` vs `<C-J>`,
--- `<leader>`, `<C-w>`), and the returned dict keeps callback, expr, `<SID>`
--- and script context so `mapset()` can recreate it exactly.
---@param bufnr integer
---@param lhs string
---@return table?
local function get_buffer_map(bufnr, lhs)
  local item = vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.maparg(lhs, "n", false, true)
  end)
  if item.buffer ~= 1 then
    return nil
  end
  return item
end

--- Recreate a snapshot in normal mode only. Installing a normal-mode map
--- leaves the other modes of a `:map` mapping untouched, so they must not be
--- reset to the snapshot.
---@param bufnr integer
---@param item table
local function restore_buffer_map(bufnr, item)
  vim.api.nvim_buf_call(bufnr, function()
    vim.fn.mapset("n", false, item)
  end)
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

  -- Delete every installed mapping before restoring, so a restored mapping is
  -- never removed again by another lhs spelling that resolves to the same keys.
  for _, lhs in ipairs(active.installed) do
    pcall(vim.keymap.del, "n", lhs, { buffer = active.bufnr })
  end
  for _, item in ipairs(active.original) do
    restore_buffer_map(active.bufnr, item)
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
  ---@type table[]
  local original = {}
  -- Snapshot every original mapping before installing any, so an lhs that
  -- resolves to the same keys as an earlier spec does not capture our own map.
  for _, spec in ipairs(specs) do
    original[#original + 1] = get_buffer_map(popup.bufnr, spec.lhs)
  end
  keymap_spec.apply(popup.bufnr, specs)

  -- Record the resolved keys so cleanup does not depend on `mapleader` at
  -- that later time.
  ---@type string[]
  local installed = {}
  for _, spec in ipairs(specs) do
    local item = get_buffer_map(popup.bufnr, spec.lhs)
    if item then
      installed[#installed + 1] = item.lhs
    end
  end

  active_source_maps = {
    winid = popup.winid,
    bufnr = popup.bufnr,
    installed = installed,
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
