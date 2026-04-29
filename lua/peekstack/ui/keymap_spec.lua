local M = {}

---@class PeekstackKeymapSpec
---@field lhs string
---@field rhs string|function
---@field desc? string
---@field mode? string|string[]
---@field expr? boolean
---@field nowait? boolean
---@field silent? boolean
---@field remap? boolean

---@param spec PeekstackKeymapSpec
---@param bufnr integer
---@return table
local function build_opts(spec, bufnr)
  return {
    buffer = bufnr,
    nowait = spec.nowait ~= false,
    silent = spec.silent ~= false,
    desc = spec.desc,
    expr = spec.expr,
    remap = spec.remap,
  }
end

---Set a single buffer-local keymap from a spec.
---Skips empty/nil `lhs` entries so callers can pass user-configurable keys directly.
---@param bufnr integer
---@param spec PeekstackKeymapSpec
function M.set(bufnr, spec)
  if not spec.lhs or spec.lhs == "" then
    return
  end
  vim.keymap.set(spec.mode or "n", spec.lhs, spec.rhs, build_opts(spec, bufnr))
end

---Apply multiple specs on a buffer.
---@param bufnr integer
---@param specs PeekstackKeymapSpec[]
function M.apply(bufnr, specs)
  for _, spec in ipairs(specs) do
    M.set(bufnr, spec)
  end
end

---Drop specs with empty `lhs` and de-dup by `lhs`, keeping the last occurrence.
---Useful when user config produces overlapping shortcuts.
---@param specs PeekstackKeymapSpec[]
---@return PeekstackKeymapSpec[]
function M.normalize(specs)
  ---@type table<string, PeekstackKeymapSpec>
  local by_lhs = {}
  ---@type string[]
  local order = {}
  for _, spec in ipairs(specs) do
    if spec.lhs and spec.lhs ~= "" then
      if not by_lhs[spec.lhs] then
        order[#order + 1] = spec.lhs
      end
      by_lhs[spec.lhs] = spec
    end
  end

  local out = {}
  for _, lhs in ipairs(order) do
    out[#out + 1] = by_lhs[lhs]
  end
  return out
end

return M
