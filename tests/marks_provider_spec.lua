local config = require("peekstack.config")
local marks_util = require("peekstack.util.marks")

describe("marks provider", function()
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

  before_each(function()
    config.setup({
      providers = {
        marks = {
          enable = true,
          include = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
          include_special = false,
        },
      },
    })
  end)

  describe("util.marks.collect", function()
    it("returns empty table when no marks exist", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      local locations = marks_util.collect("buffer", bufnr, {
        include = "abcdefghijklmnopqrstuvwxyz",
        include_special = false,
      })
      assert.is_table(locations)
      assert.equals(0, #locations)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("collects local marks with scope buffer", function()
      local tmpfile = vim.fn.resolve(vim.fn.tempname()) .. ".txt"
      vim.fn.writefile({ "hello world", "second line" }, tmpfile)
      local bufnr = vim.fn.bufadd(tmpfile)
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)

      vim.api.nvim_buf_set_mark(bufnr, "a", 2, 3, {})

      local locations = marks_util.collect("buffer", bufnr, {
        include = "abcdefghijklmnopqrstuvwxyz",
        include_special = false,
      })

      assert.same({
        {
          uri = vim.uri_from_fname(tmpfile),
          range = {
            start = { line = 1, character = 3 },
            ["end"] = { line = 1, character = 3 },
          },
          text = "[a] second line",
          provider = "marks.buffer",
        },
      }, locations)

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(tmpfile)
    end)

    it("filters marks by include string", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
      vim.api.nvim_set_current_buf(bufnr)

      vim.api.nvim_buf_set_mark(bufnr, "a", 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, "b", 2, 0, {})

      -- Only include mark 'a'
      local locations = marks_util.collect("buffer", bufnr, {
        include = "a",
        include_special = false,
      })

      local has_a = false
      local has_b = false
      for _, loc in ipairs(locations) do
        if loc.text and loc.text:find("%[a%]") then
          has_a = true
        end
        if loc.text and loc.text:find("%[b%]") then
          has_b = true
        end
      end
      assert.is_true(has_a)
      assert.is_false(has_b)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("excludes special marks when include_special is false", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
      vim.api.nvim_set_current_buf(bufnr)

      vim.api.nvim_buf_set_mark(bufnr, "a", 1, 0, {})
      for _, mark in ipairs({ "'", '"', "[", "]", "<", ">" }) do
        vim.api.nvim_buf_set_mark(bufnr, mark, 2, 0, {})
      end

      local include = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'`^.<>[]\""
      local function collected_marks(include_special)
        local chars = {}
        local locations = marks_util.collect("buffer", bufnr, { include = include, include_special = include_special })
        for _, loc in ipairs(locations) do
          table.insert(chars, loc.text:match("^%[(.)%]"))
        end
        table.sort(chars)
        return chars
      end

      -- The special marks are really there: listing them with include_special
      -- returns them alongside the regular mark. "." is set by the line edit.
      local with_special = collected_marks(true)
      for _, mark in ipairs({ "'", '"', ".", "[", "]", "<", ">" }) do
        assert.is_true(vim.list_contains(with_special, mark), "missing special mark " .. mark)
      end

      assert.same({ "a" }, collected_marks(false))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("adds special marks only when they are also listed in include", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_mark(bufnr, "<", 2, 0, {})

      local function has_mark(include)
        local locations = marks_util.collect("buffer", bufnr, { include = include, include_special = true })
        for _, loc in ipairs(locations) do
          if loc.text and loc.text:find("[<]", 1, true) then
            return true
          end
        end
        return false
      end

      assert.is_false(has_mark("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
      assert.is_true(has_mark("<"))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("providers/marks", function()
    local marks_provider = require("peekstack.providers.marks")
    local root
    local file_a
    local file_b
    local buf_a
    local buf_b

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

    ---@param path string
    ---@param line integer 0-based
    ---@param text string
    ---@param provider string
    ---@return PeekstackLocation
    local function mark_location(path, line, text, provider)
      return {
        uri = vim.uri_from_fname(path),
        range = {
          start = { line = line, character = 0 },
          ["end"] = { line = line, character = 0 },
        },
        text = text,
        provider = provider,
      }
    end

    before_each(function()
      vim.cmd("delmarks A-Z0-9")
      root = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(root, "p")
      file_a = root .. "/a.txt"
      file_b = root .. "/b.txt"
      vim.fn.writefile({ "a1", "a2", "a3" }, file_a)
      vim.fn.writefile({ "b1", "b2", "b3" }, file_b)
      buf_a = vim.fn.bufadd(file_a)
      vim.fn.bufload(buf_a)
      buf_b = vim.fn.bufadd(file_b)
      vim.fn.bufload(buf_b)

      -- The current buffer and ctx.bufnr each hold a local mark, and the
      -- global mark lives in ctx.bufnr, so every scope has a distinct answer.
      vim.api.nvim_buf_set_mark(buf_a, "a", 2, 0, {})
      vim.api.nvim_buf_set_mark(buf_b, "b", 1, 0, {})
      vim.api.nvim_buf_set_mark(buf_b, "A", 3, 0, {})
      vim.api.nvim_set_current_buf(buf_a)
    end)

    after_each(function()
      vim.cmd("delmarks A-Z0-9")
      for _, bufnr in ipairs({ buf_a, buf_b }) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      vim.fn.delete(root, "rf")
    end)

    it("buffer provider returns the local marks of ctx.bufnr only", function()
      local locations = run_provider(marks_provider.buffer, make_ctx({ bufnr = buf_b }))

      assert.same({ mark_location(file_b, 0, "[b] b1", "marks.buffer") }, locations)
    end)

    it("global provider returns the global marks only", function()
      local locations = run_provider(marks_provider.global, make_ctx({ bufnr = buf_b }))

      assert.same({ mark_location(file_b, 2, "[A] b3", "marks.global") }, locations)
    end)

    it("all provider returns the global marks and the local marks of ctx.bufnr", function()
      local locations = run_provider(marks_provider.all, make_ctx({ bufnr = buf_b }))

      assert.same({
        mark_location(file_b, 2, "[A] b3", "marks.global"),
        mark_location(file_b, 0, "[b] b1", "marks.buffer"),
      }, locations)
    end)

    it("applies the configured include filter", function()
      config.setup({
        providers = {
          marks = {
            enable = true,
            include = "A",
            include_special = false,
          },
        },
      })

      local locations = run_provider(marks_provider.all, make_ctx({ bufnr = buf_b }))

      assert.same({ mark_location(file_b, 2, "[A] b3", "marks.global") }, locations)
    end)
  end)
end)
