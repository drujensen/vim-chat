if vim.g.loaded_vim_chat then
  return
end
vim.g.loaded_vim_chat = true

-- Ghost-text autocmds and the Tab-to-accept keymap are always active; they
-- don't depend on vim.g.vim_chat having been assigned yet.
require("vimchat.completion").setup()

vim.api.nvim_create_user_command("VimChat", function(cmd_opts)
  require("vimchat").chat(cmd_opts.args)
end, { nargs = "*", desc = "Open/continue the vim-chat chat buffer, optionally seeding a prompt" })

vim.api.nvim_create_user_command("VimChatStop", function()
  require("vimchat").stop()
end, { desc = "Cancel an in-flight vim-chat request" })

vim.api.nvim_create_user_command("VimChatToggleCompletion", function()
  require("vimchat").toggle_completion()
end, { desc = "Toggle vim-chat ghost-text completion on/off" })

-- Deferred to VimEnter so that vim.g.vim_chat (typically assigned near the
-- bottom of init.lua, e.g. after lazy.nvim's setup() call sources this very
-- file) is guaranteed to already be in place before we read it.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local opts = require("vimchat.config").get()
    if opts.keymaps then
      vim.keymap.set({ "n", "x" }, "<leader>a", ":VimChat ", { noremap = true, desc = "vim-chat: open/prompt" })
      vim.keymap.set({ "n", "x" }, "<leader>c", ":VimChat<CR>", { noremap = true, desc = "vim-chat: continue" })
    end
  end,
})
