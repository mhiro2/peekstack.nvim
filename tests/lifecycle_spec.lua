-- Popup lifecycle through real autocmds: setup -> create -> switch -> close.
local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local events = require("peekstack.core.events")
local helpers = require("tests.helpers")

---@param patterns string[]
---@return table<string, integer[]> received popup ids per event
---@return integer group
local function record_events(patterns)
  local received = {}
  for _, pattern in ipairs(patterns) do
    received[pattern] = {}
  end
  local group = vim.api.nvim_create_augroup("PeekstackLifecycleSpec", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = patterns,
    callback = function(args)
      table.insert(received[args.match], args.data and args.data.popup_id)
    end,
  })
  return received, group
end

---@return integer[]
local function floating_wins()
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(winid).relative ~= "" then
      table.insert(wins, winid)
    end
  end
  return wins
end

local function close_floats()
  for _, winid in ipairs(floating_wins()) do
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

describe("popup lifecycle", function()
  before_each(function()
    stack._reset()
    config.setup({
      ui = {
        quick_peek = { close_events = { "InsertEnter" } },
        popup = { auto_close = { enabled = false } },
      },
    })
    events.setup()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "PeekstackLifecycleSpec")
    close_floats()
    stack._reset()
  end)

  describe("close", function()
    it("emits one close event and history entry per popup on close_all", function()
      local received, group = record_events({ "PeekstackClose", "PeekstackHistoryPush" })
      local ids = {}
      for _ = 1, 3 do
        table.insert(ids, stack.push(helpers.make_location()).id)
      end

      stack.close_all()
      vim.api.nvim_del_augroup_by_id(group)

      table.sort(received.PeekstackClose)
      table.sort(received.PeekstackHistoryPush)
      assert.same(ids, received.PeekstackClose)
      assert.same(ids, received.PeekstackHistoryPush)
      assert.equals(3, #stack.history_list())
      assert.equals(0, #floating_wins())
    end)

    it("emits one close event when a single popup is closed", function()
      local received, group = record_events({ "PeekstackClose" })
      local model = stack.push(helpers.make_location())

      stack.close(model.id)
      vim.api.nvim_del_augroup_by_id(group)

      assert.same({ model.id }, received.PeekstackClose)
      assert.equals(1, #stack.history_list())
    end)

    it("records an externally closed popup once and keeps it restorable", function()
      local received, group = record_events({ "PeekstackClose", "PeekstackHistoryPush" })
      local first = stack.push(helpers.make_location())
      local second = stack.push(helpers.make_location())

      vim.api.nvim_win_close(second.winid, true)
      vim.api.nvim_del_augroup_by_id(group)

      assert.same({ second.id }, received.PeekstackClose)
      assert.same({ second.id }, received.PeekstackHistoryPush)
      assert.same({ first }, stack.list())
      assert.equals(first.id, stack.focused_id())

      local restored = stack.restore_last()
      assert.is_not_nil(restored)
      assert.equals(2, #stack.list())
    end)

    it("survives popups removed by a nested wipe while closing all", function()
      local path = vim.fn.tempname() .. ".txt"
      vim.fn.writefile({ "origin" }, path)
      local root = vim.api.nvim_get_current_win()
      local previous = vim.api.nvim_win_get_buf(root)
      local origin_bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(origin_bufnr)
      vim.bo[origin_bufnr].bufhidden = "wipe"
      vim.api.nvim_win_set_buf(root, origin_bufnr)

      local location = helpers.make_location({ uri = vim.uri_from_bufnr(origin_bufnr) })
      local copy = stack.push(location)
      vim.api.nvim_set_current_win(root)
      local source = stack.push(location, { buffer_mode = "source" })
      vim.api.nvim_set_current_win(root)
      -- The source popup keeps the origin buffer displayed, so it survives this.
      vim.api.nvim_win_set_buf(root, previous)
      assert.is_true(vim.api.nvim_buf_is_valid(origin_bufnr))

      local received, group = record_events({ "PeekstackClose" })
      assert.has_no.errors(function()
        stack.close_all()
      end)
      vim.api.nvim_del_augroup_by_id(group)
      vim.fn.delete(path)

      table.sort(received.PeekstackClose)
      assert.same({ copy.id, source.id }, received.PeekstackClose)
      assert.equals(0, #stack.list())
      assert.equals(0, #floating_wins())
    end)

    it("releases a source quick peek closed from outside", function()
      local received, group = record_events({ "PeekstackClose" })
      local model = stack.push(
        helpers.make_location({
          provider = "diagnostics.under_cursor",
          text = "external close",
        }),
        { stack = false, buffer_mode = "source" }
      )
      assert.is_not_nil(model)
      local ns = vim.api.nvim_get_namespaces().peekstack_diagnostics
      assert.is_true(#vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {}) > 0)

      vim.api.nvim_win_close(model.winid, true)
      vim.api.nvim_del_augroup_by_id(group)

      assert.is_nil(stack._ephemerals()[model.id])
      assert.is_nil(stack.find_by_id(model.id))
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {}))
      assert.same({ model.id }, received.PeekstackClose)
    end)
  end)
end)
