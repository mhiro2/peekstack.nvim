# peekstack.nvim

Exploration-first peek stack for Neovim — stack LSP/diagnostics/files/grep results without losing context.

peekstack.nvim keeps your exploration flow intact by stacking “peek” windows. You can move through the stack, then promote only the results you care about into splits or tabs.

## 💡 Why peekstack.nvim?

Most peek workflows are built around viewing one thing at a time.
peekstack.nvim focuses on preserving the _trail_ of your exploration.

- **Continuity**: chase LSP/diagnostics/grep without breaking flow
- **Context-preserving**: move back/forward in a stack of popups
- **Promote when needed**: elevate only the interesting results to splits/tabs
- **Session persistence**: save and restore exploration sessions

## ✨ Features

### Core

- 🧭 **Peek stack UI**: stack / cascade / single layouts
- 🧱 **Stack view**: list popups, focus, pin, rename, reorder, history
- 🔍 **Providers**: LSP / diagnostics / file / marks
- 🚀 **Promote**: fast split/tab promotion
- 🧷 **Inline + quick peek**: inline preview or ephemeral popups
- 🧩 **Buffer modes**: copy (default) / source

### Optional

- 🔎 **ripgrep integration**: `rg`-based grep search
- 🧺 **Picker integration**: builtin / telescope / fzf-lua / snacks.nvim
- 💾 **Persist**: save/restore sessions + auto save/restore
- 🧹 **Auto close**: close stale popups by idle time

## 📦 Requirements

- Neovim ≥ 0.10
- `rg` (only if you use `grep.search`)
- Optional: `telescope.nvim` / `fzf-lua` / `snacks.nvim` (if you switch picker backends)
- Optional: Tree-sitter parsers (if you enable `ui.title.context`; Neovim bundles the runtime, but parsers are separate)

## 🚀 Installation

Using lazy.nvim:

```lua
{
  "mhiro2/peekstack.nvim",
  config = function()
    local peekstack = require("peekstack")
    peekstack.setup({
      -- Optional: enable additional providers
      providers = {
        marks = { enable = true },  -- browse vim marks
      },
    })

    -- LSP: peek at definitions and references
    vim.keymap.set("n", "pd", function() peekstack.peek.definition() end)
    vim.keymap.set("n", "pr", function() peekstack.peek.references() end)

    -- Diagnostics & files: peek at diagnostics or files under cursor
    vim.keymap.set("n", "pl", function() peekstack.peek.diagnostics_cursor() end)
    vim.keymap.set("n", "pf", function() peekstack.peek.file_under_cursor() end)

    -- Marks: browse buffer marks (requires marks provider enabled)
    vim.keymap.set("n", "pm", function() peekstack.peek.marks_buffer() end)
  end,
}
```

## 🧭 Usage

```lua
-- Call by provider name
require("peekstack").peek("lsp.definition")
require("peekstack").peek("diagnostics.under_cursor")
require("peekstack").peek("file.under_cursor")
require("peekstack").peek("marks.buffer")

-- Inline preview (no stack)
require("peekstack").peek.definition({ mode = "inline" })

-- Quick peek (temporary, no stack)
require("peekstack").peek.references({ mode = "quick" })
```

Built-in provider names:
`lsp.definition`, `lsp.implementation`, `lsp.references`, `lsp.type_definition`, `lsp.declaration`,
`diagnostics.under_cursor`, `diagnostics.in_buffer`, `file.under_cursor`, `grep.search`, `marks.buffer`,
`marks.global`, `marks.all` (marks require their provider enabled; `grep.search` requires `rg`).

## 💻 Commands

- `:PeekstackStack` — open the stack view panel
- `:PeekstackSaveSession` — save current stack (persist enabled)
- `:PeekstackRestoreSession` — restore a saved session
- `:PeekstackListSessions` — list all saved sessions
- `:PeekstackDeleteSession {name}` — delete a saved session by name
- `:PeekstackRestorePopup` — restore the last closed popup (undo close)
- `:PeekstackRestoreAllPopups` — restore all closed popups
- `:PeekstackCloseAll` — close all popups in the current stack
- `:PeekstackHistory` — show popup history and select to restore
- `:PeekstackQuickPeek [provider]` — quick peek without stacking (default: `lsp.definition`, accepts any registered provider)

## ⌨️ Keymaps

Defaults inside popup windows:

- `q` — close
- `<C-j>` — focus next popup
- `<C-k>` — focus previous popup
- `<C-x>` — promote to horizontal split
- `<C-v>` — promote to vertical split
- `<C-t>` — promote to new tab
- `<leader>os` — open stack view

Defaults in stack view:

- `<CR>` — focus selected popup
- `dd` — close selected popup
- `u` — undo close (restore last)
- `U` — restore all closed popups
- `H` — history list (select to restore)
- `r` — rename
- `p` — pin
- `/` — filter
- `J/K` — move item down/up
- `?` — help
- `q` — close

## ⚙️ Configuration

Configure via `require("peekstack").setup({ ... })`.

<details><summary>Default Settings</summary>

```lua
{
  ui = {
    layout = {
      style = "stack",
      offset = { row = 1, col = 4 },
      shrink = { w = 4, h = 2 },
      min_size = { w = 60, h = 12 },
      max_ratio = 0.65,
      zindex_base = 50,
    },
    title = {
      enabled = true,
      format = "{provider} · {path}:{line}{context}",
      breadcrumbs = true,
      context = {
        enabled = false,
        max_depth = 5,
        separator = " • ",
        node_types = {},
      },
    },
    path = {
      base = "repo", -- "repo" | "cwd" | "absolute"
      max_width = 80,
    },
    inline_preview = {
      enabled = true,
      max_lines = 10,
      hl_group = "PeekstackInlinePreview",
      close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
    },
    quick_peek = {
      close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
    },
    popup = {
      editable = false,
      buffer_mode = "copy",          -- "copy" | "source"
      source = {
        prevent_auto_close_if_modified = true,
        confirm_on_close = true,
      },
      history = {
        max_items = 50,
        restore_position = "top",    -- "top" | "original"
      },
      auto_close = {
        enabled = false,
        idle_ms = 300000,
        check_interval_ms = 60000,
        ignore_pinned = true,
      },
    },
    feedback = {
      highlight_origin_on_close = true,
    },
    promote = {
      close_popup = true,
    },
    keys = {
      close = "q",
      focus_next = "<C-j>",
      focus_prev = "<C-k>",
      promote_split = "<C-x>",
      promote_vsplit = "<C-v>",
      promote_tab = "<C-t>",
      toggle_stack_view = "<leader>os",
    },
  },
  picker = {
    backend = "builtin",
    builtin = {
      preview_lines = 1,
    },
  },
  providers = {
    lsp = { enable = true },
    diagnostics = { enable = true },
    file = { enable = true },
    marks = {
      enable = false,
      scope = "all", -- "buffer" | "global" | "all"
      include = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
      include_special = false,
    },
  },
  persist = {
    enabled = false,
    max_items = 200,
    session = {
      default_name = "default",
      prompt_if_missing = true,
    },
    auto = {
      enabled = false,
      session_name = "auto",
      restore = true,
      save = true,
      restore_if_empty = true,
      debounce_ms = 1000,
      save_on_leave = true,
    },
  },
}
```

</details>

## 🧺 Picker backends (telescope / fzf-lua / snacks.nvim)

peekstack uses a picker when multiple locations are returned (e.g. references). The
default backend is `builtin`. To use an external picker, install the plugin and set
`picker.backend` to one of: `telescope`, `fzf-lua`, `snacks`.

```lua
{
  "mhiro2/peekstack.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim", -- or "ibhagwan/fzf-lua" / "folke/snacks.nvim"
  },
  config = function()
    require("peekstack").setup({
      picker = { backend = "telescope" },
    })
  end,
}
```

If the chosen plugin is not installed, a warning is shown and the picker will not open.

## 💾 Persist sessions

When `persist.enabled = true`, `PeekstackSaveSession` uses `persist.session.default_name`
if you do not pass a name. If `persist.session.prompt_if_missing = true`, you'll be prompted
for a name instead of using the default.

> [!WARNING]
> Persistence scope is fixed to the current git repository.

### Auto persist (optional)

When `persist.auto.enabled = true`, peekstack can automatically restore and save a session:

- **Restore** on `VimEnter` / `DirChanged` (only when the stack is empty if `restore_if_empty = true`)
- **Save** on `PeekstackPush` / `PeekstackClose` / `PeekstackRestorePopup` with a debounce
- **Save on leave** on `VimLeavePre` if `save_on_leave = true`

Auto persist only runs inside a git repository and uses `scope = "repo"` internally. Make sure
`persist.enabled = true` as well.

## 🪟 Popup buffer modes

`ui.popup.buffer_mode` controls how popups are backed:

- **copy** (default): scratch buffer with copied lines; editing is controlled by `ui.popup.editable`
- **source**: uses the real source buffer; useful for editing, with safety options in
  `ui.popup.source` (`confirm_on_close`, `prevent_auto_close_if_modified`)

## 🧪 Health

Run `:checkhealth peekstack` to verify requirements.

## 📚 Documentation

See `:help peekstack` for complete documentation.

## 📄 License

MIT License. See [LICENSE](./LICENSE).
