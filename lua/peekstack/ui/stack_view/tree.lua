local M = {}

---Sort visible items in DFS tree order so children appear right after their parent.
---Items without a visible parent are treated as roots and keep their relative order.
---@param items PeekstackPopupModel[]
---@return PeekstackPopupModel[]
function M.sort(items)
  ---@type table<integer, PeekstackPopupModel>
  local by_id = {}
  for _, popup in ipairs(items) do
    by_id[popup.id] = popup
  end

  ---@type table<integer, PeekstackPopupModel[]>
  local children = {}
  ---@type PeekstackPopupModel[]
  local roots = {}

  for _, popup in ipairs(items) do
    local pid = popup.parent_popup_id
    if pid and by_id[pid] then
      if not children[pid] then
        children[pid] = {}
      end
      table.insert(children[pid], popup)
    else
      table.insert(roots, popup)
    end
  end

  ---@type PeekstackPopupModel[]
  local result = {}
  ---@type table<integer, boolean>
  local visiting = {}

  ---@param node PeekstackPopupModel
  local function dfs(node)
    if visiting[node.id] then
      return
    end
    visiting[node.id] = true
    table.insert(result, node)
    if children[node.id] then
      for _, child in ipairs(children[node.id]) do
        dfs(child)
      end
    end
  end

  for _, root in ipairs(roots) do
    dfs(root)
  end

  -- Safety fallback: keep any unvisited items (e.g. cyclic/invalid parent links)
  -- so entries are never dropped from the stack view.
  for _, popup in ipairs(items) do
    if not visiting[popup.id] then
      dfs(popup)
    end
  end

  return result
end

---@param items PeekstackPopupModel[]
---@return table<integer, PeekstackPopupModel>
local function visible_popup_by_id(items)
  ---@type table<integer, PeekstackPopupModel>
  local by_id = {}
  for _, popup in ipairs(items) do
    by_id[popup.id] = popup
  end
  return by_id
end

---@param visible PeekstackPopupModel[]
---@return table<integer, string>
function M.guide_by_id(visible)
  ---@type table<integer, string>
  local guides = {}
  local by_id = visible_popup_by_id(visible)

  ---@type table<integer, integer[]>
  local children_by_parent = {}

  -- Children order follows `visible` (stack push order).
  -- If sorting is added, children_by_parent must be rebuilt in display order.
  for _, popup in ipairs(visible) do
    local parent_id = popup.parent_popup_id
    if parent_id and by_id[parent_id] then
      if not children_by_parent[parent_id] then
        children_by_parent[parent_id] = {}
      end
      table.insert(children_by_parent[parent_id], popup.id)
    end
  end

  ---@type table<integer, integer>
  local sibling_pos = {}
  ---@type table<integer, integer>
  local sibling_total = {}
  for _, children in pairs(children_by_parent) do
    local total = #children
    for idx, child_id in ipairs(children) do
      sibling_pos[child_id] = idx
      sibling_total[child_id] = total
    end
  end

  ---@type table<integer, integer[]>
  local chain_cache = {}

  ---@param popup_id integer
  ---@param visiting table<integer, boolean>
  ---@return integer[]
  local function visible_chain(popup_id, visiting)
    local cached = chain_cache[popup_id]
    if cached then
      return cached
    end
    if visiting[popup_id] then
      return {}
    end

    local popup = by_id[popup_id]
    if not popup then
      return {}
    end

    local parent_id = popup.parent_popup_id
    if not parent_id or not by_id[parent_id] then
      local root_chain = { popup_id }
      chain_cache[popup_id] = root_chain
      return root_chain
    end

    visiting[popup_id] = true
    local parent_chain = visible_chain(parent_id, visiting)
    visiting[popup_id] = nil

    local chain = {}
    for _, id in ipairs(parent_chain) do
      table.insert(chain, id)
    end
    table.insert(chain, popup_id)
    chain_cache[popup_id] = chain
    return chain
  end

  for _, popup in ipairs(visible) do
    local chain = visible_chain(popup.id, {})
    local depth = #chain - 1
    if depth > 0 then
      local segments = {}
      for level = 1, depth - 1 do
        local path_child_id = chain[level + 1]
        local pos = sibling_pos[path_child_id] or 1
        local total = sibling_total[path_child_id] or 1
        segments[#segments + 1] = (pos < total) and "│ " or "  "
      end
      local pos = sibling_pos[popup.id] or 1
      local total = sibling_total[popup.id] or 1
      segments[#segments + 1] = (pos < total) and "├ " or "└ "
      guides[popup.id] = table.concat(segments)
    else
      guides[popup.id] = ""
    end
  end

  return guides
end

return M
