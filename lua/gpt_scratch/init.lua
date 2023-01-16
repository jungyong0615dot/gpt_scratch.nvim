local M = {}

local Job = require "plenary.job"
local curl = require "custom_curl"
local Path = require "plenary.path"
local async = require "plenary.async"
local actions = require "telescope.actions"
local actions_state = require "telescope.actions.state"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local previewers = require "telescope.previewers"
local conf = require("telescope.config").values
local ts_utils = require "telescope.utils"
local defaulter = ts_utils.make_default_callable

local API_KEY = os.getenv "OPENAI_API_KEY"

local cmd_suffix = {
  Default = { "" },
  Rephrase = { "Rewrite the following sentences using formal language:" },
  Summarize = { "Summarize this for a second-grade student:" },
  Chat = { "" },
  QA = { "Q:", "A:" },
}

local cmd_opts = {
  Default = {
    model = "text-davinci-003",
    temperature = 0,
    max_tokens = 256,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
    stop = nil,
  },
  Rephrase = {
    model = "text-davinci-003",
    temperature = 0.7,
    max_tokens = 256,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
    stop = nil,
  },
  Summarize = {
    model = "text-davinci-003",
    temperature = 0.7,
    max_tokens = 256,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
    stop = nil,
  },
  Chat = {
    model = "text-davinci-003",
    temperature = 0.9,
    max_tokens = 256,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0.6,
    stop = { " Human:", " AI:" },
  },
  QA = {
    model = "text-davinci-003",
    temperature = 0,
    max_tokens = 256,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
    stop = { "\n" },
  },
  Command = {
    model = "text-davinci-003",
    temperature = 0,
    max_tokens = 256,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
  },
}

local all_cmds = {
  { text = "Reword using simpler language:", opts = "Rephrase" },
  { text = "Rephrase in a conversational tone:", opts = "Rephrase" },
  { text = "Make this understandable for a fifth grader:", opts = "Rephrase" },
  { text = "Summarize this for a second-grade student:", opts = "Rephrase" },
  { text = "Rewrite using highly sophisticated language:", opts = "Rephrase" },
  { text = "Correct this to standard English:", opts = "Rephrase" },
  { text = "Convert following code:", opts = "Command" },
  { text = "Convert following vimscript to lua:", opts = "Command" },
}

function table.append(t1, t2)
  for i = 1, #t2 do
    t1[#t1 + 1] = t2[i]
  end
  return t1
end

M.open_search_prompts = function(cmd)
  pickers
    .new({}, {
      prompt_title = "Buffers",
      finder = finders.new_table {
        results = all_cmds,
        entry_maker = function(entry)
          return {
            value = entry.text,
            display = entry.text,
            ordinal = entry.text,
            opts = entry.opts,
          }
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = actions_state.get_selected_entry()
          actions.close(prompt_bufnr)

          local width = vim.api.nvim_get_option "columns"
          local height = vim.api.nvim_get_option "lines"
          local win_height = math.ceil(height * 0.7 - 4)
          local win_width = math.ceil(width * 0.7)
          local row = math.ceil((height - win_height) / 2 - 1)
          local col = math.ceil((width - win_width) / 2)
          local buf = vim.api.nvim_create_buf(true, true)

          vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { selection.display, "" })

          local _ = vim.api.nvim_open_win(buf, true, {
            style = "minimal",
            relative = "editor",
            row = row,
            col = col,
            width = win_width,
            height = win_height,
            border = "rounded",
          })
          vim.w.is_floating_scratch = true
          vim.b[buf].current_ai = selection.opts
          vim.cmd "set wrap"
        end)
        return true
      end,
    })
    :find()
end

M.open_floating_ai = function(cmd)
  local width = vim.api.nvim_get_option "columns"
  local height = vim.api.nvim_get_option "lines"
  local win_height = math.ceil(height * 0.7 - 4)
  local win_width = math.ceil(width * 0.7)
  local row = math.ceil((height - win_height) / 2 - 1)
  local col = math.ceil((width - win_width) / 2)
  local buf = vim.api.nvim_create_buf(true, true)

  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, cmd_suffix[cmd])

  local _ = vim.api.nvim_open_win(buf, true, {
    style = "minimal",
    relative = "editor",
    row = row,
    col = col,
    width = win_width,
    height = win_height,
    border = "rounded",
  })
  vim.w.is_floating_scratch = true
  vim.b[buf].current_ai = cmd
  return buf
end

M.complete = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local cmd = vim.b.current_ai or "Default"

  local url_info = "https://api.openai.com/v1/completions"
  local buf_contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local params = {
    prompt = table.concat(buf_contents, "\n"),
    model = cmd_opts[cmd].model,
    temperature = cmd_opts[cmd].temperature,
    max_tokens = cmd_opts[cmd].max_tokens,
    top_p = cmd_opts[cmd].top_p,
    frequency_penalty = cmd_opts[cmd].frequency_penalty,
    presence_penalty = cmd_opts[cmd].presence_penalty,
    -- stop = cmd_opts[cmd].stop,
  }

  local post_body = vim.json.encode(params)

  -- vim.pretty_print(post_body)

  curl.post(url_info, {
    headers = {
      Authorization = "Bearer " .. API_KEY,
      ["Content-Type"] = "application/json",
    },
    body = post_body,
    callback = vim.schedule_wrap(function(out)
      -- resp_body = cjson.decode(out.body)
      -- decode using vim.json
      resp_body = vim.json.decode(out.body)
      -- vim.pretty_print(resp_body)
      resp_text = resp_body["choices"][1]["text"]

      vim.api.nvim_buf_set_lines(bufnr, #buf_contents + 1, -1, false, vim.split(resp_text, "\n"))
    end),
  }):start()
end

return M
