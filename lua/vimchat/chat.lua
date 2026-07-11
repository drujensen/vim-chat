local config = require("vimchat.config")
local endpoint = require("vimchat.endpoint")

local M = {}

local BUFFER_NAME = ">> vim-chat"

local job = nil

vim.api.nvim_create_autocmd("FileType", {
  pattern = "vimchat",
  callback = function()
    vim.cmd([[
      syntax match VimChatRole "^>>> system"
      syntax match VimChatRole "^>>> user"
      syntax match VimChatRole "^<<< assistant"
      highlight default link VimChatRole Title
    ]])
  end,
})

-- Appends `text` (which may contain embedded newlines) after the last
-- character of the buffer, without disturbing earlier content.
local function buf_append(bufnr, text)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local last_line = line_count - 1
  local last_line_text = vim.api.nvim_buf_get_lines(bufnr, last_line, last_line + 1, false)[1] or ""
  local last_col = #last_line_text
  local parts = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(bufnr, last_line, last_col, last_line, last_col, parts)
end

local function parse_messages(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local messages = {}
  for _, line in ipairs(lines) do
    if line:match("^>>> system") then
      table.insert(messages, { role = "system", content = "" })
    elseif line:match("^>>> user") then
      table.insert(messages, { role = "user", content = "" })
    elseif line:match("^<<< assistant") then
      table.insert(messages, { role = "assistant", content = "" })
    elseif #messages > 0 then
      messages[#messages].content = messages[#messages].content .. "\n" .. line
    end
  end
  for _, message in ipairs(messages) do
    message.content = vim.trim(message.content)
  end
  return messages
end

function M.get_chat_bufnr()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr):match(vim.pesc(BUFFER_NAME) .. "$") then
      return bufnr
    end
  end
  return nil
end

function M.open_chat_buffer()
  local bufnr = M.get_chat_bufnr()
  if bufnr then
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.api.nvim_set_current_buf(bufnr)
    end
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, BUFFER_NAME)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "vimchat"

  local opts = config.get()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    ">>> system",
    "",
    opts.chat.system_prompt,
    "",
    ">>> user",
    "",
  })

  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 0 })
  vim.cmd("startinsert")
  return bufnr
end

function M.stop()
  if job then
    job:kill(15)
    job = nil
    vim.notify("vim-chat: request cancelled", vim.log.levels.INFO)
  end
end

function M.send_message()
  local bufnr = M.open_chat_buffer()
  local messages = parse_messages(bufnr)

  if #messages == 0 or messages[#messages].content == "" then
    vim.notify("vim-chat: nothing to send", vim.log.levels.WARN)
    return
  end

  if job then
    vim.notify("vim-chat: a request is already in progress", vim.log.levels.WARN)
    return
  end

  buf_append(bufnr, "\n<<< assistant\n\n")
  vim.cmd("redraw")

  job = endpoint.request(
    messages,
    function(delta)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      buf_append(bufnr, delta)
      vim.cmd("redraw")
    end,
    function()
      job = nil
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      buf_append(bufnr, "\n\n>>> user\n\n")
      vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 0 })
      vim.cmd("redraw")
    end,
    function(err)
      job = nil
      vim.notify(err, vim.log.levels.ERROR)
    end
  )
end

-- Entry point for :VimChat [prompt]. With a prompt, seeds/continues the
-- buffer with that text and sends immediately. Without one, just opens
-- the buffer (or sends whatever the user already typed, for "continue").
function M.chat(prompt)
  local bufnr = M.open_chat_buffer()
  if prompt and prompt ~= "" then
    buf_append(bufnr, prompt)
  end
  M.send_message()
end

return M
