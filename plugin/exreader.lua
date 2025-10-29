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

local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h:h')

local options = {
  speak_command = 'espeak --punct',
  number = 1, -- 0: never, 1: follow 'number', 2: always
  ssml_breakformat = '<break /> ',
  fallback_breakformat = '.\n',
  numberformat = 'line %d%s',
  relativenumber = 0,      -- 0: never, 1: follow 'relativenumber', 2: always
  relativenumberformat = 'newline %d%s',
  skip_empty_lines = true, -- mostly makes sense with number/relativnumber > 0.
  -- explicit number (via ex flag '#') triggers:
  -- 0: nonumber, 1: number, 2: relativenumber
  explicitnumber = 1,
  use_ssml = true,                 -- use Speech Synthesis Markup Language.
  use_treesitter = true,
  use_symbol_pronunciation = true, -- use symbol-to-word mappings
  symbol_files = {
    common = plugin_dir .. '/symbols/common.tsv',
    ssml = plugin_dir .. '/symbols/ssml.tsv',
  },
  pronounce_files = {
    en = 'pronounce/en',
  },
}

local M = {}

-- Symbol pronunciation mappings
local symbol_map = {}

-- Track espeak availability
local speak_command_available = nil

-------------------- SYMBOL LOADING ------------------------

local function check_speech_provider()
  if speak_command_available == true then
    return true
  end

  -- Extract just the command name (first word) from speak_command
  local command = options.speak_command:match('^(%S+)')

  -- Check if command exists
  local handle = io.popen('command -v ' .. command .. ' 2>/dev/null')
  if handle then
    local result = handle:read('*a')
    handle:close()
    speak_command_available = result ~= ''
  else
    speak_command_available = false
  end

  if not speak_command_available then
    vim.notify(
      'exreader: ' .. command .. ' not found. Install or configure speak_command.',
      vim.log.levels.ERROR
    )
  end

  return speak_command_available
end

local function load_tsv(filepath)
  local mappings = {}
  local file = io.open(filepath, 'r')
  if not file then
    vim.notify('exreader: Could not open ' .. filepath, vim.log.levels.WARN)
    return mappings
  end

  for line in file:lines() do
    -- Skip empty lines and comments
    if line:match('%S') and not line:match('^%s*#') then
      local symbol, word = line:match('^([^\t]+)\t+(.+)$')
      if symbol and word then
        mappings[symbol] = word:gsub('%s+$', '') -- trim trailing whitespace
      end
    end
  end

  file:close()
  return mappings
end

local function init_symbol_maps()
  -- Load common symbol mappings
  symbol_map = {
    common = load_tsv(options.symbol_files.common),
    ssml = load_tsv(options.symbol_files.ssml),
  }

  -- Load language-specific aliases
  local lang_aliases = {
    en = require(options.pronounce_files.en),
  }

  -- Resolve aliases: replace references with actual words
  for _, collection in pairs(symbol_map) do
    for token, key in pairs(collection) do
      local alias = lang_aliases['en'][key]
      if alias then
        collection[token] = alias
      end
    end
  end
end

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

  local output = { {}, }

  local function insert_row(node, col) -- col exclusive
    local text = lines[1 + printed_row - start_row]:sub(printed_col + 1, col)
    if #text == 0 then return end
    table.insert(output[#output], {
      text = text,
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
      table.insert(output, {})
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
    for _, tree in ipairs(parser:parse()) do
      add_tree_to_output(tree)
    end
  end
  ensure_output_until(end_row, end_col + 1)

  return output
end

-- TODO distinguish short breaks between nodes and long breaks for newline
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

local function relativenumber_formatter(_, offset)
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

local function pronounce(str)
  local result = {}
  local break_str = breakformat()

  local symbol_tables = {}
  if options.use_symbol_pronunciation then
    table.insert(symbol_tables, 'common')
  end
  if options.use_ssml then
    table.insert(symbol_tables, 'ssml')
  end

  -- Process character by character
  for i = 1, #str do
    local char = str:sub(i, i)
    local substituted = false
    for _, symbol_table in pairs(symbol_tables) do
      local v = symbol_map[symbol_table][char]
      if v then
        if type(v) == 'string' then
          table.insert(result, v)
        elseif options.use_ssml then
          if v.pitch then
            local pitch = '<prosody pitch="' .. v.pitch .. '">'
            table.insert(result, pitch .. v.ssml .. '</prosody>')
          else
            table.insert(result, v.ssml)
          end
        else
          table.insert(result, v.plain)
        end
        table.insert(result, break_str)
        substituted = true
        break
      end
    end
    if not substituted then
      table.insert(result, char)
    end
  end

  return table.concat(result)
end

-------------------- PUBLIC --------------------------------

function M.speak(str)
  if not check_speech_provider() then
    return
  end

  local args = options.use_ssml and '-m' or ''
  local input = vim.fn.shellescape(str)
  local result = os.execute(fmt('%s %s %s', options.speak_command, args, input))

  if result ~= 0 and result ~= true then
    vim.notify('exreader: speak command failed', vim.log.levels.WARN)
  end
end

---@param start_row number 0-based index.
---@param end_row number 0-based index.
---@param number number line number output mode
function M.print(start_row, end_row, number)
  local output = {}
  -- TODO factor out shared code
  if options.use_treesitter then
    local prefix_formatter = get_prefix_formatter(number)
    local lines = buf_text_with_nodes(start_row, 0, end_row, -1)
    for i, line in ipairs(lines) do
      if not options.skip_empty_lines or #line > 0 then
        local prefix = prefix_formatter(start_row + 1, i - 1)
        local line_text = {}
        for _, node in ipairs(line) do
          table.insert(line_text, pronounce(node.text))
        end
        table.insert(output, prefix .. table.concat(line_text, breakformat()))
      end
    end
  else
    local prefix_formatter = get_prefix_formatter(number)
    local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
    for i, line in ipairs(lines) do
      if not options.skip_empty_lines or string.match(line, "%S") then
        local prefix = prefix_formatter(start_row + 1, i - 1)
        table.insert(output, prefix .. pronounce(line))
      end
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
  for _, tuple in ipairs(t) do
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

function M.setup(user_options)
  -- Merge user options with defaults
  if user_options then
    options = vim.tbl_deep_extend('force', options, user_options)
  end

  -- Load symbol maps
  init_symbol_maps()
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

-------------------- INITIALIZATION ------------------------

-- Auto-initialize with default settings
init_symbol_maps()

------------------------------------------------------------
return M
