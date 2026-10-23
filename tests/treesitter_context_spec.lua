describe("peekstack.util.treesitter", function()
  local treesitter = require("peekstack.util.treesitter")
  local config = require("peekstack.config")

  before_each(function()
    config.setup({
      ui = {
        title = {
          context = {
            enabled = true,
            max_depth = 5,
            separator = " • ",
            node_types = {},
          },
        },
      },
    })
  end)

  ---Build a minimal Tree-sitter node tree from a nested spec.
  ---@param spec { type: string, range: integer[], children?: table[] }
  ---@param parent? table
  ---@return table
  local function build_node(spec, parent)
    local node = { _type = spec.type, _range = spec.range, _parent = parent, _children = {} }
    function node:type()
      return self._type
    end
    function node:range()
      return unpack(self._range)
    end
    function node:parent()
      return self._parent
    end
    function node:iter_children()
      local i = 0
      return function()
        i = i + 1
        return self._children[i]
      end
    end
    local function contains(n, row, col)
      local sr, sc, er, ec = n:range()
      local after_start = row > sr or (row == sr and col >= sc)
      local before_end = row < er or (row == er and col < ec)
      return after_start and before_end
    end
    function node:named_descendant_for_range(row, col)
      for _, child in ipairs(self._children) do
        if contains(child, row, col) then
          return child:named_descendant_for_range(row, col)
        end
      end
      return self
    end
    for _, child_spec in ipairs(spec.children or {}) do
      table.insert(node._children, build_node(child_spec, node))
    end
    return node
  end

  -- Mirrors the tree the Lua grammar produces for FIXTURE_LINES.
  local FIXTURE_LINES = {
    "local function outer()",
    "  local function inner()",
    "    return 42",
    "  end",
    "end",
    "local x = 1",
  }
  local FIXTURE_TREE = {
    type = "chunk",
    range = { 0, 0, 6, 0 },
    children = {
      {
        type = "function_declaration",
        range = { 0, 0, 4, 3 },
        children = {
          { type = "identifier", range = { 0, 15, 0, 20 } },
          { type = "parameters", range = { 0, 20, 0, 22 } },
          {
            type = "block",
            range = { 1, 2, 3, 5 },
            children = {
              {
                type = "function_declaration",
                range = { 1, 2, 3, 5 },
                children = {
                  { type = "identifier", range = { 1, 17, 1, 22 } },
                  { type = "parameters", range = { 1, 22, 1, 24 } },
                  {
                    type = "block",
                    range = { 2, 4, 2, 13 },
                    children = {
                      {
                        type = "return_statement",
                        range = { 2, 4, 2, 13 },
                        children = { { type = "number", range = { 2, 11, 2, 13 } } },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      { type = "variable_declaration", range = { 5, 0, 5, 11 } },
    },
  }

  ---@param spec table
  ---@return table
  local function tree_of(spec)
    local root = build_node(spec)
    return {
      root = function()
        return root
      end,
    }
  end

  describe("with a controlled parser", function()
    local original_get_parser
    local bufnr
    local trees

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, FIXTURE_LINES)
      vim.bo[bufnr].filetype = "lua"

      trees = { tree_of(FIXTURE_TREE) }
      original_get_parser = vim.treesitter.get_parser
      vim.treesitter.get_parser = function(target)
        if target == bufnr then
          return {
            parse = function() end,
            trees = function()
              return trees
            end,
          }
        end
        return original_get_parser(target)
      end
    end)

    after_each(function()
      vim.treesitter.get_parser = original_get_parser
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns the name of the nearest enclosing function", function()
      assert.equals("inner", treesitter.context_at(bufnr, 2, 11, { enabled = true, max_depth = 5 }))
      assert.equals("outer", treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 5 }))
    end)

    it("stops walking up the tree at max_depth", function()
      -- number -> return_statement -> block -> function_declaration is four levels.
      assert.equals("inner", treesitter.context_at(bufnr, 2, 11, { enabled = true, max_depth = 4 }))
      assert.is_nil(treesitter.context_at(bufnr, 2, 11, { enabled = true, max_depth = 3 }))
      assert.is_nil(treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 0 }))
    end)

    it("returns nil outside any function", function()
      assert.is_nil(treesitter.context_at(bufnr, 5, 0, { enabled = true, max_depth = 5 }))
    end)

    it("returns nil for a position beyond the parsed tree", function()
      assert.is_nil(treesitter.context_at(bufnr, #FIXTURE_LINES + 100, 0, { enabled = true, max_depth = 5 }))
    end)

    it("prefers the narrowest tree that contains the line", function()
      -- An injected tree covering only line 2 that declares a function named "42".
      local injected = tree_of({
        type = "chunk",
        range = { 2, 4, 2, 13 },
        children = {
          {
            type = "function_declaration",
            range = { 2, 4, 2, 13 },
            children = { { type = "identifier", range = { 2, 11, 2, 13 } } },
          },
        },
      })
      local broad = trees[1]

      -- Both orders, so the result depends on the range and not on the order.
      for _, order in ipairs({ { broad, injected }, { injected, broad } }) do
        trees = order
        assert.equals("42", treesitter.context_at(bufnr, 2, 11, { enabled = true, max_depth = 5 }))
        assert.equals("outer", treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 5 }))
      end
    end)

    it("returns nil when context is disabled", function()
      assert.is_nil(treesitter.context_at(bufnr, 2, 11, { enabled = false, max_depth = 5 }))
    end)

    it("uses node_types from opts for the buffer filetype", function()
      local opts = { enabled = true, max_depth = 5, node_types = { lua = { "variable_declaration" } } }
      assert.equals("local x = 1", treesitter.context_at(bufnr, 5, 0, opts))
      assert.is_nil(treesitter.context_at(bufnr, 2, 11, opts))
    end)
  end)

  it("should return nil when parser is not available", function()
    -- Use a buffer that likely doesn't have a parser
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "unknown_filetype_xyz"

    local result = treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 5 })
    assert.is_nil(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("should handle invalid buffer gracefully", function()
    local result = treesitter.context_at(-1, 0, 0, { enabled = true, max_depth = 5 })
    assert.is_nil(result)
  end)

  -- The test runtimepath only contains $VIMRUNTIME, so load the Lua parser
  -- bundled with the running Nvim directly when it is not already available.
  local function load_lua_parser()
    local ok, added = pcall(vim.treesitter.language.add, "lua")
    if ok and added then
      return true
    end
    local path = vim.fn.fnamemodify(vim.v.progpath, ":h:h") .. "/lib/nvim/parser/lua.so"
    if vim.fn.filereadable(path) == 0 then
      return false
    end
    ok, added = pcall(vim.treesitter.language.add, "lua", { path = path })
    return ok and added == true
  end

  if load_lua_parser() then
    it("extracts the enclosing function name with the real Lua parser", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = "lua"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, FIXTURE_LINES)

      local inner = treesitter.context_at(bufnr, 2, 11, { enabled = true, max_depth = 10 })
      local outer = treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 10 })
      local none = treesitter.context_at(bufnr, 5, 0, { enabled = true, max_depth = 10 })
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.equals("inner", inner)
      assert.equals("outer", outer)
      assert.is_nil(none)
    end)
  else
    require("plenary.busted").pending(
      "extracts the enclosing function name with the real Lua parser (Lua parser unavailable)"
    )
  end

  it("should use the provided buffer when extracting node text", function()
    local bufnr_primary = vim.api.nvim_create_buf(false, true)
    local bufnr_other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr_primary, 0, -1, false, { "alpha" })
    vim.api.nvim_buf_set_lines(bufnr_other, 0, -1, false, { "beta" })
    vim.api.nvim_set_current_buf(bufnr_other)

    local child = {}
    function child:type()
      return "identifier"
    end
    function child:range()
      return 0, 0, 0, 5
    end

    local node = {}
    function node:range()
      return 0, 0, 0, 5
    end
    function node:iter_children()
      local i = 0
      local children = { child }
      return function()
        i = i + 1
        return children[i]
      end
    end

    local result = treesitter._extract_name(node, "function_declaration", bufnr_primary)
    assert.equals("alpha", result)

    vim.api.nvim_buf_delete(bufnr_primary, { force = true })
    vim.api.nvim_buf_delete(bufnr_other, { force = true })
  end)
end)
