require 'csv'
require 'yaml'

PLUGIN_DIR = File.dirname(File.expand_path(__FILE__), 3)

def read_symbols(ftype)
  CSV.readlines(File.join(PLUGIN_DIR, 'symbols', ftype + '.tsv'),
                col_sep: "\t",
                quote_char: nil).to_h
end

def read_pronounce(language)
  YAML
    .parse_file(File.join(PLUGIN_DIR, 'pronounce', language + '.yaml'))
    .to_ruby
end

$pronounce = read_pronounce('en')
$ftype = read_symbols('common')
$ftype_matcher = Regexp.escape($ftype.keys.join)

Neovim.plugin do |plug|
  plug.command(:P, range: true, nargs: '*') do |
    nvim,
    *args,
    range_begin,
    range_end
  |
    position = nvim.current.window.cursor
    p_cmd = "#{range_begin},#{range_end}p#{args.join(' ')}"
    p_output = nvim.command_output(p_cmd) # read lines
    p_output.gsub!(/[#{$ftype_matcher}]/) { |k|
      symbol = $ftype[k]
      pronunciation = $pronounce[symbol] || symbol
      " #{pronunciation} "
    }
    system 'espeak', p_output
    nvim.current.window.cursor = position
    nvim.command(p_cmd) # also generate output
  end

  # plug.autocmd(:BufReadPost) do |nvim|
  #   # $ftype = read_symbols(ftype)
  # end

  # plug.ui_attach(999, 999, {}) do |*a|
  #   Neovim.logger << a.inspect
  # end
end
