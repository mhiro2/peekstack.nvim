describe("providers with context", function()
  local config = require("peekstack.config")

  before_each(function()
    config.setup({})
  end)

  local function make_ctx(overrides)
    return vim.tbl_extend("force", {
      winid = vim.api.nvim_get_current_win(),
      bufnr = vim.api.nvim_get_current_buf(),
      source_bufnr = nil,
      popup_id = nil,
      buffer_mode = nil,
      line_offset = 0,
      position = { line = 0, character = 0 },
      root_winid = vim.api.nvim_get_current_win(),
      from_popup = false,
    }, overrides or {})
  end

  ---@param provider_fn fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
  ---@param ctx PeekstackProviderContext
  ---@return PeekstackLocation[]
  local function run_provider(provider_fn, ctx)
    local result = nil
    provider_fn(ctx, function(locations)
      result = locations
    end)
    assert.is_table(result, "provider did not invoke its callback")
    return result
  end

  describe("file provider", function()
    local file_provider = require("peekstack.providers.file")
    local root
    local dir_a
    local dir_b
    local buf_a
    local buf_b

    before_each(function()
      -- Two source buffers in different directories that both refer to a
      -- same-named target, so the resolved URI shows which buffer was the base.
      root = vim.fn.resolve(vim.fn.tempname())
      dir_a = root .. "/a"
      dir_b = root .. "/b"
      vim.fn.mkdir(dir_a, "p")
      vim.fn.mkdir(dir_b, "p")
      for _, dir in ipairs({ dir_a, dir_b }) do
        vim.fn.writefile({ "-- target" }, dir .. "/peekstack_ctx_target.lua")
        vim.fn.writefile({ "peekstack_ctx_target.lua" }, dir .. "/source.lua")
      end

      buf_a = vim.fn.bufadd(dir_a .. "/source.lua")
      vim.fn.bufload(buf_a)
      buf_b = vim.fn.bufadd(dir_b .. "/source.lua")
      vim.fn.bufload(buf_b)

      vim.api.nvim_set_current_buf(buf_a)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end)

    after_each(function()
      for _, bufnr in ipairs({ buf_a, buf_b }) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      vim.fn.delete(root, "rf")
    end)

    it("resolves the target relative to the current buffer", function()
      local locations = run_provider(file_provider.under_cursor, make_ctx({ bufnr = buf_a }))

      assert.same({
        {
          uri = vim.uri_from_fname(dir_a .. "/peekstack_ctx_target.lua"),
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 0 },
          },
          provider = "file.under_cursor",
        },
      }, locations)
    end)

    it("resolves the target relative to ctx.bufnr instead of the current buffer", function()
      local locations = run_provider(file_provider.under_cursor, make_ctx({ bufnr = buf_b }))

      assert.equals(1, #locations)
      assert.equals(vim.uri_from_fname(dir_b .. "/peekstack_ctx_target.lua"), locations[1].uri)
      assert.equals("file.under_cursor", locations[1].provider)
    end)
  end)

  describe("diagnostics provider", function()
    local diag_provider = require("peekstack.providers.diagnostics")
    local ns = vim.api.nvim_create_namespace("peekstack_providers_context_spec")
    local root
    local buf_a
    local buf_b

    ---@param name string
    ---@return integer
    local function make_named_buf(name)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, root .. "/" .. name)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3 here" })
      return bufnr
    end

    before_each(function()
      root = vim.fn.resolve(vim.fn.tempname())
      buf_a = make_named_buf("a.lua")
      buf_b = make_named_buf("b.lua")

      -- The current buffer carries a diagnostic on the same line as ctx.bufnr,
      -- so reading the wrong buffer is observable.
      vim.diagnostic.set(ns, buf_a, {
        { lnum = 2, col = 0, message = "a-line3", severity = vim.diagnostic.severity.ERROR },
      })
      vim.diagnostic.set(ns, buf_b, {
        { lnum = 1, col = 0, message = "b-line2", severity = vim.diagnostic.severity.INFO },
        { lnum = 2, col = 6, end_col = 10, message = "b-line3", severity = vim.diagnostic.severity.WARN },
      })
      vim.api.nvim_set_current_buf(buf_a)
    end)

    after_each(function()
      vim.diagnostic.reset(ns)
      for _, bufnr in ipairs({ buf_a, buf_b }) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
    end)

    it("under_cursor returns only the diagnostics on ctx.position.line of ctx.bufnr", function()
      local locations =
        run_provider(diag_provider.under_cursor, make_ctx({ bufnr = buf_b, position = { line = 2, character = 0 } }))

      assert.same({
        {
          uri = vim.uri_from_fname(root .. "/b.lua"),
          range = {
            start = { line = 2, character = 6 },
            ["end"] = { line = 2, character = 10 },
          },
          text = "b-line3",
          kind = vim.diagnostic.severity.WARN,
          provider = "diagnostics.under_cursor",
        },
      }, locations)
    end)

    it("under_cursor returns nothing for a line of ctx.bufnr without diagnostics", function()
      local locations =
        run_provider(diag_provider.under_cursor, make_ctx({ bufnr = buf_b, position = { line = 0, character = 0 } }))

      assert.same({}, locations)
    end)

    it("in_buffer returns every diagnostic of ctx.bufnr and none from the current buffer", function()
      local locations = run_provider(diag_provider.in_buffer, make_ctx({ bufnr = buf_b }))

      local seen = {}
      for _, loc in ipairs(locations) do
        assert.equals(vim.uri_from_fname(root .. "/b.lua"), loc.uri)
        assert.equals("diagnostics.in_buffer", loc.provider)
        seen[loc.text] = loc.range.start.line
      end
      assert.equals(2, #locations)
      assert.same({ ["b-line2"] = 1, ["b-line3"] = 2 }, seen)
    end)
  end)
end)
