-- Type definitions for Peekstack
---@class PeekstackRange
---@field start { line: integer, character: integer }
---@field ["end"] { line: integer, character: integer }

---@class PeekstackLocation
---@field uri string
---@field range PeekstackRange
---@field text? string
---@field kind? integer
---@field provider string
---@field origin? PeekstackRange

---@class PeekstackDiagnosticExtmarks
---@field bufnr integer
---@field ns integer
---@field ids integer[]

---@class PeekstackDisplayTextOpts
---@field path_base? "repo"|"cwd"|"absolute"
---@field max_width? integer

---@class PeekstackSessionItem
---@field uri string
---@field range PeekstackRange
---@field title string
---@field provider string
---@field ts integer

---@class PeekstackSessionMeta
---@field created_at integer
---@field updated_at integer

---@class PeekstackSession
---@field items PeekstackSessionItem[]
---@field meta PeekstackSessionMeta

---@class PeekstackPopupModel
---@field id integer
---@field bufnr integer
---@field source_bufnr integer
---@field winid integer
---@field location PeekstackLocation
---@field diagnostics? PeekstackDiagnosticExtmarks
---@field origin { winid: integer, bufnr: integer, row: integer, col: integer }
---@field origin_bufnr integer
---@field origin_is_popup boolean
---@field title string
---@field pinned boolean
---@field buffer_mode "copy"|"source"
---@field line_offset integer
---@field created_at integer
---@field last_active_at integer
---@field ephemeral boolean
---@field win_opts table

---@class PeekstackStackModel
---@field root_winid integer
---@field popups PeekstackPopupModel[]
---@field history PeekstackHistoryEntry[]
---@field layout_state any
---@field focused_id integer?

---@class PeekstackUserEventData
---@field event string
---@field popup_id integer
---@field winid integer
---@field bufnr integer
---@field location PeekstackLocation
---@field provider string
---@field root_winid integer
---@field extra table

---@class PeekstackInlinePreviewState
---@field bufnr integer
---@field extmark_id integer
---@field target_uri string
---@field created_at integer
---@field request_id integer

---@class PeekstackTreesitterContextOpts
---@field enabled boolean
---@field max_depth integer
---@field separator string
---@field node_types table<string, string[]>

---@class PeekstackTitleChunk
---@field [1] string
---@field [2]? string

---@class PeekstackStoreData
---@field version integer
---@field sessions table<string, PeekstackSession>

---@class PeekstackPicker
---@field pick fun(locations: PeekstackLocation[], opts?: table, cb: fun(location: PeekstackLocation))

---@class PeekstackHistoryEntry
---@field location PeekstackLocation
---@field title? string
---@field pinned boolean
---@field buffer_mode "copy"|"source"
---@field source_bufnr? integer
---@field created_at integer
---@field closed_at integer
---@field restore_index? integer

---@class PeekstackProviderContext
---@field winid integer
---@field bufnr integer
---@field source_bufnr integer?
---@field popup_id integer?
---@field buffer_mode "copy"|"source"|nil
---@field line_offset integer
---@field position { line: integer, character: integer }
---@field root_winid integer
---@field from_popup boolean

-- Config type definitions

---@class PeekstackConfigLayoutOffset
---@field row integer
---@field col integer

---@class PeekstackConfigLayoutShrink
---@field w integer
---@field h integer

---@class PeekstackConfigLayoutMinSize
---@field w integer
---@field h integer

---@class PeekstackConfigLayout
---@field style "stack"|"cascade"|"single"
---@field offset PeekstackConfigLayoutOffset
---@field shrink PeekstackConfigLayoutShrink
---@field min_size PeekstackConfigLayoutMinSize
---@field max_ratio number
---@field zindex_base integer

---@class PeekstackConfigTitleContext
---@field enabled boolean
---@field max_depth integer
---@field separator string
---@field node_types table<string, string[]>

---@class PeekstackConfigTitleIcons
---@field enabled boolean
---@field map table<string, string>

---@class PeekstackConfigTitle
---@field enabled boolean
---@field format string
---@field icons PeekstackConfigTitleIcons
---@field context PeekstackConfigTitleContext

---@class PeekstackConfigPath
---@field base "repo"|"cwd"|"absolute"
---@field max_width integer

---@class PeekstackConfigInlinePreview
---@field enabled boolean
---@field max_lines integer
---@field hl_group string
---@field close_events string[]

---@class PeekstackConfigQuickPeek
---@field close_events string[]

---@class PeekstackConfigAutoClose
---@field enabled boolean
---@field idle_ms integer
---@field check_interval_ms integer
---@field ignore_pinned boolean

---@class PeekstackConfigPopupSource
---@field prevent_auto_close_if_modified boolean
---@field confirm_on_close boolean

---@class PeekstackConfigPopupHistory
---@field max_items integer
---@field restore_position "top"|"original"

---@class PeekstackConfigPopup
---@field editable boolean
---@field buffer_mode "copy"|"source"
---@field source PeekstackConfigPopupSource
---@field history PeekstackConfigPopupHistory
---@field auto_close PeekstackConfigAutoClose

---@class PeekstackConfigFeedback
---@field highlight_origin_on_close boolean

---@class PeekstackConfigPromote
---@field close_popup boolean

---@class PeekstackConfigKeys
---@field close string
---@field focus_next string
---@field focus_prev string
---@field promote_split string
---@field promote_vsplit string
---@field promote_tab string
---@field toggle_stack_view string

---@class PeekstackConfigUI
---@field layout PeekstackConfigLayout
---@field title PeekstackConfigTitle
---@field path PeekstackConfigPath
---@field inline_preview PeekstackConfigInlinePreview
---@field quick_peek PeekstackConfigQuickPeek
---@field popup PeekstackConfigPopup
---@field feedback PeekstackConfigFeedback
---@field promote PeekstackConfigPromote
---@field keys PeekstackConfigKeys

---@class PeekstackConfigPickerBuiltin
---@field preview_lines integer

---@class PeekstackConfigPicker
---@field backend "builtin"|"telescope"|"fzf-lua"|"snacks"
---@field builtin PeekstackConfigPickerBuiltin

---@class PeekstackConfigProviderEntry
---@field enable boolean

---@class PeekstackConfigProviderMarks
---@field enable boolean
---@field scope "buffer"|"global"|"all"
---@field include string
---@field include_special boolean

---@class PeekstackConfigProviders
---@field lsp PeekstackConfigProviderEntry
---@field diagnostics PeekstackConfigProviderEntry
---@field file PeekstackConfigProviderEntry
---@field marks PeekstackConfigProviderMarks

---@class PeekstackConfigPersistSession
---@field default_name string
---@field prompt_if_missing boolean

---@class PeekstackConfigPersistAuto
---@field enabled boolean
---@field session_name string
---@field restore boolean
---@field save boolean
---@field restore_if_empty boolean
---@field debounce_ms integer
---@field save_on_leave boolean

---@class PeekstackConfigPersist
---@field enabled boolean
---@field max_items integer
---@field session PeekstackConfigPersistSession
---@field auto PeekstackConfigPersistAuto

---@class PeekstackConfig
---@field ui PeekstackConfigUI
---@field picker PeekstackConfigPicker
---@field providers PeekstackConfigProviders
---@field persist PeekstackConfigPersist

return {}
