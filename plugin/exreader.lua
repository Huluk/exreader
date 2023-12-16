-- minimum neovim version: 0.7
--
-- Numeric variables are called 'row' when 0-indexed, and 'line' when 1-indexed.
-- There is a lot of confusion around indices here:
-- • Vim uses 1-indexed rows and columns.
-- • Neovim-lua uses 0-indexed rows and columns.
-- • Lua uses 1-indexed lists and strings, and end-inclusive ranges.
-- • Treesitter uses 0-indexed rows and columns, and end-exclusive ranges.


-------------------- VARIABLES -----------------------------

local fmt = string.format
local ts_utils = require 'nvim-treesitter.ts_utils'

local options = {
  speak_command = 'espeak --punct',
  number = 1, -- 0: never, 1: follow 'number', 2: always
  ssml_breakformat = '<break /> ',
  fallback_breakformat = '.\n',
  numberformat = 'line %d%s',
  relativenumber = 0, -- 0: absolute, 1: follow 'relativenumber', 2: always
  relativenumberformat = 'newline %d%s',
  -- explicit number (via ex flag '#') triggers:
  -- 0: nonumber, 1: number, 2: relativenumber
  explicitnumber = 1,
  use_ssml = 1, -- use Speech Synthesis Markup Language.
  use_treesitter = 1,
}

local M = {}

-------------------- HELPERS -------------------------------

-- following TSNode convention, end_row is inclusive, end_col exclusive.
-- end_col = -1 means until end of line.
local function buf_text_with_nodes(start_row, start_col, end_row, end_col)
  if start_row > end_row or start_row < 0 or start_col < 0 or
    (start_row == end_row and end_col >= 0 and start_col >= end_col) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
  if #lines == 0 then
    return
  elseif #lines < 1 + end_row - start_row then
    end_row = start_row + #lines - 1
  end
  if end_col < 0 then
    local last_line = lines[1 + end_row - start_row]
    end_col = last_line and #last_line - 1 or 0
  end

  local function overlapping_named_descendant(node)
    return node:named_descendant_for_range(
      start_row, start_col, end_row, end_col)
  end

  local printed_row = start_row
  local printed_col = start_col -- exclusive

  local output = {}

  local function insert_row(node, col) -- exclusive
    table.insert(output, {
      text = lines[1 + printed_row - start_row]:sub(printed_col + 1, col),
      node = node,
      row = printed_row,
    })
  end

  local function ensure_output_until(row, col, node) -- col exclusive
    if row < printed_row or (row == printed_row and col <= printed_col) then
      return
    end
    if row > end_row then
      row = end_row
      col = end_col + 1
    end
    while printed_row < row do
      insert_row(node)
      printed_row = printed_row + 1
      printed_col = 0
    end
    if row < printed_row or col <= printed_col then
      return
    end
    if row == end_row then
      col = math.min(col, end_col + 1)
    end
    insert_row(node, col)
    printed_col = col
  end

  local function add_to_output(node, surrounding_named_node)
    if node:named() then
      surrounding_named_node = node
    end
    for child in node:iter_children() do
      local child_row1, child_col1, _ = child:start()
      ensure_output_until(child_row1, child_col1, surrounding_named_node)
      add_to_output(child, surrounding_named_node)
    end
    local row2, col2, _ = node:end_()
    if node:named() then
      ensure_output_until(row2, col2, node)
    end
  end

  local function add_tree_to_output(tree)
    local node = overlapping_named_descendant(tree:root())
    if node then
      local row, col, _ = node:start()
      ensure_output_until(row, col)
      add_to_output(node)
    end
  end

  local success, parser = pcall(function()
    return vim.treesitter.get_parser()
  end)

  if success then
    for _,tree in ipairs(parser:parse()) do
      add_tree_to_output(tree)
    end
  end
  ensure_output_until(end_row, end_col + 1)

  return output
end

local function breakformat()
  if options.use_ssml then
    return options.ssml_breakformat
  else
    return options.fallback_breakformat
  end
end

local function none_formatter(_, _) return '' end

local function linenumber_formatter(number, offset)
  return fmt(options.numberformat, number + offset, breakformat())
end

local function relativenumber_formatter(number, offset)
  if offset == 0 then
    return ''
  else
    return fmt(options.relativenumberformat, offset, breakformat())
  end
end

local function get_prefix_formatter(number_flag)
  if number_flag then
    if options.explicitnumber <= 0 then
      return none_formatter
    elseif options.explicitnumber >= 2 then
      return relativenumber_formatter
    else
      return linenumber_formatter
    end
  end

  if number_flag == false then return '' end -- explicit false case.

  if options.relativenumber >= 2 or (
    options.relativenumber == 1 and
      vim.api.nvim_get_option_value('relativenumber', {})) then
    return relativenumber_formatter
  elseif options.number >= 2 or (
    options.number == 1 and vim.api.nvim_get_option_value('number', {})) then
    return linenumber_formatter
  end
  return none_formatter
end

local function type_format(type)
  return type:gsub('_', ' ')
end

-------------------- PUBLIC --------------------------------

function M.speak(str)
  local args = options.use_ssml and '-m' or ''
  local input = vim.fn.shellescape(str)
  os.execute(fmt('%s %s %s', options.speak_command, args, input))
end

-- arguments:
--   start_row: 0-based index.
--   end_row:   0-based index.
--   number:    whether to output line numbers.
function M.print(start_row, end_row, number)
  local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
  local output = {}
  local prefix_formatter = get_prefix_formatter(number)
  for i,line in ipairs(lines) do
    if string.match(line, "%S") then
      local prefix = prefix_formatter(start_row + 1, i - 1)
      if options.use_ssml then
        line = line:gsub('<', '&lt;'):gsub('>', '&gt;')
      end
      table.insert(output, prefix .. line)
    end
  end
  M.speak(table.concat(output, breakformat()))
end

function M.line_length(row)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  return line and #line or 0
end

function M.tree_align(start_row, end_row)
  local t = buf_text_with_nodes(start_row, 0, end_row, -1)
  for _,tuple in ipairs(t) do
    if tuple.node then tuple.type = tuple.node:type() end
  end
  print(vim.inspect(t))
end

function M.debug_tree(args) M.tree_align(args.line1 - 1, args.line2 - 1) end

function M.print_cmd(args)
  -- TODO handle all ex flags, and allow for no space before flags
  if next(args.fargs) == nil then
    return M.print(args.line1 - 1, args.line2 - 1)
  end

  local line_count = tonumber(args.fargs[1]) or 1
  local number = args.fargs[2]
  local start_row = (args.range == 2 and args.line2 or args.line1) - 1
  local end_row = start_row + line_count - 1
  M.print(start_row, end_row, number)
  local cursor = vim.api.nvim_win_get_cursor(0)
  if cursor[0] ~= end_row + 1 then
    vim.api.nvim_win_set_cursor(0, { end_row + 1, cursor[1] })
  end
end

function M.info(args)
  M.speak(type_format(vim.treesitter.get_node():type()))
end

-------------------- COMMANDS ------------------------------

vim.api.nvim_create_user_command('P', M.print_cmd, {
  desc = 'Voice-print [range] lines.',
  nargs = '*',
  range = true,
})

vim.api.nvim_create_user_command('Z', M.debug_tree, {
  desc = 'Debug-print [range] lines with treesitter nodes',
  range = true,
})

vim.api.nvim_create_user_command('K', M.info, {
  desc = 'Voice-print info about element below cursor',
})

------------------------------------------------------------
return M
