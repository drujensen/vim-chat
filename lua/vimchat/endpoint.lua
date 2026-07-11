local config = require("vimchat.config")

local M = {}

local DATA_PREFIX = "data: "
local DONE_MARKER = "[DONE]"

-- Splits a growing buffer of SSE text on newlines, returning complete lines
-- and the leftover partial line (curl/libuv chunks can split mid-line).
local function drain_lines(buffer)
  local lines = {}
  local from = 1
  while true do
    local nl = buffer:find("\n", from, true)
    if not nl then
      break
    end
    table.insert(lines, buffer:sub(from, nl - 1))
    from = nl + 1
  end
  return lines, buffer:sub(from)
end

--- Streams a chat-completion request.
--- @param messages table list of {role=, content=} tables
--- @param on_delta function(text) called for each streamed content fragment
--- @param on_done function() called once the stream completes normally
--- @param on_error function(message) called on failure
--- @param overrides table|nil optional {model=, temperature=} to override config defaults (used by completion.lua to target a faster, non-reasoning model)
--- @return vim.SystemObj job handle (call :kill() to cancel)
function M.request(messages, on_delta, on_done, on_error, overrides)
  local opts = config.get()
  overrides = overrides or {}

  local body = vim.json.encode({
    model = overrides.model or opts.model,
    temperature = overrides.temperature or opts.temperature,
    stream = true,
    messages = messages,
  })

  -- Bounds only the connect phase, not the whole streamed response (which can
  -- legitimately run far longer than this for long answers/slow models).
  -- Without it, an unreachable/firewalled host hangs curl indefinitely with
  -- nothing to kill it -- common on restrictive Windows/corporate networks.
  local connect_timeout_s = math.max(1, math.floor((opts.request_timeout_ms or 30000) / 1000))

  local args = {
    "curl",
    "-sS",
    "-N",
    "--no-buffer",
    "--connect-timeout",
    tostring(connect_timeout_s),
    "-X",
    "POST",
    opts.endpoint_url,
    "-H",
    "Content-Type: application/json",
    "--data-binary",
    "@-",
  }

  local api_key = config.api_key()
  if api_key then
    table.insert(args, "-H")
    table.insert(args, "Authorization: Bearer " .. api_key)
  end

  local pending = ""
  local stderr_output = ""
  local finished = false

  local function finish_once(fn, ...)
    if finished then
      return
    end
    finished = true
    if fn then
      fn(...)
    end
  end

  local function handle_line(line)
    if line == "" then
      return
    end
    if line:sub(1, #DATA_PREFIX) ~= DATA_PREFIX then
      return
    end
    local payload = line:sub(#DATA_PREFIX + 1)
    if payload == DONE_MARKER then
      return
    end
    local ok, decoded = pcall(vim.json.decode, payload)
    if not ok or not decoded then
      return
    end
    local choice = decoded.choices and decoded.choices[1]
    local content = choice and choice.delta and choice.delta.content
    if content and content ~= "" then
      vim.schedule(function()
        on_delta(content)
      end)
    end
  end

  local job = vim.system(args, {
    stdin = body,
    text = true,
    stdout = function(err, data)
      if err then
        return
      end
      if not data then
        return
      end
      pending = pending .. data
      local lines
      lines, pending = drain_lines(pending)
      for _, line in ipairs(lines) do
        handle_line(line)
      end
    end,
    stderr = function(err, data)
      if not err and data then
        stderr_output = stderr_output .. data
      end
    end,
  }, function(result)
    if result.code ~= 0 and result.code ~= 143 then -- 143 = killed (SIGTERM), i.e. user cancelled
      vim.schedule(function()
        finish_once(on_error, "vim-chat: curl exited " .. result.code .. (stderr_output ~= "" and (": " .. stderr_output) or ""))
      end)
      return
    end
    vim.schedule(function()
      finish_once(on_done)
    end)
  end)

  return job
end

return M
