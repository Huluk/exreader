-- minimum neovim version: 0.7

-------------------- VARIABLES -----------------------------

local fmt = string.format

local options = {
  speak_command = 'espeak',
  number = 1,
}

local M = {}

-------------------- PUBLIC --------------------------------
function M.speak(str)
  os.execute(fmt('%s %s', options.speak_command, vim.fn.shellescape(str)))
end

function M.print(start_row, end_row)
  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
  -- TODO follow options.number
  local output = table.concat(lines, '.\n')
  M.speak(output)
end

function M.print_cmd(args)
  -- TODO handle ex flags
  if next(args.fargs) == nil then
    M.print(args.line1, args.line2)
    return
  end

  local line_count = tonumber(args.fargs[1]) or 1
  local start_row
  if args.range == 2 then
    start_row = args.line2
  else
    start_row = args.line1
  end
  M.print(start_row, start_row + line_count - 1)
end

-------------------- COMMANDS ------------------------------
vim.api.nvim_create_user_command('P', M.print_cmd, {
  desc = 'Voice-print [range] lines.',
  nargs = '*',
  range = true,
})

------------------------------------------------------------
return M
