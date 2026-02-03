local M = {}

---Default node types to look for by filetype
---@type table<string, string[]>
local DEFAULT_NODE_TYPES = {
  lua = { "function_declaration", "method", "local_function" },
  python = { "function_definition", "class_definition" },
  javascript = { "function_declaration", "method_definition", "class_declaration" },
  typescript = { "function_declaration", "method_definition", "class_declaration" },
  rust = { "function_item", "struct_item", "impl_item" },
  go = { "function_declaration", "method_declaration", "type_declaration" },
  java = { "method_declaration", "class_declaration", "interface_declaration" },
  c = { "function_definition", "struct_specifier" },
  cpp = { "function_definition", "class_specifier", "struct_specifier" },
  ruby = { "method", "class" },
  php = { "function_definition", "class_declaration" },
}

---Get treesitter context at a specific position
---@param bufnr integer
---@param line integer
---@param col integer
---@param opts PeekstackTreesitterContextOpts
---@return string?
function M.context_at(bufnr, line, col, opts)
  opts = opts or {}

  if not opts.enabled then
    return nil
  end

  -- Check if parser is available
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  -- Parse all trees including injected languages (Vue, Markdown, etc.)
  parser:parse()
  local trees = parser:trees()
  if not trees or vim.tbl_isempty(trees) then
    return nil
  end

  -- Find the narrowest tree whose root contains the target position.
  -- Injected language trees are narrower than the root tree.
  local root = nil
  local smallest_range = math.huge
  for _, tree in pairs(trees) do
    local r = tree:root()
    if r then
      local sr, _, er, _ = r:range()
      if line >= sr and line <= er then
        local range_size = er - sr
        if range_size < smallest_range then
          smallest_range = range_size
          root = r
        end
      end
    end
  end

  if not root then
    return nil
  end

  -- Find the node at the position
  local node = root:named_descendant_for_range(line, col, line, col)
  if not node then
    return nil
  end

  local filetype = vim.bo[bufnr].filetype
  local node_types = opts.node_types and opts.node_types[filetype] or DEFAULT_NODE_TYPES[filetype] or {}

  -- Walk up the tree to find a matching node type
  local current = node
  local depth = 0
  local max_depth = opts.max_depth or 5

  while current and depth < max_depth do
    local node_type = current:type()

    -- Check if this node type matches
    for _, target_type in ipairs(node_types) do
      if node_type == target_type then
        -- Extract the name from the node
        local name = M._extract_name(current, node_type, bufnr)
        if name then
          return name
        end
      end
    end

    current = current:parent()
    depth = depth + 1
  end

  return nil
end

---Extract text from a node range
---@param start_row integer
---@param start_col integer
---@param end_col integer
---@param bufnr integer
---@return string?
local function extract_node_text(start_row, start_col, end_col, bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)
  if not lines or #lines == 0 then
    return nil
  end

  local text = lines[1]:sub(start_col + 1, end_col)
  return text:match("^%s*(.-)%s*$")
end

---Extract a readable name from a treesitter node
---@param node any
---@param _node_type string
---@param bufnr integer
---@return string?
function M._extract_name(node, _node_type, bufnr)
  if not node then
    return nil
  end
  local start_row, start_col, _end_row, end_col = node:range()

  -- Try to find a "name" or "identifier" child
  for child in node:iter_children() do
    local child_type = child:type()
    if child_type == "name" or child_type == "identifier" then
      local child_start_row, child_start_col, _, child_end_col = child:range()
      local text = extract_node_text(child_start_row, child_start_col, child_end_col, bufnr)
      if text then
        return text
      end
    end
  end

  -- Fallback: extract and clean text from the node's first line
  local text = extract_node_text(start_row, start_col, end_col, bufnr)
  if not text then
    return nil
  end

  -- Clean up common patterns
  text = text:gsub("^function%s+", "")
  text = text:gsub("^local%s+function%s+", "")
  text = text:match("^([^%(]*)") or text

  return text
end

return M
