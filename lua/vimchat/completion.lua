local config = require("vimchat.config")
local endpoint = require("vimchat.endpoint")

local M = {}

local ns = vim.api.nvim_create_namespace("vimchat_ghost")

-- Per-buffer state: { timer, job, extmark_id, suggestion, anchor_row, anchor_col }
local state = {}

local function get_state(bufnr)
  if not state[bufnr] then
    state[bufnr] = {}
  end
  return state[bufnr]
end

local function clear_ghost(bufnr)
  local st = get_state(bufnr)
  if st.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, st.extmark_id)
    st.extmark_id = nil
    st.suggestion = nil
  end
end

local function cancel_job(bufnr)
  local st = get_state(bufnr)
  if st.job then
    st.job:kill(15)
    st.job = nil
  end
end

local function cancel_timer(bufnr)
  local st = get_state(bufnr)
  if st.timer then
    pcall(function()
      st.timer:stop()
    end)
    st.timer = nil
  end
end

-- Some models wrap completions in a markdown fence even when told not to.
local function strip_markdown_fence(text)
  local fenced = text:match("^```[%w_+-]*\n(.-)\n?```$")
  return fenced or text
end

-- Some models re-emit text that's already present immediately before the
-- cursor instead of only the continuation; strip that duplicate overlap.
local function trim_prefix_overlap(text, prefix)
  local last_line = vim.trim(prefix:match("([^\n]*)$") or "")
  if last_line ~= "" and text:sub(1, #last_line) == last_line then
    return text:sub(#last_line + 1)
  end
  return text
end

local function should_complete(bufnr)
  local opts = config.get().completion
  if not opts.enabled then
    return false
  end
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  if vim.bo[bufnr].filetype == "vimchat" then
    return false
  end
  return true
end

local function show_suggestion(bufnr, text)
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return
  end

  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end
  if vim.api.nvim_get_mode().mode ~= "i" then
    return
  end

  clear_ghost(bufnr)

  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local lines = vim.split(text, "\n", { plain = true })

  local st = get_state(bufnr)
  st.suggestion = text
  st.anchor_row = row
  st.anchor_col = col

  if #lines == 1 then
    st.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, {
      virt_text = { { lines[1], "Comment" } },
      virt_text_pos = "inline",
    })
  else
    local virt_lines = {}
    for i = 2, #lines do
      table.insert(virt_lines, { { lines[i], "Comment" } })
    end
    st.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, {
      virt_text = { { lines[1], "Comment" } },
      virt_text_pos = "inline",
      virt_lines = virt_lines,
    })
  end
end

local function request_completion(bufnr)
  if not should_complete(bufnr) then
    return
  end
  if vim.api.nvim_get_mode().mode ~= "i" then
    return
  end

  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end

  local opts = config.get().completion
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1], cursor[2]

  local before_start = math.max(0, row - 1 - opts.max_context_lines_before)
  local before_lines = vim.api.nvim_buf_get_lines(bufnr, before_start, row, false)
  if #before_lines > 0 then
    before_lines[#before_lines] = before_lines[#before_lines]:sub(1, col)
  end
  local prefix = table.concat(before_lines, "\n")

  local after_end = math.min(vim.api.nvim_buf_line_count(bufnr), row + opts.max_context_lines_after)
  local after_lines = vim.api.nvim_buf_get_lines(bufnr, row - 1, after_end, false)
  if #after_lines > 0 then
    after_lines[1] = after_lines[1]:sub(col + 1)
  end
  local suffix = table.concat(after_lines, "\n")

  local filetype = vim.bo[bufnr].filetype
  local user_content = string.format(
    "Filetype: %s\n\n--- code before cursor ---\n%s\n--- code after cursor ---\n%s",
    filetype ~= "" and filetype or "text",
    prefix,
    suffix
  )

  local messages = {
    { role = "system", content = opts.system_prompt },
    { role = "user", content = user_content },
  }

  local st = get_state(bufnr)
  cancel_job(bufnr)

  local accumulated = ""
  st.job = endpoint.request(messages, function(delta)
    accumulated = accumulated .. delta
  end, function()
    st.job = nil
    local suggestion = strip_markdown_fence(vim.trim(accumulated))
    suggestion = trim_prefix_overlap(suggestion, prefix)
    show_suggestion(bufnr, suggestion)
  end, function(err)
    st.job = nil
    vim.notify(err, vim.log.levels.WARN)
  end, { model = opts.model, temperature = opts.temperature })
end

local function on_activity(bufnr)
  if not should_complete(bufnr) then
    return
  end
  clear_ghost(bufnr)
  cancel_job(bufnr)
  cancel_timer(bufnr)

  local st = get_state(bufnr)
  local debounce_ms = config.get().completion.debounce_ms
  st.timer = vim.defer_fn(function()
    st.timer = nil
    request_completion(bufnr)
  end, debounce_ms)
end

-- Accepts the currently displayed suggestion (if any) by inserting it as
-- real buffer text. Returns true if a suggestion was accepted.
function M.accept()
  local bufnr = vim.api.nvim_get_current_buf()
  local st = get_state(bufnr)
  if not st.extmark_id or not st.suggestion then
    return false
  end

  local text = st.suggestion
  local row, col = st.anchor_row, st.anchor_col
  clear_ghost(bufnr)

  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, lines)

  local new_row = row + #lines - 1
  local new_col = (#lines == 1) and (col + #lines[1]) or #lines[#lines]
  vim.api.nvim_win_set_cursor(0, { new_row + 1, new_col })
  return true
end

function M.toggle()
  local opts = config.get().completion
  opts.enabled = not opts.enabled
  vim.notify("vim-chat: completion " .. (opts.enabled and "enabled" or "disabled"), vim.log.levels.INFO)
  if not opts.enabled then
    local bufnr = vim.api.nvim_get_current_buf()
    clear_ghost(bufnr)
    cancel_job(bufnr)
    cancel_timer(bufnr)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("vimchat_completion", { clear = true })

  vim.api.nvim_create_autocmd({ "TextChangedI", "CursorMovedI" }, {
    group = group,
    callback = function(args)
      on_activity(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function(args)
      clear_ghost(args.buf)
      cancel_job(args.buf)
      cancel_timer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(args)
      cancel_job(args.buf)
      cancel_timer(args.buf)
      state[args.buf] = nil
    end,
  })

  vim.keymap.set("i", "<Tab>", function()
    if M.accept() then
      return ""
    end
    return "\t"
  end, { expr = true, silent = true, desc = "vim-chat: accept ghost-text suggestion" })
end

return M
