local M = {}

M.defaults = {
  endpoint_url = "https://ai.drujensen.com/v1/chat/completions",
  model = "qwen3.6",
  api_key_env = "DRUJENSEN_API_KEY",
  temperature = 0.2,
  request_timeout_ms = 30000,
  keymaps = true,
  chat = {
    system_prompt = "You are an expert pair programmer. Answer coding questions clearly and concisely. Use code blocks for code.",
  },
  completion = {
    enabled = true,
    -- Reasoning/"thinking" models (e.g. ornith, qwen3.6) stream several
    -- seconds of chain-of-thought before any real content, which blows past
    -- the debounce window and gets cancelled by the next keystroke. Ghost
    -- text needs a fast, non-reasoning model -- override here if yours
    -- differs from the default.
    model = "qwen3-coder:30b",
    temperature = 0.2,
    debounce_ms = 400,
    max_context_lines_before = 50,
    max_context_lines_after = 20,
    system_prompt = "You are a code completion engine embedded in an editor. Given the code immediately before and after the cursor, output ONLY the exact text to insert at the cursor to continue the code naturally. Never repeat existing code, never explain, never use markdown fences. If there's no reasonable completion, output nothing.",
  },
}

local options = nil

function M.setup(opts)
  options = vim.tbl_deep_extend("force", {}, M.defaults, vim.g.vim_chat or {}, opts or {})
  return options
end

function M.get()
  if not options then
    options = M.setup()
  end
  return options
end

-- Resolves the API key: explicit `api_key` string wins, otherwise the
-- configured env var. Returns nil (not an error) when neither is set --
-- local Ollama endpoints don't need auth at all.
function M.api_key()
  local opts = M.get()
  if opts.api_key and opts.api_key ~= "" then
    return opts.api_key
  end
  if opts.api_key_env and opts.api_key_env ~= "" then
    local value = os.getenv(opts.api_key_env)
    if value and value ~= "" then
      return value
    end
  end
  return nil
end

return M
