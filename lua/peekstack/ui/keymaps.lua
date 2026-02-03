local config = require("peekstack.config")
local promote = require("peekstack.core.promote")
local stack_view = require("peekstack.ui.stack_view")

local M = {}

---@param bufnr integer
---@param lhs string?
---@param rhs function
---@param desc string
local function map(bufnr, lhs, rhs, desc)
  if not lhs or lhs == "" then
    return
  end
  vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true, silent = true, desc = desc })
end

--- Resolve the current popup by looking up its id in the stack.
--- This avoids holding a stale reference to a popup object.
---@param popup_id integer
---@return table?
local function resolve_popup(popup_id)
  local stack = require("peekstack.core.stack")
  return stack.find_by_id(popup_id)
end

---@param popup table
function M.apply_popup(popup)
  local keys = config.get().ui.keys
  local popup_id = popup.id

  map(popup.bufnr, keys.close, function()
    local stack = require("peekstack.core.stack")
    local p = resolve_popup(popup_id)
    if
      p
      and p.buffer_mode == "source"
      and vim.api.nvim_buf_is_valid(p.bufnr)
      and vim.bo[p.bufnr].modified
      and config.get().ui.popup.source.confirm_on_close
    then
      vim.ui.input({ prompt = "Buffer has unsaved changes. Close? (y/n) " }, function(input)
        if input and (input == "y" or input == "Y") then
          stack.close(popup_id)
        end
      end)
      return
    end
    stack.close(popup_id)
  end, "Peekstack close")

  map(popup.bufnr, keys.focus_next, function()
    local stack = require("peekstack.core.stack")
    stack.focus_next()
  end, "Peekstack focus next")

  map(popup.bufnr, keys.focus_prev, function()
    local stack = require("peekstack.core.stack")
    stack.focus_prev()
  end, "Peekstack focus prev")

  map(popup.bufnr, keys.promote_split, function()
    local p = resolve_popup(popup_id)
    if p then
      promote.split(p)
    end
  end, "Peekstack promote split")

  map(popup.bufnr, keys.promote_vsplit, function()
    local p = resolve_popup(popup_id)
    if p then
      promote.vsplit(p)
    end
  end, "Peekstack promote vsplit")

  map(popup.bufnr, keys.promote_tab, function()
    local p = resolve_popup(popup_id)
    if p then
      promote.tab(p)
    end
  end, "Peekstack promote tab")

  map(popup.bufnr, keys.toggle_stack_view, function()
    stack_view.toggle()
  end, "Peekstack stack view")
end

return M
