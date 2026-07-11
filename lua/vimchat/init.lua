local config = require("vimchat.config")
local chat = require("vimchat.chat")
local completion = require("vimchat.completion")

local M = {}

--- Optional explicit setup, e.g. from a lazy.nvim `config` function. Merges
--- `opts` over `vim.g.vim_chat` over the built-in defaults. If you configure
--- purely via `vim.g.vim_chat` in your init.lua, calling this is optional --
--- the first use of the plugin lazily builds the same merged config from
--- whatever `vim.g.vim_chat` holds at that point (ghost-text autocmds and
--- commands are always registered by plugin/vim_chat.lua regardless).
function M.setup(opts)
  config.setup(opts)
end

M.chat = chat.chat
M.stop = chat.stop
M.toggle_completion = completion.toggle

return M
