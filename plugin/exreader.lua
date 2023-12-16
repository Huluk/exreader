-- minimum neovim version: 0.7
--
-- NOTE: 'row' is 0-indexed, 'line' is 1-indexed when it describes an index.

-------------------- VARIABLES -----------------------------

local fmt = string.format
local ts_utils = require 'nvim-treesitter.ts_utils'

local options = {
  speak_command = 'espeak',
  number = 1, -- 0: never, 1: follow 'number', 2: always
  numberformat = 'line %d: ',
  relativenumber = 0, -- 0: absolute, 1: follow 'relativenumber', 2: always
  relativenumberformat = 'newline %d: ',
  -- explicit number (via ex flag '#') triggers:
  -- 0: nonumber, 1: number, 2: relativenumber
  explicitnumber = 1,
  use_treesitter = 1,
}

local M = {}

-------------------- HELPERS -------------------------------

-- following TSNode convention, end_row is inclusive, end_col exclusive.
-- end_col = -1 means until end of line.
local function buf_text_with_nodes(start_row, start_col, end_row, end_col)
  if start_row > end_row or
    (start_row == end_row and end_col >= 0 and start_col >= end_col) then
    return
  end
  -- TODO should we fail here when out of bounds?
  local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
  if end_col < 0 then
    local last_line = lines[1 + end_row - start_row]
    end_col = last_line and #last_line or 0
  end

  local function overlapping_named_descendant(node)
    return node:named_descendant_for_range(
      start_row, start_col, end_row, end_col)
  end

  local printed_row = start_row
  local printed_col = start_col -- exclusive

  local output = {}

  -- TODO improve naming
  local function ensure_output_until(row, col, node)
    if row < printed_row or (row == printed_row and col < printed_col) then
      return
    end
    local nt = ''
    if node then nt = node:type() end
    while printed_row < row do
      table.insert(output, {
        text = lines[1 + printed_row - start_row]:sub(printed_col),
        node = node,
      })
      printed_row = printed_row + 1
      printed_col = 0
    end
    if row < printed_row or col <= printed_col then
      return
    end
    table.insert(output, {
      text = lines[1 + row - start_row]:sub(printed_col, col - 1),
      node = node,
    })
    printed_col = col
  end

  local function output_node_until(node, row, col)
    -- TODO handle node:missing()
    if not node:named() then
      ensure_output_until(row, col)
    else
      ensure_output_until(row, col, node)
    end
  end

  local function add_to_output(node, surrounding_named_node)
    for child in node:iter_children() do
      local child_row1, child_col1, _ = child:start()
      output_node_until(node, child_row1, child_col1)
      if node:named() then
        add_to_output(child, node)
      else
        add_to_output(child, surrounding_named_node)
      end
    end
    local row2, col2, _ = node:end_()
    if node:named() then
      output_node_until(node, row2, col2 + 1)
    end
  end

  local function add_tree_to_output(tree)
    local node = overlapping_named_descendant(tree:root())
    local row, col, _ = node:start()
    ensure_output_until(row, col)
    add_to_output(node, node)
  end

  for _,tree in ipairs(vim.treesitter.get_parser():parse()) do
    add_tree_to_output(tree)
  end
  ensure_output_until(end_row, end_col + 1)

  return output
end

local function none_formatter(_, _) return '' end

local function linenumber_formatter(number, offset)
  return fmt(options.numberformat, number + offset)
end

local function relativenumber_formatter(number, offset)
  if offset == 0 then
    return ''
  else
    return fmt(options.relativenumberformat, offset)
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

-------------------- PUBLIC --------------------------------
function M.speak(str)
  os.execute(fmt('%s %s', options.speak_command, vim.fn.shellescape(str)))
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
    local prefix = prefix_formatter(start_row + 1, i - 1)
    table.insert(output, prefix .. line)
  end
  M.speak(table.concat(output, '.\n'))
end

function M.line_length(row)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  return line and #line or 0
end

function M.tree_align(start_row, end_row)
  local t = buf_text_with_nodes(start_row, 0, end_row, -1)
  print(vim.inspect(t))
  for _,tuple in ipairs(t) do
    local type = ''
    if tuple.node then type = tuple.node:type() end
    M.speak(type)
  end
end

-- TODO rm this and cmd
function M.ta(args) M.tree_align(args.line1 - 1, args.line2 - 1) end

function M.print_cmd(args)
  -- TODO handle all ex flags, and allow for no space before flags
  if next(args.fargs) == nil then
    return M.print(args.line1 - 1, args.line2 - 1)
  end

  local line_count = tonumber(args.fargs[1]) or 1
  local number = args.fargs[2]
  local start_row
  if args.range == 2 then
    start_row = args.line2 - 1
  else
    start_row = args.line1 - 1
  end
  M.print(start_row, start_row + line_count - 1, number)
  -- TODO move cursor
end

-------------------- COMMANDS ------------------------------
vim.api.nvim_create_user_command('P', M.print_cmd, {
  desc = 'Voice-print [range] lines.',
  nargs = '*',
  range = true,
})

vim.api.nvim_create_user_command('Z', M.ta, {
  range = true,
})

------------------------------------------------------------
return M
