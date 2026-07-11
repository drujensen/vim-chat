if vim.g.loaded_vim_chat then
  return
end
vim.g.loaded_vim_chat = true

-- Ghost-text autocmds and the Tab-to-accept keymap are always active; they
-- don't depend on vim.g.vim_chat having been assigned yet.
require("vimchat.completion").setup()

vim.api.nvim_create_user_command("VimChat", function(cmd_opts)
  local selection = nil
  if cmd_opts.range > 0 then
    local lines = vim.api.nvim_buf_get_lines(0, cmd_opts.line1 - 1, cmd_opts.line2, false)
    selection = { text = table.concat(lines, "\n"), filetype = vim.bo.filetype }
  end
  require("vimchat").chat(cmd_opts.args, selection)
end, {
  nargs = "*",
  range = true, -- accepts a visual-mode range (e.g. `,a` after selecting text); no default when omitted
  desc = "Open/continue the vim-chat chat buffer, optionally seeding a prompt",
})

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
