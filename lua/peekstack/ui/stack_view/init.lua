local keymaps = require("peekstack.ui.stack_view.keymaps")
local renderer = require("peekstack.ui.stack_view.render")
local state = require("peekstack.ui.stack_view.state")
local window = require("peekstack.ui.stack_view.window")

local M = {}

---@param s PeekstackStackViewState
local function render_state(s)
  renderer.render(s, window.is_ready)
end

---@return PeekstackStackViewKeymapDeps
local function keymap_deps()
  return {
    render = render_state,
    toggle = function()
      M.toggle()
    end,
    is_open = function(s)
      return window.is_open(s)
    end,
    focus_stack_view = function(s)
      window.focus(s)
    end,
  }
end

---@param s PeekstackStackViewState
---@param opts? { refocus: boolean }
local function close_stack_view(s, opts)
  keymaps.close_help(s, opts, keymap_deps())
  window.close(s)
end

---Setup stack view autocmds.
function M.setup()
  state.setup()
end

---Open the stack view.
function M.open()
  M.setup()

  local s = state.current()
  if window.is_open(s) then
    window.focus(s)
    render_state(s)
    return
  end

  window.open(s, {
    before_close = function(opts)
      keymaps.close_help(s, opts, keymap_deps())
    end,
    ensure_non_header_cursor = function()
      keymaps.ensure_non_header_cursor(s)
    end,
  })

  keymaps.apply(s, keymap_deps())
  render_state(s)
end

---Toggle the stack view (open if closed, close if open).
function M.toggle()
  local s = state.current()
  if window.is_open(s) then
    close_stack_view(s)
    return
  end
  M.open()
end

---Re-render all open stack views (called on push/close events).
function M.refresh_all()
  for _, s in pairs(state.all()) do
    if window.is_ready(s) then
      render_state(s)
    end
  end
end

---Resize and re-render all open stack views (called on VimResized/WinResized).
function M.resize_all()
  for _, s in pairs(state.all()) do
    if window.is_open(s) then
      window.resize(s)
      render_state(s)
    end
  end
end

return M
