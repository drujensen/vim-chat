# vim-chat

A pure-Lua Neovim plugin combining a streaming AI chat buffer with Copilot-style
inline ghost-text completion. No Python dependency, works with any
OpenAI-compatible `/v1/chat/completions` endpoint -- a hosted proxy, Ollama, or
anything else that speaks the same wire format.

## Features

- **Chat** (`:VimChat`) -- a scratch buffer using vim-ai-style `>>> user` /
  `<<< assistant` markers, with streamed (typewriter-style) responses.
- **Ghost-text completion** -- inline suggestions rendered as virtual text as
  you type, debounced so it only fires once you pause. Press `<Tab>` to accept,
  keep typing or move the cursor to dismiss. Never touches your real buffer
  content until you accept.
- No role/`.ini` system -- one configurable system prompt per feature.
- No file-based chat persistence in v1 -- history lives in the buffer for the
  session.

## Requirements

- Neovim >= 0.10 (uses `vim.system()` and inline virtual text)
- `curl` on your `PATH`

## Install (lazy.nvim)

```lua
{ 'drujensen/vim-chat' }
```

For local development before it's pushed:

```lua
{ dir = '~/workspace/vim/vim-chat' }
```

## Configuration

Set `vim.g.vim_chat` anywhere in your `init.lua` (all fields optional --
these are the defaults merged with your own proxy in mind):

```lua
vim.g.vim_chat = {
  endpoint_url = "https://ai.drujensen.com/v1/chat/completions",
  model = "qwen3.6", -- or "ornith"
  api_key_env = "DRUJENSEN_API_KEY", -- env var read for the Bearer token;
                                     -- leave unset/empty for Ollama (no auth)
  temperature = 0.2,
  keymaps = true, -- set false to skip the default <leader>a/<leader>c mappings

  chat = {
    system_prompt = "You are an expert pair programmer. Answer coding questions clearly and concisely. Use code blocks for code.",
    window_height = 15, -- height of the split the chat buffer opens in
  },

  completion = {
    enabled = true,
    debounce_ms = 400,
    max_context_lines_before = 50,
    max_context_lines_after = 20,
  },
}
```

Using local Ollama instead: point `endpoint_url` at
`http://localhost:11434/v1/chat/completions`, set `model` to whatever you've
pulled (e.g. `qwen3.6`), and leave `api_key_env` pointing at an unset variable
-- no Authorization header is sent when the key can't be resolved.

## Commands

| Command                     | Purpose                                            |
|------------------------------|-----------------------------------------------------|
| `:VimChat [prompt]`          | Open the chat buffer; with a prompt, sends it right away. With none, sends whatever you've already typed after the last `>>> user` marker. |
| `:VimChatStop`                | Cancel an in-flight request (chat or completion).  |
| `:VimChatToggleCompletion`    | Toggle ghost-text completion on/off for the session. |

## Default keymaps

Matches the `,a` / `,c` muscle memory from vim-ai:

| Mode      | Key         | Action                        |
|-----------|-------------|--------------------------------|
| n, x      | `<leader>a` | `:VimChat ` (type a prompt, Enter to send) |
| n, x      | `<leader>c` | `:VimChat<CR>` (continue the conversation) |
| i         | `<Tab>`     | Accept ghost-text suggestion, if one is showing; otherwise inserts a literal tab |

Set `vim.g.vim_chat.keymaps = false` to skip the `<leader>a`/`<leader>c` bindings and define your own.
