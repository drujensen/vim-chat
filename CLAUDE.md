# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

vim-chat is a pure-Lua Neovim plugin: a streaming AI chat buffer plus Copilot-style inline
ghost-text completion, both talking to any OpenAI-compatible `/v1/chat/completions` endpoint
(a hosted proxy, Ollama, etc). No Python dependency, no external plugin dependencies, no build
step -- Neovim loads the Lua files directly.

## Development

There is no test suite, linter config, or build tooling in this repo. To exercise changes,
symlink or point a local Neovim config at this directory (e.g. `{ dir = '~/workspace/vim/vim-chat' }`
in lazy.nvim) and drive it interactively:

- `:VimChat [prompt]` -- open/continue the chat buffer
- `:VimChatStop` -- cancel an in-flight request
- `:VimChatToggleCompletion` -- toggle ghost-text completion
- Insert-mode `<Tab>` -- accept a ghost-text suggestion

Requires Neovim >= 0.10 (`vim.system()`, inline virtual text) and `curl` on `PATH`.

## Architecture

Four modules under `lua/vimchat/`, each with a single responsibility:

- **`config.lua`** -- defaults merged with `vim.g.vim_chat` (and optional `setup(opts)` overrides)
  via `vim.tbl_deep_extend`. `M.get()` lazily builds this on first access, so config doesn't need
  `setup()` to be called explicitly. `M.api_key()` resolves the Bearer token from an env var
  (`api_key_env`), returning `nil` -- not an error -- when unset, since local Ollama needs no auth.
- **`endpoint.lua`** -- the only module that talks to the network. Shells out to `curl -N --no-buffer`
  via `vim.system()`, streams SSE (`data: {...}` lines), and invokes `on_delta`/`on_done`/`on_error`
  callbacks. Buffers partial lines across chunk boundaries (`drain_lines`). Accepts `overrides` for
  `model`/`temperature` so callers can target a different model than the configured default. Returns
  the `vim.SystemObj` job handle so callers can `:kill()` to cancel.
- **`chat.lua`** -- owns the chat scratch buffer (named `>> vim-chat`, filetype `vimchat`). Parses
  buffer content into `{role, content}` messages by scanning for `>>> system` / `>>> user` /
  `<<< assistant` marker lines (vim-ai-style), appends streamed deltas directly into the buffer via
  `nvim_buf_set_text`, and tracks one in-flight `job` at module scope (only one chat request at a time).
- **`completion.lua`** -- ghost-text engine. Debounces on `TextChangedI`/`CursorMovedI`, gathers
  before/after-cursor context (bounded by `max_context_lines_before/after`), sends it with a
  code-completion-specific system prompt, and renders the (non-streamed, accumulated) result as an
  extmark (`virt_text` for the first line, `virt_lines` for the rest). State is keyed per-buffer in
  a module-local `state` table. `<Tab>` is bound as a **plain keymap, not an expr-mapping** --
  expr-mappings run under textlock and can't mutate the buffer, which is required to accept a
  suggestion (see the comment in `completion.lua` near the keymap for the E565 rationale).
- **`init.lua`** -- thin public API (`chat`, `stop`, `toggle_completion`, `setup`) that other Lua
  code or `plugin/vim_chat.lua` calls into.
- **`plugin/vim_chat.lua`** -- entry point Neovim auto-loads. Registers ghost-text autocmds and the
  `<Tab>` keymap unconditionally at load time (they don't depend on config), but defers registering
  `<leader>a`/`<leader>c` keymaps to `VimEnter` so `vim.g.vim_chat` (usually set near the bottom of
  the user's `init.lua`) is guaranteed to be populated first.

### Key design points worth preserving

- **Two distinct models by design.** Chat defaults to a reasoning model; ghost-text completion
  defaults to a separate, faster non-reasoning model (`completion.model` in `config.lua`), because
  reasoning models stream several seconds of chain-of-thought before real content, blowing past the
  debounce window and getting cancelled by the next keystroke.
- **No file-based persistence.** Chat history lives only in the scratch buffer for the session --
  this is intentional, not a gap.
- **No role/`.ini` system.** One configurable `system_prompt` per feature (chat vs. completion), by
  design, unlike vim-ai's role files.
- Completion output is defensively cleaned (`strip_markdown_fence`, `trim_prefix_overlap`) because
  models frequently ignore instructions not to wrap output in markdown fences or not to repeat
  context already before the cursor.
